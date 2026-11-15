#!/usr/bin/env python3
# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

"""把 .gltf 的外部 .bin buffer 内嵌成 base64，保证包内没有二进制文件。"""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path


def embed(path: Path) -> bool:
    data = json.loads(path.read_text(encoding="utf-8"))
    changed = False
    for buffer in data.get("buffers", []):
        uri = str(buffer.get("uri", ""))
        if not uri or uri.startswith("data:"):
            continue
        bin_path = path.parent / uri
        if not bin_path.is_file():
            continue
        raw = bin_path.read_bytes()
        if int(buffer.get("byteLength", len(raw))) != len(raw):
            raise ValueError(f"byteLength 不匹配: {bin_path}")
        encoded = base64.b64encode(raw).decode("ascii")
        buffer["uri"] = "data:application/octet-stream;base64," + encoded
        bin_path.unlink()
        changed = True
    if changed:
        path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n",
                        encoding="utf-8")
        print("embedded", path)
    return changed


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: embed_gltf_buffers.py <file.gltf> ...", file=sys.stderr)
        return 2
    for item in sys.argv[1:]:
        embed(Path(item).expanduser())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
