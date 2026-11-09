#!/usr/bin/env bash
# 运行 Godot + PWM + Blender 插件的全部测试。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"

cd "$ROOT"
for test in smoke_test real_packages_test override_test; do
    "$GODOT" --headless --path . --script "res://tests/${test}.gd"
done
"$GODOT" --headless --path . res://tests/ruler_input_test.tscn
"$GODOT" --headless --path . res://tests/interaction_test.tscn
"$ROOT/tests/run_pwm_plugin_test.sh"
"$ROOT/tests/run_blender_addon_test.sh"
if command -v hpm >/dev/null && command -v sdcc >/dev/null; then
    "$ROOT/tests/run_blink_test.sh"
else
    echo "skip: hpm/sdcc not installed"
fi
