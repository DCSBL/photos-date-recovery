#!/usr/bin/env python3
"""Export the PNG screenshots of an .xcresult as <name>.png, where name is the XCTAttachment name.

Only attachments the tests added on purpose are kept (not Xcode's automatic "UI Snapshot" ones).
Usage: export_screenshots.py RESULT.xcresult OUT_DIR
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def attachment_name(suggested: str) -> str:
    """Xcode appends `_<n>_<UUID>.png` to the attachment name."""
    return re.sub(r"_\d+_[0-9A-Fa-f-]{36}\.png$", "", suggested).removesuffix(".png")


def export(result: Path, out: Path) -> list[Path]:
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", tmp],
            check=True,
        )
        written = []
        for group in json.loads((Path(tmp) / "manifest.json").read_text()):
            for item in group.get("attachments", []):
                suggested = item.get("suggestedHumanReadableName", "")
                if not item.get("exportedFileName", "").endswith(".png") or suggested.startswith("UI Snapshot"):
                    continue
                target = out / f"{attachment_name(suggested)}.png"
                shutil.copy(Path(tmp) / item["exportedFileName"], target)
                written.append(target)
    return sorted(set(written))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    files = export(Path(sys.argv[1]), Path(sys.argv[2]))
    if not files:
        sys.exit("no screenshots in result bundle")
    print("\n".join(str(f) for f in files))
