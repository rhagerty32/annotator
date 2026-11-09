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

The workflow is `.github/workflows/release.yml`. It calls `scripts/publish-release.sh`. If any secret below is missing, the job stops before upload and does not publish an unsigned feed.

### What already works in a local build

- The menu bar app, shortcut recorder, Launch at Login, and the Check for Updates button.
- `python3 scripts/package-dmg.py` on a Mac, which embeds `Sparkle.framework` and ad-hoc signs the app when `DEVELOPER_ID_APPLICATION` is unset.
- Raycast flags, handed off to the agent when it is running.

### What is still required for the installed app to update itself

The disk image produced without the secrets below is ad-hoc signed (`codesign --sign -`), same as the packager's default. Gatekeeper and Sparkle both require a Developer ID signature, and Sparkle also requires an EdDSA signature from a keypair whose public half is inside the app that is already installed. An ad-hoc install will not accept a later Developer ID update. Ship one notarized Developer ID build, then later releases can update it.

Add these GitHub Actions secrets on `rhagerty32/annotator` (Settings, Secrets and variables, Actions). Do not commit any of them.

| Secret | What it is |
|---|---|
| `SPARKLE_PUBLIC_ED_KEY` | The `SUPublicEDKey` string printed by `generate_keys`. Safe to commit into `packaging/Info.plist` as well, once you have generated it. |
| `SPARKLE_PRIVATE_KEY` | The EdDSA private key exported by `generate_keys -x`. One line of base64. |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 of a Developer ID Application `.p12` (certificate plus private key). |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password chosen when exporting that `.p12`. |
| `DEVELOPER_ID_APPLICATION` | The codesign identity, for example `Developer ID Application: Ryan Hagerty (TEAMID)`. |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID. |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID. |
| `APPLE_NOTARY_KEY_P8` | Full contents of the `AuthKey_XXXX.p8` file, including the BEGIN and END lines. |

Create the API key in App Store Connect with access to notarize. Create the `.p12` in Keychain Access by exporting the Developer ID Application certificate and its private key. Give the export a password.

### One-time Sparkle key

On a Mac, after `swift build` or from the Sparkle 2.7.1 tools (`bin/generate_keys` inside `Sparkle-2.7.1.tar.xz`):

```bash
generate_keys --account annotator
```

That stores the private key in your login keychain and prints the public key as an `SUPublicEDKey` string.

Put that string in the `SPARKLE_PUBLIC_ED_KEY` secret. You can also add the same key to `packaging/Info.plist` so local Developer ID builds match CI. The packager overwrites it when `SPARKLE_PUBLIC_ED_KEY` is set.

Export the private key for GitHub, then delete the exported file:

```bash
generate_keys --account annotator -x "$HOME/Desktop/annotator_sparkle_ed25519.key"
```

The file is one line. That line is `SPARKLE_PRIVATE_KEY`. `sign_update` must be the 2.7.1 binary, matching `Package.swift`.

Then publish a GitHub Release whose tag is greater than the installed version, for example `v1.2.0` if people have `1.1.0`. The workflow signs the app with Developer ID, notarizes it, staples the ticket, signs the zip with the EdDSA key, and uploads the appcast.

### Trying an update on one Mac before the secrets exist

There is no signed feed in this pull request, so Check for Updates on an ad-hoc build tells you the public key is missing. After you have a keypair and a Developer ID certificate locally:

1. Put the public key in `packaging/Info.plist` under `SUPublicEDKey`.
2. Package and install version `1.1.0` into `/Applications` with `DEVELOPER_ID_APPLICATION` set to your identity, plus the notarization variables if you want Gatekeeper to accept it.
3. Build version `1.2.0` (`ANNOTATOR_VERSION=1.2.0`), zip `Annotator.app` with `ditto -c -k --keepParent`, and run `sign_update --ed-key-file <private key file> Annotator-1.2.0.zip`.
4. Write an appcast with `scripts/write_appcast.py` and serve it: `python3 -m http.server 8741`.
5. Point the installed app at that file and check again:

```bash
defaults write local.annotator AnnotatorUpdateFeedURL http://127.0.0.1:8741/appcast.xml
```

Quit and reopen Annotator so Sparkle reads the override. The override is a developer hook. The shipping feed stays in Info.plist.

Sparkle's update window downloads the zip and, when you choose Install and Relaunch, replaces `Annotator.app` and starts the new build. Automatic checks are on (about once a day). The app does not silently relaunch while you are annotating. Confirming the Sparkle install is the relaunch.

## Reporting bugs and suggesting features

Use the [GitHub issue templates](.github/ISSUE_TEMPLATE/) so we get the details
we need (macOS version, steps to reproduce, etc.).

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind
and constructive in issues and pull requests.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
