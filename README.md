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

## Features

- **Region, window, or full-screen capture** via Raycast commands or CLI flags (`screencapture` under the hood).
- **Floating annotation panel** — accessory app with no Dock icon; **S** copies compressed PNG and quits, **Esc** cancels.
- **Keyboard-driven tools** — shapes, arrows, draw, text, spotlight, redact, crop, numbered steps, and more (press **?** in the panel for the cheat sheet).
- **Copy text from screen** — same region picker, on-device Vision OCR, results to the clipboard without opening the editor.
- **Reopen last shot** — restores the previous capture and mark-up where supported.
- **Raycast extension** in `raycast/` — hotkey-friendly commands that launch the locally built binary.

## Install

You need **macOS 14+**, [Swift](https://swift.org) (Xcode or Command Line Tools), **Node.js**, and optionally [Raycast](https://www.raycast.com).

```bash
git clone https://github.com/rhagerty32/annotator.git
cd annotator
npm --prefix raycast install
./reload-raycast.sh
```

That builds the app, builds the Raycast extension, and restarts Raycast if it is installed.

Then in Raycast:

1. Command Palette → **Import Extension**
2. Choose the `raycast` folder inside this repo (not `dist`)
3. Optional: extension preferences → **Annotator binary** →  
   `/absolute/path/to/annotator/.build/release/Annotator`  
   (usually auto-detected after a build)

Grant **Screen Recording** permission when macOS prompts `screencapture`.

### After a git pull

Raycast caches the old extension until you rebuild and bounce it.

```bash
git pull
./reload-raycast.sh
```

## Build from source

```bash
npm run build:annotator          # swift build -c release
npm --prefix raycast run build   # Raycast extension only
./reload-raycast.sh              # both + Raycast restart
```

Binaries: `.build/release/Annotator` and `.build/release/Capture`.

### App icon and disk image

Ink Trio is the app icon and the drag-to-Applications disk image.

- `assets/icon/ink-trio.png` is the approved 1024 precomposed master. Raycast uses this file.
- `assets/icon/ink-trio.svg` is the vector source. The glass, enamel, and blur live in the raster master.
- `assets/icon/AppIcon-1024.png` is the full-bleed system icon. The dark field fills the square so macOS can mask it.
- `assets/dmg/background.png` (720x440) and `background@2x.png` (1440x880) are the Finder window art. `background.tiff` is the HiDPI image.

```bash
python3 scripts/generate-icons.py
python3 scripts/package-dmg.py
```

`scripts/generate-raycast-icon.swift` copies the master into `raycast/assets/icon.png` (or resamples it). It does not redraw the materials.

On macOS, `package-dmg.py` builds the app, ad-hoc signs it, and writes `dist/Annotator.dmg`. The Finder window content is 720 by 440 points, icons are 128 points, text is 13 points, Annotator.app is centered at (200, 230), and the Applications alias is centered at (520, 230).

Quick try without Raycast:

```bash
npm run annotate
```

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
npm run annotate                          # region, then editor
.build/release/Annotator --capture
.build/release/Annotator --capture --window
.build/release/Annotator --capture --fullscreen
.build/release/Annotator --capture --repeat
.build/release/Annotator --capture --delay 3
.build/release/Annotator --clipboard
.build/release/Annotator --ocr            # Copy Text path
.build/release/Annotator --image shot.png
.build/release/Annotator shot.png
```

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
Sources/Annotator/   Swift app (panel, tools, OCR)
Sources/CaptureKit/  Shared capture helpers + Capture CLI
raycast/             Raycast extension (launches the binary)
reload-raycast.sh    Build both + restart Raycast
```

## Contributing

We welcome issues and pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md) for build steps, branch flow, and code style. Please read our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © Ryan Hagerty
