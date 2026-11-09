# Contributing to Annotator

Thanks for your interest in contributing. This project is a macOS screenshot
annotator with an optional Raycast extension. Patches that keep the app
behavior unchanged unless the issue explicitly asks for a change are easiest
to review.

## What you need

- **macOS 14 (Sonoma) or later.** The Swift app targets macOS only.
- **Swift 5.9+** via [Xcode](https://developer.apple.com/xcode/) or
  [Command Line Tools](https://developer.apple.com/download/all/).
- **Node.js 18+** and npm (for the Raycast extension under `raycast/`).
- **[Raycast](https://www.raycast.com)** (optional but recommended for
  exercising the extension end-to-end).

Grant **Screen Recording** permission when macOS prompts you during capture.

## Build from source

Clone the repository and build the Swift binaries:

```bash
git clone https://github.com/rhagerty32/annotator.git
cd annotator
npm run build:annotator
```

That runs `swift build -c release` and leaves executables at
`.build/release/Annotator` and `.build/release/Capture`.

### Raycast extension

```bash
npm --prefix raycast install
npm --prefix raycast run build
```

For a one-shot rebuild of both layers and a Raycast restart (when Raycast is
installed locally):

```bash
./reload-raycast.sh
```

Import the extension from Raycast’s command palette (**Import Extension** →
choose the `raycast` folder in this repo). If the binary is not auto-detected,
set **Annotator binary** in extension preferences to the absolute path of
`.build/release/Annotator`.

### Quick manual test

```bash
npm run annotate
```

Select a region; the floating editor should open. **S** copies a PNG to the
clipboard and quits. **Esc** cancels.

```bash
.build/release/Annotator --ocr
```

Runs region capture and on-device OCR to the clipboard (no editor).

## Tests and lint

There is **no automated Swift test target** in `Package.swift` yet. Please
exercise capture and annotation manually before opening a pull request.

For the Raycast extension:

```bash
npm --prefix raycast run lint    # requires Raycast CLI (`ray`), when installed
```

CI (see `.github/workflows/ci.yml`) builds the Swift package on macOS and
type-checks the Raycast TypeScript sources.

## Branch and pull request flow

1. Fork the repository and create a branch from `main`.
2. Use a short, descriptive branch name (for example `fix/ocr-hud-copy` or
   `docs/readme-raycast-path`).
3. Keep changes focused; split unrelated work into separate pull requests.
4. Open a pull request against `main` and fill out the PR template.
5. Link any related issue in the description.

Maintainers may squash-merge. You do not need to force-push unless asked.

## Code style

### Swift (`Sources/`)

- Follow existing patterns in the file you edit.
- Prefer clear names over abbreviations; keep view logic in SwiftUI where the
  project already does.
- No third-party Swift dependencies, with one exception: [Sparkle](https://sparkle-project.org)
  2.7.1, pinned in `Package.swift`, for Check for Updates. Hotkeys use the system
  `RegisterEventHotKey` API and do not add a package. Everything else stays in
  the standard library, AppKit, SwiftUI, and system frameworks (Vision for OCR).
- Run `swift build` (debug is fine) before pushing.

### TypeScript (`raycast/src/`)

- `tsconfig.json` uses **strict** mode; fix type errors rather than loosening
  checks.
- Match the style of neighboring command files (`annotate.ts`, `launch.ts`, etc.).
- Built output under `raycast/*.js` is generated. Edit `raycast/src/` only,
  then `npm --prefix raycast run build` if you change the extension.

### Shell scripts

- `set -euo pipefail` where scripts already use it; keep scripts idempotent.

## Menu bar shortcuts

Opening `Annotator.app` with no arguments starts the menu bar agent. `Annotator --capture` and the other CLI flags still run one-shot when that agent is not running. When it is running, they connect to `~/Library/Application Support/Annotator/agent.sock` and exit.

Shortcuts are stored in `shortcuts.json` in that same folder. The default Capture Region shortcut is Control-Option-A. Launch at Login uses `SMAppService` and only works for the installed `.app`.

Quit the menu bar app before you rebuild if you need the new binary. `./reload-raycast.sh` quits Annotator and AnnotatorBin after a successful build.

## Releasing updates

Check for Updates uses Sparkle 2.7.1. The feed URL baked into `packaging/Info.plist` is:

`https://github.com/rhagerty32/annotator/releases/latest/download/appcast.xml`

`CFBundleVersion` and `CFBundleShortVersionString` are both the dotted version (`1.1.0` in this tree). Sparkle compares `CFBundleVersion` with `sparkle:version` in the appcast. A release tag `v1.2.0` is published as version `1.2.0`. The next tag must be greater than the version people already installed, or their app will not offer it.

Publishing a GitHub Release (or running the Release workflow with a tag) is the path that uploads:

- `Annotator.dmg` for the first install
- `Annotator-<version>.zip` containing `Annotator.app` at the archive root (the file Sparkle installs)
- `appcast.xml`

The workflow is `.github/workflows/release.yml`. It calls `scripts/publish-release.sh`.

The job ad-hoc signs the app (`codesign --sign -`) and still publishes the disk image, the zip, and `appcast.xml`. Sparkle accepts that update when the zip's `sparkle:edSignature` matches `SUPublicEDKey` in the installed app. The new app's ad-hoc signature only has to be intact. It does not have to match a Developer ID.

Apple Developer ID and notarization secrets are optional. If every one of them is set, the job uses them. If any are missing, it skips them and continues.

The one required secret is `SPARKLE_PRIVATE_KEY`: the base64 EdDSA seed from Sparkle 2.7.1 `generate_keys -x` (32 bytes after decoding). Do not commit it. `sign_update` from the Sparkle 2.7.1 tools must be the signer, which is what the workflow downloads.

Put the matching public key in `packaging/Info.plist` as `SUPublicEDKey` (32 bytes, base64). The packager keeps that value unless `SPARKLE_PUBLIC_ED_KEY` is set.

On a Mac:

```bash
generate_keys --account annotator
generate_keys --account annotator -x "$HOME/Desktop/annotator_sparkle_ed25519.key"
gh secret set SPARKLE_PRIVATE_KEY < "$HOME/Desktop/annotator_sparkle_ed25519.key"
rm -P "$HOME/Desktop/annotator_sparkle_ed25519.key"
```

`generate_keys` prints the `SUPublicEDKey` string. Commit that string in the plist, not the private file.

Then publish a GitHub Release whose tag is greater than the installed version, for example `v1.2.0` when people have `1.1.0`.

What the user does:

1. Install `Annotator.dmg`. If macOS says the developer cannot be verified, right-click the app, choose Open, and confirm.
2. Later, choose Check for Updates.
3. Sparkle reads `appcast.xml` from the latest release, downloads `Annotator-<version>.zip`, and checks the EdDSA signature.
4. Choose Install and Relaunch. Sparkle replaces `Annotator.app` and starts the new build. The menu bar agent comes back.

Automatic checks run about once a day. The app does not relaunch in the middle of an annotation. Install and Relaunch is the restart.

### Trying an update against a local feed

1. Install a build whose `SUPublicEDKey` matches the key you will sign with.
2. Build a higher `ANNOTATOR_VERSION`, zip `Annotator.app` with `ditto -c -k --keepParent`, and run `sign_update --ed-key-file <private key file> Annotator-<version>.zip`.
3. Write an appcast with `scripts/write_appcast.py` and serve it: `python3 -m http.server 8741`.
4. Point the installed app at that file and check again:

```bash
defaults write local.annotator AnnotatorUpdateFeedURL http://127.0.0.1:8741/appcast.xml
```

Quit and reopen Annotator so Sparkle reads the override. The shipping feed stays in Info.plist.

## Reporting bugs and suggesting features

Use the [GitHub issue templates](.github/ISSUE_TEMPLATE/) so we get the details
we need (macOS version, steps to reproduce, etc.).

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind
and constructive in issues and pull requests.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
