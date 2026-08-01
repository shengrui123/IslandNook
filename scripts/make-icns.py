#!/usr/bin/env python3
"""Build a modern PNG-backed ICNS without depending on Xcode or Pillow."""

from pathlib import Path
import struct
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-icns.py <iconset-directory> <output.icns>")

    iconset = Path(sys.argv[1])
    output = Path(sys.argv[2])
    entries = [
        (b"icp4", "icon_16x16.png"),
        (b"icp5", "icon_32x32.png"),
        (b"icp6", "icon_32x32@2x.png"),
        (b"ic07", "icon_128x128.png"),
        (b"ic08", "icon_256x256.png"),
        (b"ic09", "icon_512x512.png"),
        (b"ic10", "icon_512x512@2x.png"),
    ]

    chunks = []
    for kind, filename in entries:
        payload = (iconset / filename).read_bytes()
        chunks.append(kind + struct.pack(">I", len(payload) + 8) + payload)

    body = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
