#!/usr/bin/env python3
"""Pack locally fetched, pinned Android game PNGs as watch assets. Requires macOS sips."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/petpet-game-art")
manifest = json.loads((root / "Artwork/AndroidGameSources.json").read_text())
target = root / "PetPet Watch App/Assets.xcassets/Games"
target.mkdir(exist_ok=True)
info = {"author": "xcode", "version": 1}
(target / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
for item in manifest["files"]:
    original = source / Path(item["path"]).name
    data = original.read_bytes()
    digest = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    if digest != item["gitBlobSHA"]:
        raise ValueError("Source differs from pinned Android blob: " + original.name)
    folder = target / ("stepmate_game_" + original.stem + ".imageset")
    folder.mkdir(exist_ok=True)
    subprocess.run(["sips", "-Z", "512", str(original), "--out", str(folder / "image.png")], check=True, capture_output=True)
    contents = {"images": [{"filename": "image.png", "idiom": "universal"}], "info": info}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
print(f"Verified source hashes and packed {len(manifest['files'])} game PNGs at <=512px")
