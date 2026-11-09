#!/usr/bin/env python3
"""Build Ink Trio icon and disk-image assets from the approved masters.

Source of truth
  assets/icon/ink-trio.png   Approved 1024 precomposed icon (squircle, shadow).
  assets/icon/ink-trio.svg   Vector source for that master. Filters describe the
                             glass, enamel, and gold. Do not redraw those
                             materials in AppKit or a flatter generator.
  assets/dmg/background.png  Finder window art, 720x440.
  assets/dmg/background@2x.png  Same art at 1440x880.

Outputs
  raycast/assets/icon.png    Exact copy of the precomposed master (1024).
                             Raycast shows this image as drawn.
  assets/icon/AppIcon-1024.png
                             Full-bleed system icon. The dark field fills the
                             square and there is no outer shadow, so macOS can
                             apply its own squircle mask.
  assets/icon/AppIcon.icns   16 through 1024, plus the retina sizes.
  assets/icon/AppIcon.appiconset/
                             The same full-bleed sizes for an asset catalog.
  assets/dmg/background.tiff HiDPI TIFF (1x at 72 dpi, 2x at 144 dpi).

The system icon is produced by lifting the opaque squircle face out of the
approved raster and scaling that face to 1024. Corners outside the squircle
are filled from the dark field. That keeps the approved lighting and avoids
shipping a pre-masked icon with a second drop shadow.
"""

from __future__ import annotations

import json
import shutil
import struct
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "assets" / "icon" / "ink-trio.png"
BG_1X = ROOT / "assets" / "dmg" / "background.png"
BG_2X = ROOT / "assets" / "dmg" / "background@2x.png"
RAYCAST_ICON = ROOT / "raycast" / "assets" / "icon.png"
APP_ICON = ROOT / "assets" / "icon" / "AppIcon-1024.png"
ICNS_PATH = ROOT / "assets" / "icon" / "AppIcon.icns"
ICONSET = ROOT / "assets" / "icon" / "AppIcon.appiconset"
TIFF_PATH = ROOT / "assets" / "dmg" / "background.tiff"

# Opaque face of the approved master. Measured from ink-trio.png:
# alpha >= 250 occupies x=100..923, y=100..923.
FACE_BOX = (100, 100, 924, 924)

ICONSET_IMAGES = [
    ("icon_16x16.png", 16, "16x16", "1x"),
    ("icon_16x16@2x.png", 32, "16x16", "2x"),
    ("icon_32x32.png", 32, "32x32", "1x"),
    ("icon_32x32@2x.png", 64, "32x32", "2x"),
    ("icon_128x128.png", 128, "128x128", "1x"),
    ("icon_128x128@2x.png", 256, "128x128", "2x"),
    ("icon_256x256.png", 256, "256x256", "1x"),
    ("icon_256x256@2x.png", 512, "256x256", "2x"),
    ("icon_512x512.png", 512, "512x512", "1x"),
    ("icon_512x512@2x.png", 1024, "512x512", "2x"),
]

# Modern icns PNG chunks. iconutil emits this set.
ICNS_TYPES = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512),
]


def full_bleed(master: Image.Image) -> Image.Image:
    """Scale the squircle face to a 1024 square with an opaque dark field."""
    face = master.convert("RGBA").crop(FACE_BOX)
    width, height = face.size
    src = face.load()
    out = Image.new("RGB", (width, height))
    dst = out.load()
    center_x = (width - 1) / 2
    center_y = (height - 1) / 2

    def sample_inward(x: int, y: int) -> tuple[int, int, int]:
        # The squircle edge carries a thin rim light. Step past it so the
        # square corners continue the dark field instead of smearing that rim.
        dx = center_x - x
        dy = center_y - y
        dist = max(1.0, (dx * dx + dy * dy) ** 0.5)
        step_x = dx / dist
        step_y = dy / dist
        px = float(x)
        py = float(y)
        seen = 0
        for _ in range(int(dist) + 2):
            px += step_x
            py += step_y
            ix = int(round(px))
            iy = int(round(py))
            if not (0 <= ix < width and 0 <= iy < height):
                continue
            if src[ix, iy][3] < 250:
                continue
            seen += 1
            if seen >= 28:
                red, green, blue, _alpha = src[ix, iy]
                return red, green, blue
        return 22, 20, 23

    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = src[x, y]
            if alpha >= 250:
                dst[x, y] = (red, green, blue)
            else:
                dst[x, y] = sample_inward(x, y)

    if out.size != (1024, 1024):
        out = out.resize((1024, 1024), Image.Resampling.LANCZOS)
    return out


