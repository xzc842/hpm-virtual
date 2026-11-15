#!/usr/bin/env bash
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

# 编译并运行 ultrasonic debug.c 单元测试（输入目标距离，3D 回写实测值）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES="${HPM_PACKAGES_DIR:-$HOME/.hpm/packages}"
HPM_SOURCE="${HPM_SOURCE:-$HOME/桌面/项目/hpm}"
INCLUDE="$HPM_SOURCE/build/include"

PKG="$(find "$PACKAGES" -maxdepth 1 -type d -name 'ultrasonic-*' | sort | head -n 1)"
if [[ -z "$PKG" ]]; then
    echo "skip: ultrasonic package not installed" >&2
    exit 0
fi
if [[ ! -f "$INCLUDE/hpm/debug/plugin.h" ]]; then
    echo "skip: plugin header not found at $INCLUDE" >&2
    exit 0
fi
mkdir -p "$ROOT/.tmp"
cc -std=c11 -O2 -Wall -Wextra -I "$INCLUDE" \
    "$PKG/debug/debug.c" "$ROOT/tests/ultrasonic_plugin_test.c" \
    -o "$ROOT/.tmp/ultrasonic_plugin_test" -lm
"$ROOT/.tmp/ultrasonic_plugin_test"
