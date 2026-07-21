#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$HOME/Applications/Arxiv Discovery.app"

if pgrep -x "Arxiv Discovery" >/dev/null 2>&1; then
  echo "Quit Arxiv Discovery before replacing its signed application bundle." >&2
  exit 3
fi

if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
  echo "The Arxiv Discovery source has tracked local changes; preserve them before automatic installation." >&2
  exit 4
fi

UV="$(command -v uv || true)"
[[ -n "$UV" ]] || { echo "uv is required to install the arxiv-discovery provider." >&2; exit 2; }
"$UV" tool install --force "$ROOT"
"$ROOT/apps/ArxivDiscoveryApp/scripts/package_macos_app.sh" "$TARGET"
echo "Installed the current signed Arxiv Discovery app and CLI provider."
