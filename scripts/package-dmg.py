#!/usr/bin/env python3
"""Build Annotator.app and dist/Annotator.dmg with the Ink Trio icon.

Finder layout (content area, origin at the top left, positions are icon centers):
  window     720 x 440 pt
  icon size  128
  text size  13
  Annotator.app     (200, 230)
  Applications      (520, 230)

The background is assets/dmg/background.tiff (1x at 72 dpi, 2x at 144 dpi).
Labels sit under the icons, about y 290 to 330, which the background leaves empty.
On a dark window, Finder draws those labels white in Dark Mode.

On macOS this uses swift, hdiutil, and codesign. It embeds Sparkle.framework
so Check for Updates can relaunch a newer build. Signing is ad-hoc unless
DEVELOPER_ID_APPLICATION is set. Notarization runs when APPLE_NOTARY_KEY_ID,
APPLE_NOTARY_ISSUER_ID, and APPLE_NOTARY_KEY_PATH are set.
On Linux it reuses the arm64 binaries already inside dist/Annotator.dmg and
packs an HFS+ image with libdmg-hfsplus (hfsplus, dmg, and scripts/hfs-tool.c).
"""

from __future__ import annotations

import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist" / "Annotator.dmg"
ICNS = ROOT / "assets" / "icon" / "AppIcon.icns"
TIFF = ROOT / "assets" / "dmg" / "background.tiff"
INFO = ROOT / "packaging" / "Info.plist"

WINDOW_BOUNDS = "{{200, 120}, {720, 440}}"
ICON_POSITIONS = {
    "Annotator.app": (200, 230),
    "Applications": (520, 230),
}


def run(cmd: list[str], **kwargs) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.check_call(cmd, **kwargs)


def capture(cmd: list[str]) -> str:
    print("+", " ".join(cmd), flush=True)
    return subprocess.check_output(cmd, text=True)


def generate_icons() -> None:
    run([sys.executable, str(ROOT / "scripts" / "generate-icons.py")], cwd=ROOT)


def strip_code_signature(path: Path) -> None:
    """Drop an embedded Mach-O signature so a new bundle seal can replace it."""
    data = bytearray(path.read_bytes())
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xFEEDFACF:
        return
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    offset = 32
    signature = None
    linkedit = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmd == 0x1D and cmdsize >= 16:  # LC_CODE_SIGNATURE
            dataoff, datasize = struct.unpack_from("<II", data, offset + 8)
            signature = (offset, cmdsize, dataoff, datasize)
        if cmd == 0x19:  # LC_SEGMENT_64
            name = bytes(data[offset + 8 : offset + 24]).split(b"\0", 1)[0]
            if name == b"__LINKEDIT":
                linkedit = offset
        offset += cmdsize
    if signature is None:
        return
    cmd_off, cmdsize, dataoff, datasize = signature
    if linkedit is not None:
        fileoff, filesize = struct.unpack_from("<QQ", data, linkedit + 40)
        if fileoff + filesize == dataoff + datasize:
            struct.pack_into("<Q", data, linkedit + 48, filesize - datasize)
    struct.pack_into("<I", data, 16, ncmds - 1)
    struct.pack_into("<I", data, 20, sizeofcmds - cmdsize)
    del data[dataoff : dataoff + datasize]
    path.write_bytes(data)


def stage_app(stage: Path, binary: Path) -> Path:
    app = stage / "Annotator.app"
    macos = app / "Contents" / "MacOS"
    resources = app / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    write_info(app / "Contents" / "Info.plist")
    shutil.copyfile(ICNS, resources / "AppIcon.icns")
    # CFBundleExecutable must be this binary. A launcher that execs a second
    # Mach-O makes MenuBarAgent reject the status-item scene on macOS 26.
    shutil.copyfile(binary, macos / "Annotator")
    os.chmod(macos / "Annotator", 0o755)
    # Same image under the old name so `AnnotatorBin --settings` still runs it.
    shutil.copyfile(binary, macos / "AnnotatorBin")
    os.chmod(macos / "AnnotatorBin", 0o755)
    background = stage / ".background"
    background.mkdir()
    shutil.copyfile(TIFF, background / "background.tiff")
    applications = stage / "Applications"
    if applications.exists() or applications.is_symlink():
        applications.unlink()
    applications.symlink_to("/Applications")
    return app


