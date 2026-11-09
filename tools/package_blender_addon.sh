#!/usr/bin/env bash
# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# 打包 Blender 插件为可安装 zip（manifest 在 zip 根目录）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/blender_addon/hpm_virtual"
DIST="$ROOT/dist"
VERSION="$(grep -E '^version = ' "$SOURCE/blender_manifest.toml" | head -n 1 | cut -d'"' -f2)"
OUT="$DIST/hpm_virtual-${VERSION}.zip"

mkdir -p "$DIST"
rm -f "$OUT"
(
    cd "$SOURCE"
    zip -r "$OUT" . -x '__pycache__/*' '*.pyc' >/dev/null
)
echo "$OUT"
