# Annotator

**Capture a screen region on macOS, mark it up with keyboard shortcuts, and copy a PNG to your clipboard** — with an optional Raycast workflow and on-device OCR for “copy text from screen.”

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/rhagerty32/annotator/actions/workflows/ci.yml/badge.svg)](https://github.com/rhagerty32/annotator/actions/workflows/ci.yml)

<!-- Replace with a short screen recording or screenshot of the annotation panel -->
<p align="center">
  <img src="raycast/assets/icon.png" alt="Annotator icon (replace with app screenshot)" width="128" />
  <br />
  <em>Add a GIF or screenshot of the floating editor here when you have one.</em>
</p>

## Download

**macOS 14 or later.** Download the latest [Annotator.dmg](https://github.com/rhagerty32/annotator/releases/latest) from GitHub Releases, open it, and drag **Annotator** to **Applications**.

The app is an accessory: no Dock icon. The first capture asks for Screen Recording permission.

To update later, open Annotator and choose **Check for Updates…** from the Annotator menu or the Help menu. Sparkle downloads the new disk image and installs it.

The Raycast extension looks for `/Applications/Annotator.app/Contents/MacOS/Annotator` by default. Override **Annotator binary** in the extension preferences if you want a different build.

Building from source is the contributor path, below.

## Features

- **Region, window, or full-screen capture** via Raycast commands or CLI flags (`screencapture` under the hood).
- **Floating annotation panel** — accessory app with no Dock icon; **S** copies compressed PNG and quits, **Esc** cancels.
- **Keyboard-driven tools** — shapes, arrows, draw, text, spotlight, redact, crop, numbered steps, and more (press **?** in the panel for the cheat sheet).
- **Copy text from screen** — same region picker, on-device Vision OCR, results to the clipboard without opening the editor.
- **Reopen last shot** — restores the previous capture and mark-up where supported.
- **Raycast extension** in `raycast/` — hotkey-friendly commands that launch the installed app, or a binary you built.

## Build from source

Contributors need **macOS 14+**, [Swift](https://swift.org) 5.9+ (Xcode or Command Line Tools), **Node.js**, and optionally [Raycast](https://www.raycast.com).

```bash
git clone https://github.com/rhagerty32/annotator.git
cd annotator
npm --prefix raycast install
./reload-raycast.sh
```

That builds the binaries, builds the Raycast extension, and restarts Raycast if it is installed.

Then in Raycast:

1. Command Palette → **Import Extension**
2. Choose the `raycast` folder inside this repo (not `dist`)
3. Optional: extension preferences → **Annotator binary** → a path you built, such as  
   `/absolute/path/to/annotator/.build/release/Annotator`  
   Leave the preference at `/Applications/Annotator.app/Contents/MacOS/Annotator` to use the installed app. If that app is not installed, the extension falls back to a binary next to the repo.

Grant **Screen Recording** permission when macOS prompts `screencapture`.

### After a git pull

Raycast caches the old extension until you rebuild and bounce it.

```bash
git pull
./reload-raycast.sh
```

### Commands

```bash
npm run build:annotator          # swift build -c release, plus Sparkle next to the binary
npm run package:app              # dist/Annotator.app (ad-hoc signed, not for distribution)
npm run package:dmg              # dist/Annotator.dmg with an Applications alias
npm --prefix raycast run build   # Raycast extension only
./reload-raycast.sh              # binaries + Raycast restart
```

Binaries: `.build/release/Annotator` and `.build/release/Capture`. The app bundle also contains `Contents/MacOS/Capture`, which the Raycast fast path launches.

Quick try without Raycast:

```bash
npm run annotate
```

Packaging a signed release is documented in [docs/release.md](docs/release.md). Do not commit certificates, API keys, or the Sparkle private key.

## How it works

1. A Raycast command (or a CLI flag) launches the `Annotator` binary.
2. macOS `screencapture` takes the region, window, or display.
3. Annotator opens as a floating accessory panel — no Dock icon.
4. You annotate. **S** copies a compressed PNG and quits. **Esc** cancels.

Copy Text skips the panel: capture → read pixels with Vision → HUD → clipboard.

## Usage

### Raycast

Bind hotkeys to whichever commands you use.

| Command | What it does |
|---|---|
| **Annotate Screenshot** | Crosshair region, then the editor |
| **Annotate Window** | Click a window, then the editor |
| **Annotate Full Screen** | Display under the cursor, then the editor |
| **Annotate Last Region** | Same rectangle as last time, no crosshair |
| **Annotate in 3s** | Wait 3 seconds, then region capture (menus that vanish) |
| **Annotate Clipboard** | Open whatever image is already on the clipboard |
| **Copy Text from Screen** | Region capture → OCR → clipboard. Edit after you paste. |
| **Reopen Last Shot** | Open the last screenshot and its marks again |

### Terminal

```bash
open -a Annotator                         # installed app, blank canvas
/Applications/Annotator.app/Contents/MacOS/Annotator --capture
/Applications/Annotator.app/Contents/MacOS/Annotator --capture --window
/Applications/Annotator.app/Contents/MacOS/Annotator --capture --fullscreen
/Applications/Annotator.app/Contents/MacOS/Annotator --capture --repeat
/Applications/Annotator.app/Contents/MacOS/Annotator --capture --delay 3
/Applications/Annotator.app/Contents/MacOS/Annotator --clipboard
/Applications/Annotator.app/Contents/MacOS/Annotator --ocr
/Applications/Annotator.app/Contents/MacOS/Annotator --image shot.png
```

A source build uses `.build/release/Annotator` with the same flags. `npm run annotate` captures a region with that binary.

### Annotating

Press **?** in the panel for the full cheat sheet. Hold **space** to see every tool, then tap its letter. Space types normally while a text field is active.

| | |
|---|---|
| **Space** | Hold: tool palette · tap a letter to pick |
| **V R C A L D X T** | Select, rectangle, circle, arrow, line, draw, cross, text |
| **H I N B K J** | Fill, spotlight, numbered steps, redact, crop, slice |
| **1–0 −** | Colors (− is black) |
| **[ ]** | Stroke |
| **⇧** | Constrain (square / 45°) |
| **⌥** | Draw from center, or a headless line with **A** |
| **L** | Toggle arrowhead |
| **S** | Copy and close |
| **⌘C** | Copy and stay |
| **⇧S / ⌘S** | Save PNG |
| **Esc** | Deselect, then quit |

Drag an arrow’s midpoint to curve it. Drag a rectangle’s top-edge dot to round the corners. **⌘,** opens canvas settings (void, chrome, checker).

### Copy text from screen

Same region picker as annotate. After you release, a small HUD reads the pixels. When it says **Copied**, paste wherever you already were. Esc in the picker cancels.

## Project layout

```
Sources/Annotator/   Swift app (panel, tools, OCR, Sparkle menu)
Sources/CaptureKit/  Shared capture helpers + Capture CLI
packaging/           Bundle id, entitlements, Sparkle feed settings
scripts/             App bundle, DMG, notarization, appcast
raycast/             Raycast extension (launches the binary)
docs/release.md      How to tag a signed release
reload-raycast.sh    Build both + restart Raycast
```

## Contributing

We welcome issues and pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md) for build steps, branch flow, and code style. Please read our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © Ryan Hagerty

In-app updates use [Sparkle](https://sparkle-project.org) (MIT). The Sparkle license is copied into the app bundle at package time.
