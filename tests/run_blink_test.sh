#!/usr/bin/env bash
# Blink 完整工程测试：构建固件 + 在 mcus 模拟器里确认 LED 状态切换。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/examples/blink"
LOG="$ROOT/.tmp/blink-debug.log"

mkdir -p "$ROOT/.tmp"
cd "$PROJECT"
hpm sync --offline
hpm build

# hpm debug 在 stdin EOF 时会退出，用 sleep 保持输入打开。
(sleep 6) | timeout 20 hpm debug --json --run > "$LOG" 2>/dev/null || true

on=$(grep -c '"message":"power=on"' "$LOG" || true)
off=$(grep -c '"message":"power=off"' "$LOG" || true)
echo "blink: power=on $on 次, power=off $off 次"
if [[ "$on" -lt 2 || "$off" -lt 2 ]]; then
    echo "FAIL: 没有观察到持续闪烁" >&2
    tail -5 "$LOG" >&2
    exit 1
fi
echo "BLINK: ok"
