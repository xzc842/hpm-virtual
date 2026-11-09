#!/usr/bin/env bash
# 构建并在 mcus 模拟器里运行 Blink（CLI 验证，不是 Godot 界面）。
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
hpm sync --offline
hpm build
exec hpm debug --run "$@"
