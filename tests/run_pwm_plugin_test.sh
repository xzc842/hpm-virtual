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

# 编译并运行 pwm 设备包的 debug.c 单元测试（PWM -> 角度）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES="${HPM_PACKAGES_DIR:-$HOME/.hpm/packages}"
HPM_SOURCE="${HPM_SOURCE:-$HOME/桌面/项目/hpm}"
INCLUDE="$HPM_SOURCE/build/include"

PKG="$(find "$PACKAGES" -maxdepth 1 -type d -name 'pwm-stc90c51-*' | sort | head -n 1)"
if [[ -z "$PKG" ]]; then
    echo "skip: pwm-stc90c51 package not installed" >&2
    exit 0
fi
if [[ ! -f "$INCLUDE/hpm/debug/plugin.h" ]]; then
    echo "skip: plugin header not found at $INCLUDE" >&2
    exit 0
fi

mkdir -p "$ROOT/.tmp"
cc -std=c11 -O2 -Wall -Wextra -I "$INCLUDE" \
    "$PKG/debug/debug.c" "$ROOT/tests/pwm_plugin_test.c" \
    -o "$ROOT/.tmp/pwm_plugin_test" -lm
"$ROOT/.tmp/pwm_plugin_test"
