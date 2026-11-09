import CaptureKit
import Darwin
import Foundation

struct AgentReply: Codable, Equatable {
  var ok: Bool
  var code: Int32
  var text: String
  var error: String?

  static func success(text: String = "", code: Int32 = 0) -> AgentReply {
    AgentReply(ok: true, code: code, text: text, error: nil)
  }

  static func failure(_ message: String, code: Int32 = 1) -> AgentReply {
    AgentReply(ok: false, code: code, text: "", error: message)
  }
}

/// One menu bar process listens on a Unix socket. Later launches hand work to it.
enum AgentBridge {
  private static let server = Server()

  static var socketURL: URL {
    socketURLOverride ?? AnnotatorFiles.supportDirectory.appendingPathComponent("agent.sock")
  }

  @discardableResult
  static func acquireLock() -> Bool {
    server.acquireLock()
  }

  static func start(handler: @escaping @MainActor (LaunchRequest) -> AgentReply) -> Bool {
    server.start(handler: handler)
  }

  static func stop() {
    server.stop()
  }

  /// `nil` means no agent is listening. A reply means the agent accepted the connection.
  static func send(_ request: LaunchRequest) -> AgentReply? {
    server.send(request)
  }

  /// In-process encode, listen, and decode check. Used by `--protocol-self-test`.
  static func runProtocolSelfTest() -> Int32 {
    if LaunchRequest.parse(["AnnotatorBin", "--settings"]) != .settings {
      fputs("protocol self-test: --settings did not parse\n", stderr)
      return 1
    }
    if case .capture = LaunchRequest.parse(["AnnotatorBin", "--capture"]) {
    } else {
      fputs("protocol self-test: --capture did not parse\n", stderr)
      return 1
    }
    if LaunchRequest.parse(["AnnotatorBin", "--settings", "--annotator-handoff"]) != .settings {
      fputs("protocol self-test: handoff flag changed --settings\n", stderr)
      return 1
    }
    if LaunchRequest.parse(["Annotator", "-psn_0_1"]) != .agent {
      fputs("protocol self-test: Finder -psn_ did not parse as agent\n", stderr)
      return 1
    }
    let roundTrips: [LaunchRequest] = [
      .agent,
      .settings,
      .updates,
      .activate,
      .ocr,
      .clipboard,
      .reopen,
      .capture(CaptureOptions(window: true, fullScreen: false, repeatLast: true, delay: 3)),
      .image(path: "/tmp/shot.png", wait: true),
      .file(path: "/tmp/shot.png"),
    ]
    for sample in roundTrips {
      let parsed = LaunchRequest.parse(["Annotator"] + sample.forwardingArguments)
      if parsed != sample {
        fputs("protocol self-test: \(String(describing: sample)) did not round trip\n", stderr)
        return 1
      }
    }
    if Bundle.main.bundleURL.pathExtension == "app" {
      let name = BundleExecutable.currentURL.lastPathComponent
      if name == "AnnotatorBin"
        && (BundleExecutable.isBundleExecutable
          || !BundleExecutable.bundleExecutablePath.hasSuffix("/Contents/MacOS/Annotator")) {
        fputs(
          "protocol self-test: CFBundleExecutable resolved to \(BundleExecutable.bundleExecutablePath)\n",
          stderr
        )
        return 1
      }
      if name == "Annotator" && !BundleExecutable.isBundleExecutable {
        let running = BundleExecutable.currentPath
        let expected = BundleExecutable.bundleExecutablePath
        fputs("protocol self-test: bundle executable was not recognized (\(running) vs \(expected))\n", stderr)
        return 1
      }
    } else if BundleExecutable.isBundleExecutable {
      fputs("protocol self-test: a non-bundle path was treated as the agent executable\n", stderr)
      return 1
    }

    // sun_path holds 104 bytes. A long NSTemporaryDirectory path would fail to bind.
    let socketPath = "/tmp/annotator-proto-\(getpid()).sock"
    socketURLOverride = URL(fileURLWithPath: socketPath)
    defer {
      stop()
      socketURLOverride = nil
      try? FileManager.default.removeItem(atPath: socketPath)
    }

    let box = SelfTestBox()
    guard start(handler: { request in
      box.store(request)
      return .success(text: "ok")
    }) else {
      fputs("protocol self-test: could not listen\n", stderr)
      return 1
    }

    DispatchQueue.global(qos: .userInitiated).async {
      box.storeReply(send(.settings))
    }
    let deadline = Date().addingTimeInterval(5)
    while box.reply() == nil && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    guard let reply = box.reply(), reply.ok, box.request() == .settings else {
      fputs("protocol self-test: settings round trip failed (\(String(describing: box.reply())))\n", stderr)
      return 1
    }
    return 0
  }

