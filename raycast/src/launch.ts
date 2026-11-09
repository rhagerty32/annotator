import {
  closeMainWindow,
  getPreferenceValues,
  PopToRootType,
  showToast,
  Toast,
} from "@raycast/api";
import { spawn } from "child_process";
import { accessSync, constants } from "fs";
import { homedir, tmpdir } from "os";
import { dirname, join } from "path";

interface Preferences {
  annotatorPath?: string;
}

const installedBinary = "/Applications/Annotator.app/Contents/MacOS/Annotator";

export function resolveBinary(preference?: string): string | null {
  const candidates = [
    preference?.trim(),
    installedBinary,
    join(__dirname, "../.build/release/Annotator"),
    join(__dirname, "../../.build/release/Annotator"),
    join(__dirname, "../../../.build/release/Annotator"),
    join(homedir(), "GROUND/side-projects/annotator/.build/release/Annotator"),
    "/Users/ryan/GROUND/side-projects/annotator/.build/release/Annotator",
  ].filter((p): p is string => Boolean(p));

  for (const path of candidates) {
    try {
      accessSync(path, constants.X_OK);
      return path;
    } catch {
      // try next
    }
  }
  return null;
}

export async function launchAnnotator(
  args: string[],
  options: { wait?: boolean } = {},
): Promise<number | null> {
  const result = await runAnnotator(args, options);
  return result?.code ?? null;
}

export interface FastCapture {
  window?: boolean;
  fullscreen?: boolean;
  repeat?: boolean;
  delay?: number;
}

/**
 * Start screencapture before Raycast closes and before the editor loads.
 * The editor process boots in parallel and opens the PNG when the drag ends.
 */
export async function launchFastCapture(flags: FastCapture = {}): Promise<void> {
  const { annotatorPath } = getPreferenceValues<Preferences>();
  const binary = resolveBinary(annotatorPath);
  if (!binary) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Annotator binary not found",
      message: "Install Annotator.dmg from GitHub Releases, or set the binary preference to a local build.",
    });
    return;
  }

  const capture = join(dirname(binary), "Capture");
  let captureReady = false;
  try {
    accessSync(capture, constants.X_OK);
    captureReady = true;
  } catch {
    captureReady = false;
  }

  if (!captureReady) {
    const args = ["--capture"];
    if (flags.window) args.push("--window");
    if (flags.fullscreen) args.push("--fullscreen");
    if (flags.repeat) args.push("--repeat");
    if (flags.delay) args.push("--delay", String(flags.delay));
    await launchAnnotator(args);
    return;
  }

  const png = join(tmpdir(), `annotator-${process.pid}-${Date.now()}.png`);
  const captureArgs = ["--out", png];
  if (flags.window) captureArgs.push("--window");
  if (flags.fullscreen) captureArgs.push("--fullscreen");
  if (flags.repeat) captureArgs.push("--repeat");
  if (flags.delay) captureArgs.push("--delay", String(flags.delay));

  const grab = spawn(capture, captureArgs, { detached: true, stdio: "ignore" });
  grab.unref();
  const editor = spawn(binary, ["--image", png, "--wait"], {
    detached: true,
    stdio: "ignore",
  });
  editor.unref();

  await closeMainWindow({
    clearRootSearch: true,
    popToRootType: PopToRootType.Immediate,
  });
}

export async function runAnnotator(
  args: string[],
  options: { wait?: boolean } = {},
): Promise<{ code: number; stdout: string } | null> {
  const { annotatorPath } = getPreferenceValues<Preferences>();
  const binary = resolveBinary(annotatorPath);

  if (!binary) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Annotator binary not found",
      message: "Install Annotator.dmg from GitHub Releases, or set the binary preference to a local build.",
    });
    return null;
  }

  await closeMainWindow({
    clearRootSearch: true,
    popToRootType: PopToRootType.Immediate,
  });

  if (!options.wait) {
    const child = spawn(binary, args, {
      detached: true,
      stdio: "ignore",
    });
    child.unref();
    return null;
  }

  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { stdio: ["ignore", "pipe", "ignore"] });
    let stdout = "";
    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? 1, stdout }));
  });
}
