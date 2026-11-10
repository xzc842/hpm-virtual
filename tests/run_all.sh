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

# 运行 Godot + PWM + Blender 插件的全部测试。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"

cd "$ROOT"
mkdir -p .tmp
: > .tmp/.gdignore
for test in smoke_test real_packages_test override_test project2_test config_test ultrasonic_scene_test servo_arm_test; do
    "$GODOT" --headless --path . --script "res://tests/${test}.gd"
done
"$GODOT" --headless --path . res://tests/ruler_input_test.tscn
"$GODOT" --headless --path . res://tests/interaction_test.tscn
"$ROOT/tests/run_pwm_plugin_test.sh"
"$ROOT/tests/run_blender_addon_test.sh"
if command -v hpm >/dev/null && command -v sdcc >/dev/null; then
    "$ROOT/tests/run_example_test.sh"
    "$ROOT/tests/run_ultrasonic_plugin_test.sh"
    "$ROOT/tests/run_servo_arm_build.sh"
else
    echo "skip: hpm/sdcc not installed"
fi
