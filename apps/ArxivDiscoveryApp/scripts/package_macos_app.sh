#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APP_ROOT/../.." && pwd)"
OUTPUT="${1:-$ROOT/dist/Arxiv Discovery.app}"
MASTER="$ROOT/identity/app-icon/arxiv-discovery-v1.png"
BUILD_DIR="${TMPDIR:-/tmp}/arxiv-discovery-app-build"
ICONSET="$BUILD_DIR/AppIcon.iconset"
APP_TMP="$BUILD_DIR/Arxiv Discovery.app"

[[ -f "$MASTER" ]] || { echo "Approved Arxiv Discovery icon is missing." >&2; exit 2; }
command -v swift >/dev/null || { echo "Swift is required." >&2; exit 2; }
command -v iconutil >/dev/null || { echo "iconutil is required." >&2; exit 2; }
command -v sips >/dev/null || { echo "sips is required." >&2; exit 2; }

rm -rf "$BUILD_DIR"
mkdir -p "$ICONSET" "$APP_TMP/Contents/MacOS" "$APP_TMP/Contents/Resources"

swift build --package-path "$APP_ROOT" -c release --product ArxivDiscoveryApp
BIN_DIR="$(swift build --package-path "$APP_ROOT" -c release --show-bin-path)"
ditto "$BIN_DIR/ArxivDiscoveryApp" "$APP_TMP/Contents/MacOS/Arxiv Discovery"
ditto "$APP_ROOT/Info.plist" "$APP_TMP/Contents/Info.plist"
ditto "$ROOT/gnaroshi.app.json" "$APP_TMP/Contents/Resources/gnaroshi.app.json"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_TMP/Contents/Resources/AppIcon.icns"

COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
DIRTY=false
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || DIRTY=true
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_TMP/Contents/Info.plist"
printf '{"schemaVersion":1,"repository":"Gnaroshi/Arxiv-newest-paper-crawler","commit":"%s","dirty":%s,"version":"0.4.0","build":%s}\n' "$COMMIT" "$DIRTY" "$BUILD_NUMBER" > "$APP_TMP/Contents/Resources/build-provenance.json"

IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)"
fi
[[ -n "$IDENTITY" ]] || { echo "A Developer ID Application signing identity is required." >&2; exit 2; }
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP_TMP"
codesign --verify --deep --strict --verbose=2 "$APP_TMP"

mkdir -p "$(dirname "$OUTPUT")"
rm -rf "$OUTPUT"
ditto "$APP_TMP" "$OUTPUT"
echo "$OUTPUT"
