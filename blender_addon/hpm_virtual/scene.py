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

"""在 Blender 场景中放置设备、维护物体级摩擦参数。"""

from __future__ import annotations

import json
import os
from typing import Any

import bpy
from mathutils import Vector


DEFAULT_FRICTION = 0.8


def scene_of(context) -> bpy.types.Scene:
    return context.scene if context else bpy.context.scene


def active_collection(context) -> bpy.types.Collection:
    return context.collection if context else bpy.context.scene.collection


def get_prop(obj, name: str, default=""):
    """IDProperty 优先（兼容旧版本），否则读 RNA 属性。"""
    try:
        if name in obj.keys():
            return obj[name]
    except (AttributeError, TypeError):
        pass
    return getattr(obj, name, default)


def find_object(name: str):
    return bpy.data.objects.get(name)


def migrate_legacy_props() -> None:
    """把旧版本用 obj["hpm_*"]/scene["hpm_*"] 存的数据迁移到 RNA 属性。"""
    object_props = (
        "hpm_device", "hpm_props", "hpm_override", "hpm_friction", "hpm_rough",
        "hpm_bounce", "hpm_physics_enabled", "hpm_physics_owner",
    )
    for obj in bpy.data.objects:
        keys = obj.keys()
        for prop in object_props:
            if prop in keys:
                try:
                    setattr(obj, prop, obj[prop])
                    del obj[prop]
                except (TypeError, ValueError):
                    pass
    scene_props = (
        "hpm_project_path", "hpm_mcu", "hpm_device_entries", "hpm_model_settings",
        "hpm_custom_packs", "hpm_last_export",
    )
    for scene in bpy.data.scenes:
        keys = scene.keys()
        for prop in scene_props:
            if prop in keys:
                try:
                    setattr(scene, prop, scene[prop])
                    del scene[prop]
                except (TypeError, ValueError):
                    pass


def parse_device(obj: bpy.types.Object) -> dict[str, Any]:
    raw = get_prop(obj, "hpm_device", "")
    if not raw:
        return {}
    try:
        value = json.loads(str(raw))
        return value if isinstance(value, dict) else {}
    except ValueError:
        return {}


def device_roots() -> list[bpy.types.Object]:
    return [obj for obj in bpy.data.objects if get_prop(obj, "hpm_device", "")]


def find_device_root(name: str) -> bpy.types.Object | None:
    for obj in device_roots():
        if parse_device(obj).get("name") == name or obj.name == name:
            return obj
    return None


def remove_device(name: str) -> None:
    root = find_device_root(name)
    if root is not None:
        remove_hierarchy(root)


def remove_hierarchy(root: bpy.types.Object) -> None:
    for child in list(root.children):
        remove_hierarchy(child)
    bpy.data.objects.remove(root, do_unlink=True)


def meshes_under(root: bpy.types.Object) -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
    stack = [root]
    while stack:
        obj = stack.pop()
        if obj.type == "MESH":
            result.append(obj)
        stack.extend(list(obj.children))
    return result


def is_under(obj: bpy.types.Object, root: bpy.types.Object) -> bool:
    parent = obj.parent
    while parent is not None:
        if parent == root:
            return True
        parent = parent.parent
    return False


def environment_meshes() -> list[bpy.types.Object]:
    roots = device_roots()
    return [
        obj for obj in bpy.data.objects
        if obj.type == "MESH" and not any(is_under(obj, root) or obj == root for root in roots)
    ]


def relative_path(root: bpy.types.Object, obj: bpy.types.Object) -> str:
    names: list[str] = []
    node = obj
    while node is not None and node != root:
        names.append(node.name)
        node = node.parent
    names.reverse()
    return "/".join(names)


def find_node(root: bpy.types.Object, path: str) -> bpy.types.Object | None:
    if not path:
        return root
    node = root
    for piece in path.split("/"):
        if not piece:
            continue
        child = next((item for item in node.children if item.name == piece), None)
        if child is None:
            child = _find_by_name(node, piece)
        if child is None:
            return None
        node = child
    return node


def _find_by_name(root: bpy.types.Object, name: str) -> bpy.types.Object | None:
    stack = list(root.children)
    while stack:
        node = stack.pop()
        if node.name == name:
            return node
        stack.extend(list(node.children))
    return None