  fileprivate static var socketURLOverride: URL?
}

private final class Server {
  private var lockFD: Int32 = -1
  private var listenFD: Int32 = -1
  private var source: DispatchSourceRead?
  private var handler: (@MainActor (LaunchRequest) -> AgentReply)?

  func acquireLock() -> Bool {
    if lockFD >= 0 { return true }
    let url = AnnotatorFiles.supportDirectory.appendingPathComponent("agent.lock")
    let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
    if fd < 0 { return false }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
      close(fd)
      return false
    }
    lockFD = fd
    return true
  }

  func start(handler: @escaping @MainActor (LaunchRequest) -> AgentReply) -> Bool {
    self.handler = handler
    let path = AgentBridge.socketURL.path
    if path.utf8.count >= 104 {
      fputs("Annotator: agent socket path is too long\n", stderr)
      return false
    }
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { return false }
    var nosigpipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    guard bindUnix(fd, path: path), listen(fd, 8) == 0 else {
      close(fd)
      unlink(path)
      return false
    }
    chmod(path, 0o600)
    let flags = fcntl(fd, F_GETFL)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    listenFD = fd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
    source.setEventHandler { [weak self] in
      self?.acceptPending()
    }
    source.setCancelHandler {
      close(fd)
    }
    self.source = source
    source.resume()
    return true
  }

  func stop() {
    let source = self.source
    self.source = nil
    listenFD = -1
    // Only the listening process owns the socket. A one-shot editor must not
    // unlink the menu bar agent's socket on the way out.
    if source != nil {
      source?.cancel()
      unlink(AgentBridge.socketURL.path)
    }
    if lockFD >= 0 {
      flock(lockFD, LOCK_UN)
      close(lockFD)
      lockFD = -1
    }
  }

  func send(_ request: LaunchRequest) -> AgentReply? {
    let path = AgentBridge.socketURL.path
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { return nil }
    defer { close(fd) }
    var nosigpipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    guard connectUnix(fd, path: path) else { return nil }
    setTimeout(fd, seconds: 180)
    let packet = AgentPacket(request)
    guard let body = try? JSONEncoder().encode(packet) else {
      return .failure("Could not encode the request.")
    }
    var bytes = body
    bytes.append(0x0A)
    guard writeAll(fd, bytes) else {
      return .failure("The running Annotator did not accept the request.")
    }
    guard let line = readLine(fd, limit: 1_000_000),
          let reply = try? JSONDecoder().decode(AgentReply.self, from: line)
    else {
      return .failure("The running Annotator did not answer.")
    }
    return reply
  }

  private func acceptPending() {
    while true {
      let client = accept(listenFD, nil, nil)
      if client < 0 {
        if errno == EINTR { continue }
        return
      }
      var nosigpipe: Int32 = 1
      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
      // The listening socket is nonblocking, and macOS copies that onto the
      // accepted socket. A nonblocking read runs before the client writes the
      // JSON and comes back empty, which we used to report as
      // "Unrecognized request."
      makeBlocking(client)
      setTimeout(client, seconds: 5)
      handle(client)
    }
  }

  private func handle(_ client: Int32) {
    guard let line = readLine(client, limit: 64_000),
          let packet = try? JSONDecoder().decode(AgentPacket.self, from: line),
          let request = packet.request
    else {
      writeReply(client, .failure("Unrecognized request."))
      close(client)
      return
    }
    // Capture can take a while. Reply from the main queue so a nested
    // screencapture run loop can still accept this work without deadlocking.
    setTimeout(client, seconds: 180)
    let handler = self.handler
    DispatchQueue.main.async {
      let reply = MainActor.assumeIsolated {
        handler?(request) ?? .failure("Annotator is not running.")
      }
      self.writeReply(client, reply)
      close(client)
    }
  }

  private func writeReply(_ fd: Int32, _ reply: AgentReply) {
    guard var data = try? JSONEncoder().encode(reply) else { return }
    data.append(0x0A)
    _ = writeAll(fd, data)
  }
}

