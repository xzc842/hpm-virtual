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

"""Blender 插件无头测试。

运行：
  blender --background --factory-startup --python-exit-code 1 \
    --python tests/blender_addon_test.py
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parent.parent
ADDON_DIR = ROOT / "blender_addon"
TEMP_DIR = ROOT / ".tmp" / "blender-test-project"
PACK_NAME = "clickable-led-1.0.0"

sys.path.insert(0, str(ADDON_DIR))
import hpm_virtual  # noqa: E402
from hpm_virtual import data, scene, state  # noqa: E402

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        failures.append(message)
        print(f"  FAIL {message}")


def setup_project() -> Path:
    if TEMP_DIR.exists():
        shutil.rmtree(TEMP_DIR)
    shutil.copytree(ROOT / "examples" / "project1", TEMP_DIR)
    return TEMP_DIR


def install_custom_pack(project_dir: Path) -> Path:
    source = ROOT / "examples" / "project2" / "virtual" / "packages" / PACK_NAME
    target = project_dir / "virtual" / "packages" / PACK_NAME
    shutil.copytree(source, target, dirs_exist_ok=True)
    return target


def clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    hpm_virtual.register()
    context = bpy.context
    project_dir = setup_project()
    install_custom_pack(project_dir)

    print("[Load]")
    context.scene.hpm_project_path = str(project_dir)
    check(bpy.ops.hpm_virtual.load_project() == {"FINISHED"}, "操作符加载项目")
    check(bpy.data.filepath == str(project_dir / "virtual" / "virtual.blend"),
          "自动打开 virtual.blend")
    clear_scene()
    project = state.get_project(context)
    check(len(project["devices"]) == 3, "发现 3 个设备")
    led1_entry = next(item for item in project["devices"] if item["name"] == "led1")
    led2_entry = next(item for item in project["devices"] if item["name"] == "led2")
    servo_entry = next(item for item in project["devices"] if item["name"] == "servo")
    check(led1_entry["package"] == "gpio", "LED1 包为 gpio")
    check(servo_entry["package"] == "pwm", "舵机包为 pwm-stc90c51")

    print("[Place]")
    led1_root = scene.place_device(context, project, led1_entry, location=(-0.35, 0.12, 0.06))
    led2_root = scene.place_device(context, project, led2_entry, location=(-0.15, -0.16, 0.06))
    servo_root = scene.place_device(context, project, servo_entry, location=(0.2, 0.0, 0.0))
    check(led1_root.name == "led1" and led2_root.name == "led2", "两个 LED 根节点")
    check(servo_root.name == "servo", "舵机根节点名为 servo")
    check(len(scene.meshes_under(led1_root)) == 5, "LED1 5 个网格")
    check(len(scene.meshes_under(led2_root)) == 5, "LED2 5 个网格")
    check(len(scene.meshes_under(servo_root)) == 8, "舵机 8 个网格")

    horn_hub = scene.find_node(servo_root, "ServoHorn/ServoHub")
    check(horn_hub is not None and abs(float(horn_hub.hpm_friction) - 0.35) < 1e-4,
          "舵机摆臂摩擦来自 device.json")
    scene.add_floor(context)

    print("[Custom pack: only affects new placements]")
    pack_dir = project_dir / "virtual" / "packages" / PACK_NAME
    state.set_setting(context, "led2", {
        "use_custom_pack": True,
        "custom_pack_path": str(pack_dir),
    })
    check(not _override_of(led2_root), "已放置的 LED2 不受设置影响")
    check(len(scene.meshes_under(led2_root)) == 5, "原 LED2 仍为 5 个网格")

    old_location = led2_root.location.copy()
    scene.remove_device("led2")
    entry = state.resolve_entry(context, "led2")
    check(bool(entry.get("override")), "新放置解析出自定义包")
    check(str(entry.get("model_path", "")).endswith(f"{PACK_NAME}/model.gltf"), "使用自定义模型")
    led2_root = scene.place_device(context, project, entry, location=old_location)
    check(_override_of(led2_root).get("name") == "clickable-led", "新 LED2 记录 override")

    barrel = scene.find_node(led2_root, "Body/Barrel2")
    check(barrel is not None and abs(float(barrel.hpm_friction) - 0.35) < 1e-4,
          "自定义包 device.json 摩擦生效")
    barrel.hpm_friction = 0.42
    barrel.hpm_bounce = 0.15

    print("[Export]")
    check(bpy.ops.hpm_virtual.export_project() == {"FINISHED"}, "操作符导出")
    result = json.loads(str(context.scene.hpm_last_export))
    check(result["ok"], "导出返回 ok")
    check(os.path.isfile(result["glb"]) and os.path.getsize(result["glb"]) > 1024, "virtual.glb 已写出")
    exported = json.loads(Path(result["json"]).read_text(encoding="utf-8"))
    check(len(exported["devices"]) == 3, "virtual.json 3 个设备")
    led2_json = next(item for item in exported["devices"] if item["name"] == "led2")
    servo_json = next(item for item in exported["devices"] if item["name"] == "servo")
    check(led2_json.get("override", {}).get("name") == "clickable-led", "LED2 override 写入")
    check(len(led2_json["objects"]) == 5, "LED2 5 个物体摩擦")
    check(len(servo_json["objects"]) == 8, "舵机 8 个物体摩擦")
    barrel_json = next(item for item in led2_json["objects"] if item["node"] == "Body/Barrel2")
    check(abs(barrel_json["physics"]["friction"] - 0.42) < 1e-4, "Blender 摩擦编辑写入 virtual.json")
    floor_json = next(item for item in exported["objects"] if item["node"] == "Floor")
    check(abs(floor_json["physics"]["friction"] - 0.9) < 1e-4, "地板摩擦写入 virtual.json")

    copied = project_dir / "virtual" / "packages" / PACK_NAME
    check((copied / "virtual.gd").is_file(), "复制 virtual.gd")
    check((copied / "model.gltf").is_file(), "复制模型")

    print("[Turn off: new placements revert]")
    check(_override_of(led2_root).get("name") == "clickable-led", "关闭前已放置实例保持覆盖")
    state.set_setting(context, "led2", {"use_custom_pack": False, "custom_pack_path": ""})
    scene.remove_device("led2")
    entry = state.resolve_entry(context, "led2")
    check(not entry.get("override"), "关闭后解析回基础包")
    led2_root = scene.place_device(context, project, entry, location=old_location)
    check(not _override_of(led2_root), "关闭后新拖入恢复默认模型")

    print(f"BLENDER ADDON: {len(failures)} failure(s)")
    if failures:
        for message in failures:
            print("  -", message)
        raise SystemExit(1)


def _override_of(root) -> dict:
    raw = str(root.hpm_override or "")
    if not raw:
        return {}
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else {}
    except ValueError:
        return {}


main()
