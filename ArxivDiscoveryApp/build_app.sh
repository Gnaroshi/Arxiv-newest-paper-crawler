#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

uv run python tools/build_app_icon.py
swift build -c release --package-path "$SCRIPT_DIR"

APP_DIR="$SCRIPT_DIR/dist/Arxiv Discovery.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$SCRIPT_DIR/Info.plist"
ENTITLEMENTS="$SCRIPT_DIR/ArxivDiscovery.entitlements"
APP_VERSION="$(python3 -c 'import pathlib,tomllib; print(tomllib.loads(pathlib.Path("pyproject.toml").read_text())["project"]["version"])')"
BUILD_NUMBER="$(git rev-list --count HEAD)"
GIT_COMMIT="$(git rev-parse HEAD)"
GIT_DIRTY=false
if [[ -n "$(git status --porcelain)" ]]; then GIT_DIRTY=true; fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$SCRIPT_DIR/.build/release/ArxivDiscoveryApp" "$MACOS_DIR/ArxivDiscovery"
cp "$SCRIPT_DIR/.build/release/ArxivDiscoveryIntegration" "$MACOS_DIR/ArxivDiscoveryIntegration"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/identity/app-icon/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/gnaroshi.app.json" "$RESOURCES_DIR/gnaroshi.app.json"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

python3 - "$RESOURCES_DIR/build-provenance.json" "$APP_VERSION" "$BUILD_NUMBER" "$GIT_COMMIT" "$GIT_DIRTY" <<'PY'
import json
import pathlib
import sys

path, version, number, commit, dirty = sys.argv[1:]
pathlib.Path(path).write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "version": version,
            "buildNumber": int(number),
            "commit": commit,
            "dirty": dirty == "true",
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

chmod +x "$MACOS_DIR/ArxivDiscovery" "$MACOS_DIR/ArxivDiscoveryIntegration"
SIGNING_MODE="${SIGNING_MODE:-development}"
if [[ "$SIGNING_MODE" == "release" && "$GIT_DIRTY" == "true" ]]; then
  echo "Release packaging requires a clean tagged checkout." >&2
  exit 2
fi

SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$SIGNING_IDENTITY" && "$SIGNING_MODE" != "release" ]]; then
  SIGNING_IDENTITY="${APPLE_DEVELOPMENT_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "${ALLOW_AD_HOC_SIGNING:-0}" != "1" ]]; then
    echo "A Developer ID Application or Apple Development identity is required." >&2
    exit 2
  fi
  SIGNING_IDENTITY="-"
fi
if [[ "$SIGNING_MODE" == "release" && "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "Public release builds require a Developer ID Application identity." >&2
  exit 2
fi

codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$MACOS_DIR/ArxivDiscoveryIntegration"
codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "${PACKAGE_RELEASE:-0}" == "1" ]]; then
  ZIP_PATH="$SCRIPT_DIR/dist/Arxiv-Discovery-$APP_VERSION.zip"
  COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
  shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
  echo "Packaged $ZIP_PATH"
fi

echo "Built $APP_DIR"
echo "Version $APP_VERSION ($BUILD_NUMBER), commit $GIT_COMMIT, dirty $GIT_DIRTY"
echo "Signed with $SIGNING_IDENTITY"
