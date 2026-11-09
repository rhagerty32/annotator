# Contributing to Annotator

Thanks for your interest in contributing. This project is a macOS screenshot
annotator with an optional Raycast extension. Patches that keep the app
behavior unchanged unless the issue explicitly asks for a change are easiest
to review.

## What you need

- **macOS 14 (Sonoma) or later** — the Swift app targets macOS only.
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
`.build/release/Annotator` and `.build/release/Capture`, with Sparkle.framework
beside them so the editor can launch.

`npm run package:app` builds `dist/Annotator.app` (ad-hoc signed). That local
bundle is for trying the menu bar and the Capture helper. It is not notarized
and must not be attached to a GitHub Release. Signed releases are described in
[docs/release.md](docs/release.md).

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
choose the `raycast` folder in this repo). The default **Annotator binary**
preference is `/Applications/Annotator.app/Contents/MacOS/Annotator`. To test a
binary you just built, set that preference to the absolute path of
`.build/release/Annotator`. If the Applications path is missing, the extension
still tries the `.build/release` locations.

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
- No third-party Swift dependencies beyond Sparkle, which ships in-app updates.
  Stay within the standard library, AppKit, SwiftUI, system frameworks
  (e.g. Vision for OCR), and Sparkle.
- Do not commit certificates, `.p12` / `.p8` files, or the Sparkle EdDSA private key.
- Run `swift build` (debug is fine) before pushing.

### TypeScript (`raycast/src/`)

- `tsconfig.json` uses **strict** mode; fix type errors rather than loosening
  checks.
- Match the style of neighboring command files (`annotate.ts`, `launch.ts`, etc.).
- Built output under `raycast/*.js` is generated — edit `raycast/src/` only,
  then `npm --prefix raycast run build` if you change the extension.

### Shell scripts

- `set -euo pipefail` where scripts already use it; keep scripts idempotent.

## Reporting bugs and suggesting features

Use the [GitHub issue templates](.github/ISSUE_TEMPLATE/) so we get the details
we need (macOS version, steps to reproduce, etc.).

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind
and constructive in issues and pull requests.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
