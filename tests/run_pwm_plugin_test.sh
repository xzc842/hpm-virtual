#!/usr/bin/env bash
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
