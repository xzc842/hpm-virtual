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

"""为两个示例工程生成可编辑的 virtual.blend。

用法：
  blender --background --factory-startup --python tools/build_example_blends.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "blender_addon"))

import hpm_virtual  # noqa: E402
from hpm_virtual import data, scene, state  # noqa: E402

PROJECTS = [ROOT / "examples" / "project1", ROOT / "examples" / "project2"]


def main() -> None:
    hpm_virtual.register()
    for project_dir in PROJECTS:
        build_project(project_dir)
    bpy.ops.wm.quit_blender()


def build_project(project_dir: Path) -> None:
    virtual = data.read_json(project_dir / "virtual" / "virtual.json")
    devices = {item.get("name"): item for item in virtual.get("devices", [])}
    overrides = {
        name: item["override"]
        for name, item in devices.items()
        if item.get("override")
    }
    project = data.load_project(str(project_dir), overrides)

    new_scene = bpy.data.scenes.new(f"HPM {project_dir.name}")
    bpy.context.window.scene = new_scene
    for old_scene in list(bpy.data.scenes):
        if old_scene != new_scene:
            bpy.data.scenes.remove(old_scene)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.import_scene.gltf(filepath=str(project_dir / "virtual" / "virtual.glb"))
    state.store_project(bpy.context, project)

    for entry in project.get("devices", []):
        name = entry["name"]
        root = bpy.data.objects.get(name)
        if root is None:
            root = find_object(name)
        if root is None:
            print(f"skip: 找不到设备根节点 {name}")
            continue

        inst = devices.get(name, {})
        root.hpm_device = json.dumps({
            "name": name,
            "driver": entry.get("driver", ""),
            "package": entry.get("package", ""),
            "version": entry.get("version", ""),
        }, ensure_ascii=False)
        root.hpm_props = json.dumps(inst.get("props", {}), ensure_ascii=False)

        override = entry.get("override") or {}
        if override:
            override_path = Path(override.get("path", ""))
            if override_path.is_absolute():
                override_path = override_path.relative_to(project_dir)
            root.hpm_override = json.dumps({
                "name": override.get("name", ""),
                "version": override.get("version", ""),
                "path": str(override_path),
            }, ensure_ascii=False)

        merged = merge_physics(entry.get("device_json", {}), inst)
        scene.apply_device_physics(root, merged)

        if override:
            state.set_setting(bpy.context, name, {
                "use_custom_pack": True,
                "custom_pack_path": str(Path(override.get("path", ""))),
            })

    apply_environment_physics(virtual)
    setup_camera_light()
    blend_path = project_dir / "virtual" / "virtual.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    print("wrote", blend_path)


def merge_physics(base: dict, instance: dict) -> dict:
    physics = dict(base.get("physics", {}))
    physics.update(instance.get("physics", {}))
    objects = list(instance.get("objects", [])) + list(base.get("objects", []))
    return {"physics": physics, "objects": objects}


def apply_environment_physics(virtual: dict) -> None:
    rules = {item.get("node"): item.get("physics", {})
             for item in virtual.get("objects", []) if isinstance(item, dict)}
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.hpm_physics_owner == "device":
            continue
        scene.ensure_physics_props(obj)
        physics = rules.get(obj.name)
        if physics:
            obj.hpm_friction = float(physics.get("friction", 0.8))
            obj.hpm_rough = bool(physics.get("rough", True))
            obj.hpm_bounce = float(physics.get("bounce", 0.0))
            obj.hpm_physics_enabled = bool(physics.get("enabled", True))


def setup_camera_light() -> None:
    bpy.ops.object.camera_add(location=(1.1, 0.9, 1.1))
    camera = bpy.context.active_object
    direction = Vector((0.0, 0.0, 0.05)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(type="SUN", location=(1.0, 1.0, 2.0))
    light = bpy.context.active_object
    light.data.energy = 3.0
    light.rotation_euler = (math.radians(35.0), math.radians(10.0), math.radians(30.0))


def find_object(name: str):
    for obj in bpy.data.objects:
        if obj.name == name:
            return obj
    return None


main()