def write_info(dest: Path) -> None:
    info = plistlib.loads(INFO.read_bytes())
    version = os.environ.get("ANNOTATOR_VERSION", "").strip()
    if version:
        info["CFBundleShortVersionString"] = version
        info["CFBundleVersion"] = version
    public = os.environ.get("SPARKLE_PUBLIC_ED_KEY", "").strip()
    if public:
        info["SUPublicEDKey"] = public
    dest.write_bytes(plistlib.dumps(info, sort_keys=False))


def find_sparkle_framework() -> Path | None:
    root = ROOT / ".build"
    if not root.exists():
        return None
    found = [
        path
        for path in root.rglob("Sparkle.framework")
        if path.is_dir() and "Annotator.app" not in path.parts
    ]

    def rank(path: Path) -> tuple[int, int]:
        parts = set(path.parts)
        if "macos-arm64_x86_64" in parts:
            return (0, len(path.parts))
        if "macos-arm64" in parts:
            return (1, len(path.parts))
        if "macos-x86_64" in parts:
            return (2, len(path.parts))
        return (3, len(path.parts))

    found.sort(key=rank)
    return found[0] if found else None


def embed_sparkle(app: Path) -> None:
    framework = find_sparkle_framework()
    if framework is None:
        if sys.platform == "darwin":
            raise SystemExit(
                "Sparkle.framework was not found under .build. "
                "swift build should fetch the Sparkle package before packaging."
            )
        print("Sparkle.framework not found; leaving this bundle without an updater", flush=True)
        return
    dest_root = app / "Contents" / "Frameworks"
    dest_root.mkdir(parents=True, exist_ok=True)
    dest = dest_root / "Sparkle.framework"
    if dest.exists():
        shutil.rmtree(dest)
    if sys.platform == "darwin":
        run(["ditto", str(framework), str(dest)])
    else:
        shutil.copytree(framework, dest, symlinks=True)


def is_macho(path: Path) -> bool:
    if not path.is_file() or path.is_symlink():
        return False
    try:
        magic = path.read_bytes()[:4]
    except OSError:
        return False
    return magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")


def signing_identity() -> str:
    return os.environ.get("DEVELOPER_ID_APPLICATION", "").strip() or "-"


def sign_item(path: Path, identity: str, preserve: bool = False, identifier: str | None = None) -> None:
    cmd = ["codesign", "--force", "--sign", identity]
    if identity != "-":
        cmd += ["--timestamp", "--options", "runtime"]
    if identifier:
        cmd += ["--identifier", identifier]
    if preserve:
        preserved = subprocess.run(
            cmd + ["--preserve-metadata=entitlements", str(path)],
            text=True,
            capture_output=True,
        )
        if preserved.returncode == 0:
            return
    run(cmd + [str(path)])


def sign_sparkle(framework: Path, identity: str) -> None:
    paths: list[Path] = []
    for path in framework.rglob("*"):
        if path.is_symlink():
            continue
        if path.suffix in {".app", ".xpc", ".bundle"} or is_macho(path):
            paths.append(path)
    paths.sort(key=lambda item: len(item.parts), reverse=True)
    for path in paths:
        sign_item(path, identity, preserve=True)
    sign_item(framework, identity, preserve=True)


def ensure_framework_rpath(binary: Path) -> None:
    if sys.platform != "darwin" or not binary.is_file():
        return
    token = "@executable_path/../Frameworks"
    listing = capture(["otool", "-l", str(binary)])
    if token in listing:
        return
    added = subprocess.run(
        ["install_name_tool", "-add_rpath", token, str(binary)],
        text=True,
        capture_output=True,
    )
    if added.returncode != 0:
        subprocess.run(["codesign", "--remove-signature", str(binary)], check=False)
        run(["install_name_tool", "-add_rpath", token, str(binary)])


def assert_links_sparkle(binary: Path) -> None:
    if sys.platform != "darwin" or not binary.is_file():
        return
    listing = capture(["otool", "-L", str(binary)])
    if "Sparkle.framework" not in listing:
        raise SystemExit("AnnotatorBin does not link Sparkle.framework")


