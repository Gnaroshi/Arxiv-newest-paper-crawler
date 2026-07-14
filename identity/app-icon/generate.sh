#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/identity/app-icon/arxiv-discovery-v1.png"
STATIC="$ROOT/src/arxiv_discovery/web/static/identity"

command -v magick >/dev/null || { echo "ImageMagick is required." >&2; exit 2; }
mkdir -p "$STATIC"
magick "$SOURCE" -filter point -resize 32x32 "$STATIC/favicon-32.png"
magick "$SOURCE" -filter point -resize 64x64 "$STATIC/arxiv-discovery-64.png"
magick "$SOURCE" -filter point -resize 128x128 "$STATIC/arxiv-discovery-128.png"
magick "$SOURCE" -filter point -resize 180x180 "$STATIC/apple-touch-icon.png"

