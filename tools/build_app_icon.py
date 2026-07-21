from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path

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
    properties = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(SOURCE)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if "pixelWidth: 2048" not in properties or "pixelHeight: 2048" not in properties:
        raise SystemExit("Expected a 2048x2048 approved icon source.")
    for filename, size in SIZES.items():
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(SOURCE), "--out", str(ICONSET / filename)],
            check=True,
            stdout=subprocess.DEVNULL,
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
                "id": "arxiv-discovery-v1",
                "source": "arxiv-discovery-v1.png",
                "sourceCandidate": "app-family-p5-arxiv-discovery",
                "sourceSha256": EXPECTED_SOURCE_SHA256,
                "sourceSize": [2048, 2048],
                "ownerApproved": True,
                "targetPlatforms": [
                    "native macOS application",
                    "Gnaroshi Studio managed-app card",
                ],
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