def _effective_physics(root: bpy.types.Object, mesh: bpy.types.Object,
                       device_json: dict[str, Any]) -> dict[str, Any]:
    rules: list[tuple[bpy.types.Object, dict[str, Any], int]] = []
    for item in device_json.get("objects", []):
        if not isinstance(item, dict):
            continue
        target = find_node(root, str(item.get("node", "")))
        if target is None:
            continue
        physics = item.get("physics", {})
        if isinstance(physics, dict):
            rules.append((target, physics, _depth(root, target)))

    chosen: dict[str, Any] = {}
    chosen_depth = -1
    node: bpy.types.Object | None = mesh
    while node is not None:
        for target, physics, depth in rules:
            if target == node and depth > chosen_depth:
                chosen = physics
                chosen_depth = depth
        if node == root:
            break
        node = node.parent

    if not chosen:
        chosen = device_json.get("physics", {})
    if not isinstance(chosen, dict):
        chosen = {}
    return chosen


def _depth(root: bpy.types.Object, obj: bpy.types.Object) -> int:
    depth = 0
    node = obj
    while node is not None and node != root:
        depth += 1
        node = node.parent
    return depth


def apply_device_physics(root: bpy.types.Object, device_json: dict[str, Any]) -> None:
    for mesh in meshes_under(root):
        physics = _effective_physics(root, mesh, device_json)
        mesh.hpm_friction = float(physics.get("friction", DEFAULT_FRICTION))
        mesh.hpm_rough = bool(physics.get("rough", True))
        mesh.hpm_bounce = float(physics.get("bounce", 0.0))
        mesh.hpm_physics_enabled = bool(physics.get("enabled", True))
        mesh.hpm_physics_owner = "device"


def ensure_physics_props(obj: bpy.types.Object) -> None:
    """属性都有 RNA 默认值；这里只补归属，便于导出时区分设备/环境。"""
    if obj.type != "MESH":
        return
    if not obj.hpm_physics_owner:
        obj.hpm_physics_owner = "environment"


def _import_model(path: str) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, import_scene_extras=True,
                              import_select_created_objects=True)
    return [obj for obj in bpy.data.objects if obj not in before]


def place_device(context, project: dict[str, Any], entry: dict[str, Any],
                 location=None) -> bpy.types.Object:
    name = str(entry.get("name", ""))
    model_path = str(entry.get("model_path", ""))
    if not model_path or not os.path.isfile(model_path):
        raise FileNotFoundError(f"设备 {name} 没有可用的模型：{model_path or '(空)'}")

    remove_device(name)
    imported = _import_model(model_path)
    if not imported:
        raise RuntimeError(f"导入模型失败：{model_path}")

    roots = [obj for obj in imported if obj.parent is None or obj.parent not in imported]
    if len(roots) == 1:
        root = roots[0]
    else:
        root = bpy.data.objects.new(name, None)
        active_collection(context).objects.link(root)
        for item in roots:
            item.parent = root
            item.matrix_parent_inverse = root.matrix_world.inverted()

    root.name = name
    root.parent = None
    scene = scene_of(context)
    root.location = Vector(location) if location is not None else scene.cursor.location.copy()

    info = {
        "name": name,
        "driver": entry.get("driver", ""),
        "package": entry.get("package", ""),
        "version": entry.get("version", ""),
    }
    root.hpm_device = json.dumps(info, ensure_ascii=False)
    root.hpm_props = json.dumps(entry.get("spec", {}).get("props", {}), ensure_ascii=False)
    override = entry.get("override") or {}
    if override:
        root.hpm_override = json.dumps({
            "name": override.get("name", ""),
            "version": override.get("version", ""),
            "path": override.get("path", ""),
        }, ensure_ascii=False)
    else:
        root.hpm_override = ""

    apply_device_physics(root, entry.get("device_json", {}))

    bpy.context.view_layer.objects.active = root
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    root.select_set(True)
    return root


def add_floor(context, size: float = 4.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0.0, 0.0, -0.002))
    floor = bpy.context.active_object
    floor.name = "Floor"
    floor.hpm_physics_enabled = True
    floor.hpm_friction = 0.9
    floor.hpm_rough = True
    floor.hpm_bounce = 0.0
    floor.hpm_physics_owner = "environment"
    return floor
