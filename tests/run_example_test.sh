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

# 示例工程测试：构建 project1，确认两个 LED 闪烁、舵机角度变化。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/examples/project1"
LOG="$ROOT/.tmp/example-debug.log"

mkdir -p "$ROOT/.tmp"
cd "$PROJECT"
hpm sync --offline
hpm build

# hpm debug 在 stdin EOF 时会退出，用 sleep 保持输入打开。
(sleep 8) | timeout 25 hpm debug --json --run > "$LOG" 2>/dev/null || true

led1=$(grep -c '"device":"led1".*power=on' "$LOG" || true)
led2=$(grep -c '"device":"led2".*power=on' "$LOG" || true)
servo=$(grep -c '"device":"servo".*angle' "$LOG" || true)
echo "example: led1=on $led1 次, led2=on $led2 次, servo 状态 $servo 次"
if [[ "$led1" -lt 1 || "$led2" -lt 1 || "$servo" -lt 2 ]]; then
    echo "FAIL: 没有观察到 LED/舵机状态变化" >&2
    tail -8 "$LOG" >&2
    exit 1
fi
echo "EXAMPLE: ok"
