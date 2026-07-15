from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "identity" / "app-icon" / "arxiv-discovery-v1.png"
OUTPUT = ROOT / "identity" / "app-icon" / "AppIcon.icns"
ICONSET = ROOT / "identity" / "app-icon" / "AppIcon.iconset"
METADATA = ROOT / "identity" / "app-icon" / "metadata.json"
EXPECTED_SOURCE_SHA256 = (
    "17a1678d5b6ffbbd6592c598664c5889777533d378354b4ff5672efacaa81ad7"
)

SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if sha256(SOURCE) != EXPECTED_SOURCE_SHA256:
        raise SystemExit("Approved Arxiv Discovery icon source hash does not match.")

    shutil.rmtree(ICONSET, ignore_errors=True)
    ICONSET.mkdir(parents=True)
    with Image.open(SOURCE) as source:
        if source.size != (2048, 2048):
            raise SystemExit(f"Expected a 2048x2048 source, got {source.size}.")
        for filename, size in SIZES.items():
            source.resize((size, size), Image.Resampling.NEAREST).save(
                ICONSET / filename,
                format="PNG",
                optimize=False,
            )

    subprocess.run(
        ["iconutil", "--convert", "icns", "--output", str(OUTPUT), str(ICONSET)],
        check=True,
    )
    shutil.rmtree(ICONSET)
    METADATA.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "source": "arxiv-discovery-v1.png",
                "sourceSha256": EXPECTED_SOURCE_SHA256,
                "sourceSize": [2048, 2048],
                "resampling": "nearest-neighbor",
                "icnsSha256": sha256(OUTPUT),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
