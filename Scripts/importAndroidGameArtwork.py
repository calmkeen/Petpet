#!/usr/bin/env python3
"""Pack pinned Android PNGs. Usage: source-directory [manifest.json]. Requires sips."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/petpet-game-art")
manifest_path = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "Artwork/AndroidGameSources.json"
manifest = json.loads(manifest_path.read_text())
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
