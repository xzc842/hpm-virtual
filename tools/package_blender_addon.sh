#!/usr/bin/env bash
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