def png_bytes(image: Image.Image, size: int) -> bytes:
    if image.size != (size, size):
        image = image.resize((size, size), Image.Resampling.LANCZOS)
    from io import BytesIO

    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def write_icns(images: dict[int, Image.Image], path: Path) -> None:
    chunks = []
    cache: dict[int, bytes] = {}
    for ostype, size in ICNS_TYPES:
        if size not in cache:
            cache[size] = png_bytes(images[1024], size)
        payload = cache[size]
        chunks.append(ostype.encode("ascii") + struct.pack(">I", len(payload) + 8) + payload)
    body = b"".join(chunks)
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def write_iconset(full: Image.Image, directory: Path) -> None:
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    images = []
    seen: dict[int, Path] = {}
    for filename, size, point_size, scale in ICONSET_IMAGES:
        dest = directory / filename
        if size not in seen:
            frame = full if size == 1024 else full.resize((size, size), Image.Resampling.LANCZOS)
            frame.save(dest, format="PNG", optimize=True)
            seen[size] = dest
        else:
            shutil.copyfile(seen[size], dest)
        images.append(
            {
                "filename": filename,
                "idiom": "mac",
                "scale": scale,
                "size": point_size,
            }
        )
    contents = {"images": images, "info": {"author": "annotator", "version": 1}}
    (directory / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def _rational(value: int) -> bytes:
    return struct.pack("<II", value, 1)


def _ifd_entry(tag: int, typ: int, count: int, payload: bytes) -> tuple[bytes, bytes]:
    """Return (12-byte entry, overflow bytes). Overflow is empty if it fits inline."""
    if len(payload) <= 4:
        inline = payload + b"\x00" * (4 - len(payload))
        return struct.pack("<HHI", tag, typ, count) + inline, b""
    return struct.pack("<HHI", tag, typ, count) + b"\x00\x00\x00\x00", payload


def write_hidpi_tiff(path_1x: Path, path_2x: Path, dest: Path) -> None:
    """TIFF with the 1x plate at 72 dpi and the 2x plate at 144 dpi.

    create-dmg / tiffutil -cathidpicheck expects both plates to share one
    physical size. Finder then picks the plate that matches the screen scale.
    Compression is Adobe Deflate, which ImageIO reads.
    """
    plates = [
        (Image.open(path_1x).convert("RGB"), 72),
        (Image.open(path_2x).convert("RGB"), 144),
    ]
    encoded = []
    for image, dpi in plates:
        raw = image.tobytes()
        encoded.append((image.size[0], image.size[1], dpi, zlib.compress(raw, 9)))

    # Layout: header, strip bytes, then per page: bits, rationals, IFD.
    blob = bytearray(b"II" + struct.pack("<HI", 42, 0))
    pages = []
    for width, height, dpi, strip in encoded:
        strip_off = len(blob)
        blob += strip
        bits_off = len(blob)
        blob += struct.pack("<HHH", 8, 8, 8)
        xres_off = len(blob)
        blob += _rational(dpi)
        yres_off = len(blob)
        blob += _rational(dpi)
        pages.append((width, height, strip_off, len(strip), bits_off, xres_off, yres_off))

    # Each IFD is 2 + 12*12 + 4 bytes. Offsets to the 3-sample BitsPerSample
    # array and the resolution rationals live in front of the IFDs.
    ifd_size = 2 + 12 * 12 + 4
    ifd_offsets = []
    for width, height, strip_off, strip_len, bits_off, xres_off, yres_off in pages:
        ifd_offsets.append(len(blob))
        entries = [
            (256, 4, 1, struct.pack("<I", width)),
            (257, 4, 1, struct.pack("<I", height)),
            (258, 3, 3, struct.pack("<I", bits_off)),
            (259, 3, 1, struct.pack("<H", 8)),
            (262, 3, 1, struct.pack("<H", 2)),
            (273, 4, 1, struct.pack("<I", strip_off)),
            (277, 3, 1, struct.pack("<H", 3)),
            (278, 4, 1, struct.pack("<I", height)),
            (279, 4, 1, struct.pack("<I", strip_len)),
            (282, 5, 1, struct.pack("<I", xres_off)),
            (283, 5, 1, struct.pack("<I", yres_off)),
            (296, 3, 1, struct.pack("<H", 2)),
        ]
        blob += struct.pack("<H", len(entries))
        entry_start = len(blob)
        blob += b"\x00" * (12 * len(entries))
        blob += struct.pack("<I", 0)
        for slot, (tag, typ, count, payload) in enumerate(entries):
            entry, overflow = _ifd_entry(tag, typ, count, payload)
            if overflow:
                raise RuntimeError(f"TIFF tag {tag} did not fit inline")
            blob[entry_start + slot * 12 : entry_start + (slot + 1) * 12] = entry

    for index, ifd_off in enumerate(ifd_offsets):
        next_off = ifd_offsets[index + 1] if index + 1 < len(ifd_offsets) else 0
        struct.pack_into("<I", blob, ifd_off + ifd_size - 4, next_off)
    struct.pack_into("<I", blob, 4, ifd_offsets[0])
    dest.write_bytes(blob)


def main() -> None:
    for path in (MASTER, BG_1X, BG_2X):
        if not path.is_file():
            raise SystemExit(f"missing master: {path}")

    master = Image.open(MASTER)
    if master.size != (1024, 1024):
        raise SystemExit(f"{MASTER} must be 1024x1024, got {master.size}")

    RAYCAST_ICON.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(MASTER, RAYCAST_ICON)

    full = full_bleed(master)
    if full.size != (1024, 1024):
        raise SystemExit("full-bleed icon is not 1024 square")
    # Corners are the dark field extended past the squircle. A thin rim light
    # from the approved edge can land here; macOS masks those corners off.
    corners = [full.getpixel((0, 0)), full.getpixel((1023, 0)), full.getpixel((0, 1023)), full.getpixel((1023, 1023))]
    for pixel in corners:
        if max(pixel) > 140:
            raise SystemExit(f"full-bleed corner is too light: {pixel}")
    full.save(APP_ICON, format="PNG", optimize=True)

    write_icns({1024: full}, ICNS_PATH)
    write_iconset(full, ICONSET)
    write_hidpi_tiff(BG_1X, BG_2X, TIFF_PATH)

    print(f"Wrote {RAYCAST_ICON.relative_to(ROOT)}")
    print(f"Wrote {APP_ICON.relative_to(ROOT)}")
    print(f"Wrote {ICNS_PATH.relative_to(ROOT)}")
    print(f"Wrote {ICONSET.relative_to(ROOT)}")
    print(f"Wrote {TIFF_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