private struct AgentPacket: Codable {
  var command: String?
  var window: Bool?
  var fullScreen: Bool?
  var repeatLast: Bool?
  var delay: Int?
  var path: String?
  var wait: Bool?
  var ok: Bool?
  var code: Int?
  var text: String?
  var error: String?

  init(_ request: LaunchRequest) {
    switch request {
    case .agent:
      command = "agent"
    case .activate:
      command = "activate"
    case .settings:
      command = "settings"
    case .updates:
      command = "updates"
    case .capture(let options):
      command = "capture"
      window = options.window
      fullScreen = options.fullScreen
      repeatLast = options.repeatLast
      delay = options.delay
    case .clipboard:
      command = "clipboard"
    case .reopen:
      command = "reopen"
    case .ocr:
      command = "ocr"
    case .image(let path, let wait):
      command = "image"
      self.path = path
      self.wait = wait
    case .file(let path):
      command = "file"
      self.path = path
    }
  }

  var request: LaunchRequest? {
    switch command {
    case "agent":
      return .agent
    case "activate":
      return .activate
    case "settings":
      return .settings
    case "updates":
      return .updates
    case "capture":
      return .capture(CaptureOptions(
        window: window ?? false,
        fullScreen: fullScreen ?? false,
        repeatLast: repeatLast ?? false,
        delay: delay ?? 0
      ))
    case "clipboard":
      return .clipboard
    case "reopen":
      return .reopen
    case "ocr":
      return .ocr
    case "image":
      guard let path, !path.isEmpty else { return nil }
      return .image(path: path, wait: wait ?? false)
    case "file":
      guard let path, !path.isEmpty else { return nil }
      return .file(path: path)
    default:
      return nil
    }
  }
}

private func bindUnix(_ fd: Int32, path: String) -> Bool {
  mutateAddress(path: path) { pointer, length in
    Darwin.bind(fd, pointer, length) == 0
  }
}

private func connectUnix(_ fd: Int32, path: String) -> Bool {
  mutateAddress(path: path) { pointer, length in
    Darwin.connect(fd, pointer, length) == 0
  }
}

private func mutateAddress(path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Bool) -> Bool {
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
  guard path.utf8.count < 104, let cString = strdup(path) else { return false }
  defer { free(cString) }
  strncpy(&addr.sun_path.0, cString, 103)
  return withUnsafePointer(to: &addr) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
      body(sock, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
  }
}

private func makeBlocking(_ fd: Int32) {
  let flags = fcntl(fd, F_GETFL)
  if flags >= 0 {
    _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
  }
}

private func setTimeout(_ fd: Int32, seconds: Int) {
  var timeout = timeval(tv_sec: seconds, tv_usec: 0)
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
  data.withUnsafeBytes { raw in
    guard let base = raw.baseAddress else { return false }
    var sent = 0
    while sent < raw.count {
      let n = write(fd, base.advanced(by: sent), raw.count - sent)
      if n > 0 {
        sent += n
        continue
      }
      if n < 0 && errno == EINTR { continue }
      return false
    }
    return true
  }
}

private final class SelfTestBox: @unchecked Sendable {
  private let lock = NSLock()
  private var seen: LaunchRequest?
  private var result: AgentReply?

  func store(_ request: LaunchRequest) {
    lock.lock()
    seen = request
    lock.unlock()
  }

  func storeReply(_ reply: AgentReply?) {
    lock.lock()
    result = reply
    lock.unlock()
  }

  func request() -> LaunchRequest? {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  func reply() -> AgentReply? {
    lock.lock()
    defer { lock.unlock() }
    return result
  }
}

private func readLine(_ fd: Int32, limit: Int) -> Data? {
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while data.count < limit {
    let n = read(fd, &buffer, buffer.count)
    if n > 0 {
      data.append(buffer, count: n)
      if let newline = data.firstIndex(of: 0x0A) {
        return Data(data[..<newline])
      }
      continue
    }
    if n < 0 && errno == EINTR { continue }
    break
  }
  return data.isEmpty ? nil : data
}