def notarization_env() -> tuple[str, str, str] | None:
    key_id = os.environ.get("APPLE_NOTARY_KEY_ID", "").strip()
    issuer = os.environ.get("APPLE_NOTARY_ISSUER_ID", "").strip()
    key_path = os.environ.get("APPLE_NOTARY_KEY_PATH", "").strip()
    if key_id and issuer and key_path:
        return key_id, issuer, key_path
    return None


def notarize(path: Path) -> None:
    creds = notarization_env()
    if creds is None or sys.platform != "darwin":
        return
    key_id, issuer, key_path = creds
    submit = path
    temp_zip: Path | None = None
    if path.suffix == ".app":
        temp_zip = path.parent / f"{path.stem}-notarize.zip"
        if temp_zip.exists():
            temp_zip.unlink()
        run(["ditto", "-c", "-k", "--keepParent", str(path), str(temp_zip)])
        submit = temp_zip
    try:
        run(
            [
                "xcrun",
                "notarytool",
                "submit",
                str(submit),
                "--key",
                key_path,
                "--key-id",
                key_id,
                "--issuer",
                issuer,
                "--wait",
            ]
        )
        run(["xcrun", "stapler", "staple", str(path)])
    finally:
        if temp_zip is not None and temp_zip.exists():
            temp_zip.unlink()


def publish_app(app: Path) -> None:
    dest = DIST.parent / "Annotator.app"
    if dest.exists():
        shutil.rmtree(dest)
    if sys.platform == "darwin":
        run(["ditto", str(app), str(dest)])
    else:
        shutil.copytree(app, dest, symlinks=True)


def sign_app(app: Path) -> None:
    if sys.platform == "darwin":
        identity = signing_identity()
        framework = app / "Contents" / "Frameworks" / "Sparkle.framework"
        if framework.exists():
            sign_sparkle(framework, identity)
        # Both names are the same Swift binary and must share the bundle identifier.
        # A launcher signed as local.annotator.launcher does not match the bundle
        # MenuBarAgent resolves for the status item.
        sign_item(app / "Contents" / "MacOS" / "Annotator", identity, identifier="local.annotator")
        sign_item(app / "Contents" / "MacOS" / "AnnotatorBin", identity, identifier="local.annotator")
        sign_item(app, identity, identifier="local.annotator")
        if identity == "-":
            print(
                "Ad-hoc signature. Open Annotator from the Finder if macOS asks the first time. "
                "Check for Updates still installs a newer zip signed with the Sparkle EdDSA key.",
                flush=True,
            )
        elif notarization_env() is None:
            print(
                "Developer ID signature without notarization.",
                flush=True,
            )
        return
    rcodesign = os.environ.get("RCODESIGN") or shutil.which("rcodesign")
    if not rcodesign:
        print("rcodesign not found; leaving the bundle unsigned", flush=True)
        for binary in (app / "Contents" / "MacOS" / "Annotator", app / "Contents" / "MacOS" / "AnnotatorBin"):
            strip_code_signature(binary)
        code_resources = app / "Contents" / "_CodeSignature"
        if code_resources.exists():
            shutil.rmtree(code_resources)
        return
    for binary in (app / "Contents" / "MacOS" / "Annotator", app / "Contents" / "MacOS" / "AnnotatorBin"):
        strip_code_signature(binary)
    run(
        [
            rcodesign,
            "sign",
            "--binary-identifier",
            "local.annotator",
            str(app),
        ]
    )


def apple_date(seconds: int):
    from mac_alias.utils import mac_epoch

    return mac_epoch + timedelta(seconds=int(seconds))


