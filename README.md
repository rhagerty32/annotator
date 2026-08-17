# Annotator

A macOS screenshot annotator. Raycast (or the terminal) grabs a region, a floating panel opens, you mark it up with hotkeys, and **S** copies it to the clipboard.

There is also a **Copy Text from Screen** command: same region picker, then on-device OCR, then the words land on the clipboard. No editor.

## How it works

1. A Raycast command (or a CLI flag) launches the `Annotator` binary.
2. macOS `screencapture` takes the region, window, or display.
3. Annotator opens as a floating accessory panel — no Dock icon.
4. You annotate. **S** copies a compressed PNG and quits. **Esc** cancels.

Copy Text skips the panel: capture → read pixels with Vision → HUD → clipboard.

## Install

You need macOS 14+, [Swift](https://swift.org) (Xcode or Command Line Tools), Node.js, and [Raycast](https://www.raycast.com).

```bash
git clone <this-repo> annotator
cd annotator
npm --prefix raycast install
./reload-raycast.sh
```

That builds the app, builds the Raycast extension, and restarts Raycast.

Then in Raycast:

1. Command Palette → **Import Extension**
2. Choose the `raycast` folder inside this repo (not `dist`)
3. Optional: extension preferences → **Annotator binary** →  
   `/absolute/path/to/annotator/.build/release/Annotator`  
   (usually auto-detected after a build)

Give macOS Screen Recording permission when `screencapture` asks.

## After a git pull

Raycast caches the old extension until you rebuild and bounce it.

```bash
git pull
./reload-raycast.sh
```

## Ways to use it

### Raycast

Bind hotkeys to whichever you actually use.

| Command | What it does |
|---|---|
| **Annotate Screenshot** | Crosshair region, then the editor |
| **Annotate Window** | Click a window, then the editor |
| **Annotate Full Screen** | Display under the cursor, then the editor |
| **Annotate Last Region** | Same rectangle as last time, no crosshair |
| **Annotate in 3s** | Wait 3 seconds, then region capture (menus that vanish) |
| **Annotate Clipboard** | Open whatever image is already on the clipboard |
| **Copy Text from Screen** | Region capture → OCR → clipboard. Edit after you paste. |

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

## Annotating

Press **?** in the panel for the full cheat sheet.

| | |
|---|---|
| **V R C A D T** | Select, rectangle, circle, arrow, draw, text |
| **H I N B X** | Fill, spotlight, numbered steps, redact, crop |
| **1–0** | Colors |
| **[ ]** | Stroke |
| **⇧** | Constrain (square / 45°) |
| **⌥** | Draw from center, or a headless line with **A** |
| **L** | Toggle arrowhead |
| **S** | Copy and close |
| **⌘C** | Copy and stay |
| **⇧S / ⌘S** | Save PNG |
| **Esc** | Deselect, then quit |

Drag an arrow’s midpoint to curve it. Drag a rectangle’s top-edge dot to round the corners. **⌘,** opens canvas settings (void, chrome, checker).

## Copy Text from Screen

Same region picker as annotate. After you release, a small HUD reads the pixels. When it says **Copied**, paste wherever you already were. Esc in the picker cancels.

## Project layout

```
Sources/Annotator/   Swift app (panel, tools, OCR)
raycast/             Raycast extension (launches the binary)
reload-raycast.sh    Build both + restart Raycast
```
