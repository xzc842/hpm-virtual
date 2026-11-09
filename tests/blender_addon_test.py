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
    shutil.copytree(ROOT / "examples" / "real-project", TEMP_DIR)
    return TEMP_DIR


def clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def make_custom_pack(project_dir: Path) -> Path:
    """只有模型、device.json、virtual.gd，没有 manifest。"""
    pack_dir = project_dir / "virtual" / "packages" / "blue-led-1.0.0"
    pack_dir.mkdir(parents=True, exist_ok=True)
    (pack_dir / "device.json").write_text(json.dumps({
        "name": "gpio",
        "display_name": "Blue LED",
        "physics": {"friction": 0.11, "rough": True},
        "objects": [{"node": "LedBody", "physics": {"friction": 0.11}}],
    }, ensure_ascii=False), encoding="utf-8")
    (pack_dir / "virtual.gd").write_text(
        'extends "res://sdk/virtual_device.gd"\n'
        'func _on_bind(_ctx): log_info("OVERRIDE LED BOUND")\n',
        encoding="utf-8",
    )
    gpio_debug = Path(data.find_package("gpio", "stc90c51", str(project_dir))["path"]) / "debug"
    shutil.copy2(gpio_debug / "device.gltf", pack_dir / "model.gltf")
    if (gpio_debug / "device0.bin").exists():
        shutil.copy2(gpio_debug / "device0.bin", pack_dir / "device0.bin")
    return pack_dir


def main() -> None:
    hpm_virtual.register()
    context = bpy.context
    project_dir = setup_project()
    clear_scene()

    print("[Load]")
    context.scene.hpm_project_path = str(project_dir)
    result = bpy.ops.hpm_virtual.load_project()
    check(result == {"FINISHED"}, "操作符加载项目")
    project = state.get_project(context)
    check(len(project["devices"]) == 2, "发现 2 个设备")
    led_entry = project["devices"][0]
    servo_entry = project["devices"][1]
    check(led_entry["package"] == "gpio", "LED 包为 gpio")
    check(servo_entry["package"] == "pwm-stc90c51", "舵机包为 pwm-stc90c51")

    print("[Place]")
    led_root = scene.place_device(context, project, led_entry, location=(-0.35, 0.12, 0.06))
    servo_root = scene.place_device(context, project, servo_entry, location=(0.2, 0.0, 0.0))
    check(led_root.name == "led", "LED 根节点名为 led")
    check(servo_root.name == "servo", "舵机根节点名为 servo")
    check(not _override_of(led_root), "默认模型没有 override")

    horn_hub = scene.find_node(servo_root, "ServoHorn/ServoHub")
    check(horn_hub is not None and abs(float(horn_hub.hpm_friction) - 0.35) < 1e-4,
          "舵机摆臂摩擦来自 device.json")
    scene.add_floor(context)

    print("[Edit model settings: only affects new placements]")
    pack_dir = make_custom_pack(project_dir)
    state.set_setting(context, "led", {
        "use_custom_pack": True,
        "custom_pack_path": str(pack_dir),
    })
    check(not _override_of(led_root), "已放置的 LED 不受设置影响")
    check(len(scene.meshes_under(led_root)) == 5, "原 LED 仍为 5 个网格")

    old_location = led_root.location.copy()
    scene.remove_device("led")
    entry = state.resolve_entry(context, "led")
    check(bool(entry.get("override")), "新放置解析出自定义包")
    check(str(entry.get("model_path", "")).endswith("blue-led-1.0.0/model.gltf"), "使用自定义模型")
    led_root = scene.place_device(context, project, entry, location=old_location)
    check(_override_of(led_root).get("name") == "blue-led-1.0.0", "新 LED 记录 override")

    barrel = scene.find_node(led_root, "LedBody/LedBarrel")
    check(barrel is not None and abs(float(barrel.hpm_friction) - 0.11) < 1e-4,
          "覆盖 device.json 的摩擦生效")
    barrel.hpm_friction = 0.42
    barrel.hpm_bounce = 0.15

    print("[Export]")
    result_operator = bpy.ops.hpm_virtual.export_project()
    check(result_operator == {"FINISHED"}, "操作符导出")
    result = json.loads(str(context.scene.hpm_last_export))
    check(result["ok"], "导出返回 ok")
    check(os.path.isfile(result["glb"]) and os.path.getsize(result["glb"]) > 1024, "virtual.glb 已写出")
    check("blue-led-1.0.0" in result["packs"], "自定义包已复制到项目")
    exported = json.loads(Path(result["json"]).read_text(encoding="utf-8"))
    check(len(exported["devices"]) == 2, "virtual.json 2 个设备")
    led_json = next(item for item in exported["devices"] if item["name"] == "led")
    servo_json = next(item for item in exported["devices"] if item["name"] == "servo")
    check(led_json["node"] == "led", "LED node 路径")
    check(led_json.get("override", {}).get("name") == "blue-led-1.0.0", "LED override 写入")
    check(len(servo_json["objects"]) == 8, "舵机 8 个物体摩擦")
    barrel_json = next(item for item in led_json["objects"] if item["node"] == "LedBody/LedBarrel")
    check(abs(barrel_json["physics"]["friction"] - 0.42) < 1e-4, "Blender 摩擦编辑写入 virtual.json")
    floor_json = next(item for item in exported["objects"] if item["node"] == "Floor")
    check(abs(floor_json["physics"]["friction"] - 0.9) < 1e-4, "地板摩擦写入 virtual.json")

    copied = project_dir / "virtual" / "packages" / "blue-led-1.0.0"
    check((copied / "virtual.gd").is_file(), "复制 virtual.gd")
    check((copied / "model.gltf").is_file(), "复制模型")
    generated = data.read_json(copied / "manifest.json")
    check(generated.get("type") == "hpm-virtual-pack", "自动生成 manifest")
    check(generated.get("name") == "blue-led-1.0.0", "manifest name 来自目录名")

    print("[Turn off: new placements revert]")
    check(_override_of(led_root).get("name") == "blue-led-1.0.0", "关闭前已放置实例保持覆盖")
    state.set_setting(context, "led", {"use_custom_pack": False, "custom_pack_path": ""})
    scene.remove_device("led")
    entry = state.resolve_entry(context, "led")
    check(not entry.get("override"), "关闭后解析回基础包")
    led_root = scene.place_device(context, project, entry, location=old_location)
    check(not _override_of(led_root), "关闭后新拖入恢复默认模型")

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