def background_alias(stat: dict[str, str]) -> bytes:
    from mac_alias import ALIAS_EJECTABLE_DISK, ALIAS_KIND_FILE, Alias, TargetInfo, VolumeInfo

    volume_name = stat["volume_name"]
    fs_type = stat["signature"].encode("ascii")
    if len(fs_type) != 2:
        fs_type = b"H+"
    alias = Alias()
    alias.volume = VolumeInfo(
        name=volume_name,
        creation_date=apple_date(int(stat["volume_create"])),
        fs_type=fs_type,
        disk_type=ALIAS_EJECTABLE_DISK,
        attribute_flags=0,
        fs_id=b"\0\0",
    )
    alias.volume.posix_path = f"/Volumes/{volume_name}".encode()
    parent = int(stat["parent"])
    # Same carbon-path shape mac_alias writes: volume:.background:<NUL>background.tiff
    carbon = volume_name.encode() + b":.background:\0background.tiff"
    alias.target = TargetInfo(
        kind=ALIAS_KIND_FILE,
        filename="background.tiff",
        folder_cnid=parent,
        cnid=int(stat["cnid"]),
        creation_date=apple_date(int(stat["create"])),
        creator_code=b"\0\0\0\0",
        type_code=b"\0\0\0\0",
        folder_name=".background",
        cnid_path=[parent],
        carbon_path=carbon,
        posix_path=b"/.background/background.tiff",
    )
    return alias.to_bytes()


