#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SCRIPT_DIR/dist/Arxiv Discovery.app"
INSTALL_ROOT="${INSTALL_ROOT:-/Applications}"
INSTALLED_APP="$INSTALL_ROOT/Arxiv Discovery.app"
TEMP_APP="$INSTALL_ROOT/.Arxiv Discovery.installing.app"
BACKUP_APP="$INSTALL_ROOT/.Arxiv Discovery.previous.app"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then "$SCRIPT_DIR/build_app.sh"; fi
if pgrep -x ArxivDiscovery >/dev/null 2>&1; then
  echo "Arxiv Discovery is running. Save any work, quit it normally, and rerun this installer." >&2
  exit 3
fi

mkdir -p "$INSTALL_ROOT"
rm -rf "$TEMP_APP" "$BACKUP_APP"
SOURCE_PROVENANCE="$SOURCE_APP/Contents/Resources/build-provenance.json"
SOURCE_COMMIT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$SOURCE_PROVENANCE")"
SOURCE_DIRTY="$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1]))["dirty"]).lower())' "$SOURCE_PROVENANCE")"
CURRENT_COMMIT="$(git -C "$SCRIPT_DIR/.." rev-parse HEAD)"
if [[ "$SOURCE_COMMIT" != "$CURRENT_COMMIT" || "$SOURCE_DIRTY" != "false" ]]; then
  echo "Refusing an app bundle that does not match the clean current source commit." >&2
  exit 2
fi
codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$SOURCE_APP" "$TEMP_APP"

restore_previous_install() {
  rm -rf "$TEMP_APP" "$INSTALLED_APP"
  if [[ -d "$BACKUP_APP" ]]; then mv "$BACKUP_APP" "$INSTALLED_APP"; fi
}
trap restore_previous_install ERR INT TERM

if [[ -d "$INSTALLED_APP" ]]; then mv "$INSTALLED_APP" "$BACKUP_APP"; fi
mv "$TEMP_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_APP"
mdimport "$INSTALLED_APP" >/dev/null 2>&1 || true

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist")"
if [[ "$BUNDLE_ID" != "dev.gnaroshi.ArxivDiscovery" ]]; then
  echo "Installed bundle identifier verification failed: $BUNDLE_ID" >&2
  exit 6
fi
INSTALLED_COMMIT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$INSTALLED_APP/Contents/Resources/build-provenance.json")"
if [[ "$INSTALLED_COMMIT" != "$SOURCE_COMMIT" ]]; then
  echo "Installed bundle provenance does not match the selected source commit." >&2
  exit 6
fi

SPOTLIGHT_BUNDLE_ID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  SPOTLIGHT_BUNDLE_ID="$(mdls -raw -name kMDItemCFBundleIdentifier "$INSTALLED_APP" 2>/dev/null || true)"
  if [[ "$SPOTLIGHT_BUNDLE_ID" == "dev.gnaroshi.ArxivDiscovery" ]]; then break; fi
  sleep 1
done
if [[ "$SPOTLIGHT_BUNDLE_ID" != "dev.gnaroshi.ArxivDiscovery" ]]; then
  echo "Spotlight indexing is still pending; Launch Services registration succeeded." >&2
fi

rm -rf "$BACKUP_APP"
trap - ERR INT TERM

echo "Installed $INSTALLED_APP"
echo "Bundle ID: $BUNDLE_ID"
echo "Spotlight bundle ID: $SPOTLIGHT_BUNDLE_ID"
echo "Provenance:"
sed -n '1,40p' "$INSTALLED_APP/Contents/Resources/build-provenance.json"
echo "Spotlight matches:"
mdfind "kMDItemCFBundleIdentifier == 'dev.gnaroshi.ArxivDiscovery'" | sed -n '1,10p'

if [[ "${OPEN_APP:-0}" == "1" ]]; then open "$INSTALLED_APP"; fi
