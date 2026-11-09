#!/usr/bin/env bash
# Shared helpers for packaging Annotator.app, the DMG, and the Sparkle appcast.
# Sourced by the other scripts.

if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

die() {
  echo "error: $*" >&2
  exit 1
}

github_repo() {
  local file="$ROOT/packaging/github-repo"
  [[ -f "$file" ]] || die "missing $file"
  tr -d '[:space:]' < "$file"
}

feed_url() {
  printf 'https://github.com/%s/releases/latest/download/appcast.xml' "$(github_repo)"
}

release_download_url() {
  local version="$1"
  local asset="$2"
  printf 'https://github.com/%s/releases/download/v%s/%s' "$(github_repo)" "$version" "$asset"
}

release_notes_url() {
  local version="$1"
  printf 'https://github.com/%s/releases/tag/v%s' "$(github_repo)" "$version"
}

sparkle_version() {
  local file="$ROOT/packaging/sparkle-version"
  [[ -f "$file" ]] || die "missing $file"
  tr -d '[:space:]' < "$file"
}

is_blank() {
  local value="${1:-}"
  [[ -z "${value//[[:space:]]/}" ]]
}

resolve_version() {
  local ver=""
  if [[ -n "${ANNOTATOR_VERSION:-}" ]]; then
    ver="${ANNOTATOR_VERSION#v}"
  elif git -C "$ROOT" describe --tags --exact-match >/dev/null 2>&1; then
    ver="$(git -C "$ROOT" describe --tags --exact-match)"
    ver="${ver#v}"
  else
    ver="0.0.0"
  fi
  if [[ "$ver" != "0.0.0" && ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "version must be MAJOR.MINOR.PATCH (tag vX.Y.Z). Got: ${ver}"
  fi
  printf '%s' "$ver"
}

resolve_sparkle_public_key() {
  local from_env="" from_file="" file="$ROOT/packaging/SUPublicEDKey"
  if [[ -n "${SPARKLE_EDDSA_PUBLIC_KEY:-}" ]]; then
    from_env="$(printf '%s' "$SPARKLE_EDDSA_PUBLIC_KEY" | tr -d '[:space:]')"
  fi
  if [[ -f "$file" ]]; then
    from_file="$(tr -d '[:space:]' < "$file")"
  fi
  if [[ -n "$from_env" && -n "$from_file" && "$from_env" != "$from_file" ]]; then
    die "SPARKLE_EDDSA_PUBLIC_KEY does not match packaging/SUPublicEDKey. Refusing to ship a build whose update key disagrees with the repo."
  fi
  if [[ -n "$from_env" ]]; then
    printf '%s' "$from_env"
  else
    printf '%s' "$from_file"
  fi
}

require_ci_secrets() {
  local missing=() name value
  local names=(
    DEVELOPER_ID_CERTIFICATE_BASE64
    DEVELOPER_ID_CERTIFICATE_PASSWORD
    APPLE_TEAM_ID
    APP_STORE_CONNECT_API_KEY_ID
    APP_STORE_CONNECT_API_ISSUER_ID
    APP_STORE_CONNECT_API_KEY_BASE64
    SPARKLE_EDDSA_PRIVATE_KEY
  )
  for name in "${names[@]}"; do
    value="$(printenv "$name" 2>/dev/null || true)"
    if is_blank "$value"; then
      missing+=("$name")
    fi
  done
  local public_key
  public_key="$(resolve_sparkle_public_key)"
  if is_blank "$public_key"; then
    missing+=("SPARKLE_EDDSA_PUBLIC_KEY or packaging/SUPublicEDKey")
  fi
  if ((${#missing[@]} > 0)); then
    echo "error: Refusing to publish an unsigned Annotator release." >&2
    echo "Gatekeeper blocks a downloaded app that is not Developer ID signed and notarized." >&2
    echo "This tag will not create a GitHub Release and will not upload a DMG." >&2
    echo >&2
    echo "Missing GitHub Actions secrets:" >&2
    for name in "${missing[@]}"; do
      echo "  - $name" >&2
    done
    echo >&2
    echo "Setup steps are in docs/release.md." >&2
    echo "To sign on a Mac instead of storing the Developer ID certificate in GitHub, run scripts/release-local.sh and upload that notarized DMG with gh release create." >&2
    echo "Do not attach an ad-hoc or unsigned DMG to the release." >&2
    return 1
  fi
}

file_sha256() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    sha256sum "$path" | awk '{print $1}'
  fi
}

write_release_notes() {
  local dest="$1"
  local version="$2"
  local dmg="$3"
  local sum
  sum="$(file_sha256 "$dmg")"
  cat > "$dest" <<EOF
Annotator ${version}

Download **Annotator.dmg**, open it, and drag Annotator to Applications.

Open Annotator and choose **Check for Updates…** from the Annotator menu to install later versions.

SHA-256: \`${sum}\`
EOF
}

render_info_plist() {
  local dest="$1"
  local version="$2"
  local public_key="$3"
  local feed key_block=""
  feed="$(feed_url)"
  if [[ -n "$public_key" ]]; then
    key_block="$(printf '  <key>SUPublicEDKey</key>\n  <string>%s</string>\n' "$public_key")"
  fi
  cat > "$dest" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Annotator</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.rhagerty32.annotator</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Annotator</string>
  <key>CFBundleDisplayName</key>
  <string>Annotator</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>© Ryan Hagerty</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>${feed}</string>
${key_block}  <key>SUEnableAutomaticChecks</key>
  <false/>
</dict>
</plist>
EOF
}

build_release_binaries() {
  local help
  cd "$ROOT"
  help="$(swift build --help 2>&1 || true)"
  if [[ "$help" == *"--arch"* ]]; then
    if ! swift build -c release --arch arm64 --arch x86_64; then
      echo "Universal build failed; building for the host architecture."
      swift build -c release
    fi
  else
    echo "This Swift toolchain has no --arch flag; building for the host architecture only."
    swift build -c release
  fi
}

product_dir() {
  local best="" best_mtime=0 candidate dir mtime
  for candidate in \
    "$ROOT/.build/apple/Products/Release/Annotator" \
    "$ROOT/.build/release/Annotator"
  do
    dir="$(dirname "$candidate")"
    if [[ -x "$candidate" && -x "$dir/Capture" ]]; then
      mtime="$(stat -f %m "$candidate" 2>/dev/null || stat -c %Y "$candidate")"
      if [[ "$mtime" -ge "$best_mtime" ]]; then
        best="$dir"
        best_mtime="$mtime"
      fi
    fi
  done
  [[ -n "$best" ]] || die "built Annotator and Capture were not found under .build"
  printf '%s' "$best"
}

find_sparkle_framework() {
  local found=""
  if [[ -d "$ROOT/.build/artifacts" ]]; then
    found="$(find "$ROOT/.build/artifacts" -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' ! -path '*.dSYM*' 2>/dev/null | head -n 1 || true)"
    if [[ -z "$found" ]]; then
      found="$(find "$ROOT/.build/artifacts" -type d -name Sparkle.framework -path '*macos*' ! -path '*.dSYM*' 2>/dev/null | head -n 1 || true)"
    fi
  fi
  [[ -n "$found" && -d "$found" ]] || die "Sparkle.framework not found under .build/artifacts. swift build did not resolve the Sparkle package."
  printf '%s' "$found"
}

ensure_rpath() {
  local bin="$1"
  local rpath="$2"
  local dump
  dump="$(otool -l "$bin")"
  if [[ "$dump" != *"$rpath"* ]]; then
    install_name_tool -add_rpath "$rpath" "$bin"
  fi
  dump="$(otool -l "$bin")"
  [[ "$dump" == *"$rpath"* ]] || die "failed to add rpath $rpath to $bin"
}

# Copy Sparkle next to a loose executable so `swift build` / Raycast dev runs
# can load it. The .app uses Contents/Frameworks instead.
embed_sparkle_beside_binary() {
  local bin_dir="$1"
  local framework
  framework="$(find_sparkle_framework)"
  ditto "$framework" "$bin_dir/Sparkle.framework"
  ensure_rpath "$bin_dir/Annotator" "@executable_path"
}

build_icns() {
  local dest="$1"
  local src="$ROOT/raycast/assets/icon.png"
  local work iconset
  [[ -f "$src" ]] || die "missing app icon source $src"
  command -v sips >/dev/null || die "sips is required to build the app icon (macOS)"
  command -v iconutil >/dev/null || die "iconutil is required to build the app icon (macOS)"
  work="$(mktemp -d)"
  iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"
  emit_icon() {
    sips -z "$1" "$1" "$src" --out "$iconset/$2" >/dev/null
  }
  emit_icon 16 icon_16x16.png
  emit_icon 32 icon_16x16@2x.png
  emit_icon 32 icon_32x32.png
  emit_icon 64 icon_32x32@2x.png
  emit_icon 128 icon_128x128.png
  emit_icon 256 icon_128x128@2x.png
  emit_icon 256 icon_256x256.png
  emit_icon 512 icon_256x256@2x.png
  emit_icon 512 icon_512x512.png
  emit_icon 1024 icon_512x512@2x.png
  iconutil -c icns "$iconset" -o "$dest"
  rm -rf "$work"
}

codesign_identity() {
  if is_blank "${SIGNING_IDENTITY:-}"; then
    printf '%s' "-"
  else
    printf '%s' "$SIGNING_IDENTITY"
  fi
}

sign_item() {
  local target="$1"
  local entitlements="${2:-}"
  local identity
  identity="$(codesign_identity)"
  local -a args=(--force --sign "$identity" --options runtime)
  if [[ "$identity" == "-" ]]; then
    args+=(--timestamp=none)
  else
    args+=(--timestamp)
  fi
  if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
    args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi
  if [[ -n "$entitlements" ]]; then
    args+=(--entitlements "$entitlements")
  elif [[ "$identity" != "-" ]]; then
    args+=(--preserve-metadata=identifier,entitlements)
  fi
  if ! codesign "${args[@]}" "$target"; then
    local -a fallback=(--force --sign "$identity" --options runtime)
    if [[ "$identity" == "-" ]]; then
      fallback+=(--timestamp=none)
    else
      fallback+=(--timestamp)
    fi
    if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
      fallback+=(--keychain "$CODESIGN_KEYCHAIN")
    fi
    if [[ -n "$entitlements" ]]; then
      fallback+=(--entitlements "$entitlements")
    fi
    codesign "${fallback[@]}" "$target"
  fi
}

sign_sparkle_framework() {
  local fw="$1"
  local version_b="$fw/Versions/B"
  [[ -d "$version_b" ]] || die "Sparkle.framework is missing Versions/B ($fw)"
  sign_item "$version_b/XPCServices/Downloader.xpc"
  sign_item "$version_b/XPCServices/Installer.xpc"
  sign_item "$version_b/Updater.app"
  sign_item "$version_b/Autoupdate"
  sign_item "$fw"
}

find_sign_update() {
  local existing="" dest ver archive
  if [[ -d "$ROOT/.build" ]]; then
    existing="$(find "$ROOT/.build" -type f -path '*/bin/sign_update' ! -path '*old_dsa_scripts*' ! -path '*.dSYM*' 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -n "$existing" && -x "$existing" ]]; then
    printf '%s' "$existing"
    return 0
  fi
  ver="$(sparkle_version)"
  dest="$ROOT/.build/sparkle-tools"
  mkdir -p "$dest"
  if [[ ! -x "$dest/bin/sign_update" ]]; then
    archive="$(mktemp)"
    curl -fsSL -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/${ver}/Sparkle-${ver}.tar.xz"
    tar -xJf "$archive" -C "$dest"
    rm -f "$archive"
  fi
  [[ -x "$dest/bin/sign_update" ]] || die "sign_update was not found after downloading Sparkle ${ver}"
  printf '%s' "$dest/bin/sign_update"
}
