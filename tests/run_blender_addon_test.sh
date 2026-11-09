#!/usr/bin/env bash
# Blender 插件无头测试。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLENDER="${BLENDER:-blender}"

"$BLENDER" --background --factory-startup --python-exit-code 1 \
    --python "$ROOT/tests/blender_addon_test.py"