def write_ds_store(path: Path, alias_bytes: bytes) -> None:
    from ds_store import DSStore

    if path.exists():
        path.unlink()
    bwsp = {
        "ShowStatusBar": False,
        "WindowBounds": WINDOW_BOUNDS,
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }
    icvp = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 13.0,
        "iconSize": 128.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
        "backgroundImageAlias": alias_bytes,
    }
    with DSStore.open(str(path), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = bwsp
        store["."]["icvp"] = icvp
        store["."]["icvl"] = ("type", b"icnv")
        for name, point in ICON_POSITIONS.items():
            store[name]["Iloc"] = point


def parse_stat(text: str) -> dict[str, str]:
    values = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    required = ("volume_name", "volume_create", "signature", "kind", "cnid", "parent", "create")
    missing = [key for key in required if key not in values]
    if missing:
        raise SystemExit(f"hfs-tool stat missing {missing}\n{text}")
    return values


def locate_swift_binary(work: Path) -> Path:
    built = ROOT / ".build" / "release" / "Annotator"
    binary_env = os.environ.get("ANNOTATOR_BIN")
    if binary_env:
        return Path(binary_env)
    if sys.platform == "darwin" and shutil.which("swift"):
        run(["swift", "build", "-c", "release"], cwd=ROOT)
        return built
    if not DIST.is_file():
        raise SystemExit("No dist/Annotator.dmg and no swift build. Cannot find the app binary.")
    extract = work / "previous"
    extract.mkdir()
    # The Applications drop link is an absolute symlink. 7z refuses to
    # extract that path, and we only need the Mach-O here.
    run(
        [
            "7z",
            "x",
            "-y",
            f"-o{extract}",
            str(DIST),
            "-x!Applications",
            "-x!*/Applications",
        ]
    )
    # Older images keep the Swift binary at AnnotatorBin and a C launcher at Annotator.
    binary = next(extract.rglob("MacOS/AnnotatorBin"), None)
    if binary is None or not binary.is_file():
        binary = next(extract.rglob("MacOS/Annotator"), None)
    if binary is None or not binary.is_file():
        raise SystemExit(f"Previous disk image did not contain the app binary in {extract}")
    return binary


def build_macos(stage: Path, output: Path) -> None:
    from mac_alias import Alias

    work = output.parent
    raw = work / "Annotator-rw.dmg"
    if raw.exists():
        raw.unlink()
    run(
        [
            "hdiutil",
            "create",
            "-size",
            "64m",
            "-fs",
            "HFS+",
            "-volname",
            "Annotator",
            "-ov",
            str(raw),
        ]
    )
    plist = plistlib.loads(
        subprocess.check_output(
            ["hdiutil", "attach", "-readwrite", "-noverify", "-noautoopen", "-nobrowse", "-plist", str(raw)]
        )
    )
    mount = None
    device = None
    for entity in plist.get("system-entities", []):
        if entity.get("mount-point"):
            mount = entity["mount-point"]
            device = entity.get("dev-entry")
    if not mount:
        raise SystemExit("hdiutil attach did not return a mount point")
    try:
        for name in os.listdir(stage):
            source = stage / name
            dest = Path(mount) / name
            if source.is_symlink():
                dest.symlink_to(os.readlink(source))
            else:
                run(["ditto", str(source), str(dest)])
        alias = Alias.for_file(str(Path(mount) / ".background" / "background.tiff"))
        write_ds_store(Path(mount) / ".DS_Store", alias.to_bytes())
        if shutil.which("bless"):
            subprocess.call(["bless", "--folder", mount])
    finally:
        if device:
            subprocess.call(["hdiutil", "detach", device])
    if output.exists():
        output.unlink()
    run(["hdiutil", "convert", str(raw), "-format", "UDZO", "-ov", "-o", str(output)])
    raw.unlink()


def which_or_env(env: str, name: str) -> str | None:
    value = os.environ.get(env)
    if value:
        return value
    return shutil.which(name)


def build_linux(stage: Path, output: Path, work: Path) -> None:
    hfsplus = which_or_env("HFSPLUS", "hfsplus")
    dmg_tool = which_or_env("DMG_TOOL", "dmg")
    hfs_tool = os.environ.get("HFS_TOOL")
    empty = os.environ.get("EMPTY_HFS")
    if not hfsplus or not dmg_tool or not hfs_tool or not empty:
        raise SystemExit(
            "Linux packaging needs hfsplus, dmg, hfs-tool, and an empty HFS template.\n"
            "Build https://github.com/mozilla/libdmg-hfsplus and set HFSPLUS, DMG_TOOL, "
            "HFS_TOOL, and EMPTY_HFS. On macOS this script uses hdiutil instead."
        )
    image = work / "annotator.hfs"
    shutil.copyfile(empty, image)
    run([hfsplus, str(image), "grow", str(64 * 1024 * 1024)])
    run([hfsplus, "--symlinks=clone_link", "--special-modes=no", str(image), "addall", str(stage)])
    run([hfs_tool, "rename", str(image), "Annotator"])
    stat = parse_stat(capture([hfs_tool, "stat", str(image), "/.background/background.tiff"]))
    if stat["volume_name"] != "Annotator":
        raise SystemExit(f"volume name is {stat['volume_name']!r}")
    ds_store = work / "DS_Store"
    write_ds_store(ds_store, background_alias(stat))
    run([hfsplus, str(image), "add", str(ds_store), "/.DS_Store"])
    run([hfs_tool, "bless", str(image)])
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    run([dmg_tool, "-c", "zlib", "build", str(image), str(output)])


def verify_dmg(path: Path) -> None:
    if not shutil.which("7z"):
        print("7z not available; skipped disk image listing")
        return
    listing = capture(["7z", "l", str(path)])
    print(listing)
    needed = ("Annotator.app", "AppIcon.icns", "background.tiff", ".DS_Store", "Applications")
    missing = [name for name in needed if name not in listing]
    if missing:
        raise SystemExit(f"disk image listing is missing {missing}")


def main() -> None:
    app_only = "--app-only" in sys.argv
    os.chdir(ROOT)
    generate_icons()
    with tempfile.TemporaryDirectory(prefix="annotator-dmg-") as tmp:
        work = Path(tmp)
        binary = locate_swift_binary(work)
        stage = work / "stage"
        stage.mkdir()
        app = stage_app(stage, binary)
        embed_sparkle(app)
        for name in ("Annotator", "AnnotatorBin"):
            binary_in_app = app / "Contents" / "MacOS" / name
            ensure_framework_rpath(binary_in_app)
            assert_links_sparkle(binary_in_app)
        sign_app(app)
        if sys.platform == "darwin" and signing_identity() != "-" and notarization_env() is not None:
            notarize(app)
        publish_app(app)
        if app_only:
            print(f"Wrote {DIST.parent / 'Annotator.app'}")
            return
        output = work / "Annotator.dmg"
        if sys.platform == "darwin":
            build_macos(stage, output)
        else:
            build_linux(stage, output, work)
        DIST.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(output, DIST)
        if sys.platform == "darwin" and signing_identity() != "-":
            run(["codesign", "--force", "--sign", signing_identity(), "--timestamp", str(DIST)])
            if notarization_env() is not None:
                notarize(DIST)
    verify_dmg(DIST)
    print(f"Wrote {DIST}")


if __name__ == "__main__":
    main()
