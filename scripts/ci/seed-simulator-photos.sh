#!/usr/bin/env bash
# Puts photos with known filenames in a simulator's library and grants Phtofxr full photo access, so
# PhotoKitIntegrationTests can check what PhotoKit reports for them. The JPEGs carry no EXIF date and have
# their file date set to 11 October 2016, like the user's old import.
# Usage: seed-simulator-photos.sh <simulator-udid>
set -euo pipefail

udid="${1:?usage: $0 <simulator-udid>}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A tiny PNG built in Python (no image libraries on the runner), turned into a JPEG by sips.
python3 - "$work/base.png" <<'PY'
import struct, sys, zlib
w = h = 8
raw = b"".join(b"\x00" + b"\xf0\x80\x30" * w for _ in range(h))
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY
sips -s format jpeg "$work/base.png" --out "$work/base.jpg" >/dev/null

names=(
  "IMG_20170223_123456.jpg"
  "IMG-20220201-WA0001.jpg"
  "2015-05-18 20.17.49.jpg"
  "PXL_20210101_123456789.jpg"
  "IMG_1234.jpg"
)
files=()
for name in "${names[@]}"; do
  cp "$work/base.jpg" "$work/$name"
  touch -t 201610111423 "$work/$name"
  files+=("$work/$name")
done

xcrun simctl addmedia "$udid" "${files[@]}"
xcrun simctl privacy "$udid" grant photos nl.dcsbl.phtofxr
echo "Seeded ${#files[@]} photos into $udid and granted photo access."
