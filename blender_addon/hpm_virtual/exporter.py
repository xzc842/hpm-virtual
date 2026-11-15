# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

"""导出 virtual.glb + virtual.json，并打包自定义虚拟包。"""

from __future__ import annotations

import json
import os
import shutil
from typing import Any

import bpy

from . import data, scene


def _physics_dict(obj: bpy.types.Object) -> dict[str, Any]:
    scene.ensure_physics_props(obj)
    return {
        "friction": round(float(scene.get_prop(obj, "hpm_friction", 0.8)), 4),
        "mass": round(float(scene.get_prop(obj, "hpm_mass", 1.0)), 4),
        "rough": bool(scene.get_prop(obj, "hpm_rough", True)),
        "bounce": round(float(scene.get_prop(obj, "hpm_bounce", 0.0)), 4),
        "enabled": bool(scene.get_prop(obj, "hpm_physics_enabled", True)),
    }


def _mesh_objects(root: bpy.types.Object) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for mesh in scene.meshes_under(root):
        result.append({
            "node": scene.relative_path(root, mesh),
            "physics": _physics_dict(mesh),
        })
    return result


def _device_objects(entry: dict[str, Any], root: bpy.types.Object) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "name": entry["name"],
        "node": _scene_path(root),
        "package": entry.get("package", ""),
        "version": entry.get("version", ""),
        "objects": _mesh_objects(root),
    }
    try:
        props = json.loads(str(scene.get_prop(root, "hpm_props", "") or "{}"))
        if isinstance(props, dict) and props:
            payload["props"] = props
    except ValueError:
        pass
    config = _kv_dict(scene.get_prop(root, "hpm_config_items", []))
    if not config:
        config = _json_object(str(scene.get_prop(root, "hpm_config", "") or "{}"))
    if config:
        payload["config"] = config

    override = entry.get("override") or {}
    if override:
        payload["override"] = {
            "name": override.get("name", ""),
            "version": override.get("version", ""),
        }
    return payload




def _kv_dict(items) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for item in items:
        key = str(item.key or "").strip()
        if not key:
            continue
        kind = str(item.value_type or "string")
        raw = str(item.value or "")
        if kind == "bool":
            result[key] = raw.strip().lower() in ("1", "true", "yes", "on")
        elif kind == "int":
            try:
                result[key] = int(raw)
            except ValueError:
                result[key] = 0
        elif kind == "float":
            try:
                result[key] = float(raw)
            except ValueError:
                result[key] = 0.0
        else:
            result[key] = raw
    return result

def _json_object(raw: str) -> dict[str, Any]:
    try:
        value = json.loads(raw or "{}")
    except ValueError:
        return {}
    return value if isinstance(value, dict) else {}


def _virtual_payload(item) -> dict[str, Any] | None:
    obj = bpy.data.objects.get(str(item.object_name or ""))
    if obj is None:
        obj = bpy.data.objects.get(str(item.name or ""))
    if obj is None:
        return None
    payload: dict[str, Any] = {
        "name": str(item.name),
        "node": _scene_path(obj),
        "package": str(item.package or ""),
        "version": str(item.version or "1.0.0"),
        "objects": _mesh_objects(obj),
    }
    config = _kv_dict(item.config_items)
    if not config:
        config = _json_object(str(item.config or "{}"))
    if config:
        payload["config"] = config
    physics = _kv_dict(item.physics_items)
    if not physics:
        physics = _json_object(str(item.physics or "{}"))
    if not physics:
        physics = _physics_dict(obj)
    payload["physics"] = physics
    override_path = str(item.override_path or "").strip()
    if override_path:
        payload["override"] = {
            "name": str(item.package or item.name),
            "version": str(item.version or "1.0.0"),
            "path": override_path,
        }
    return payload


def _prepare_virtual_devices(existing: dict[str, Any], exported_names: set[str],
                             warnings: list[str]) -> list[dict[str, Any]]:
    """把旧 JSON 的虚拟设备迁移到场景虚拟设备列表，再导出列表。"""
    scene = bpy.context.scene
    items = scene.hpm_virtual_devices
    if not bool(scene.hpm_virtual_list_ready):
        if isinstance(existing, dict):
            for old in existing.get("devices", []) or []:
                if not isinstance(old, dict):
                    continue
                name = str(old.get("name", ""))
                if not name or name in exported_names:
                    continue
                if any(entry.name == name for entry in items):
                    continue
                leaf = str(old.get("node", "")).rsplit("/", 1)[-1]
                obj = bpy.data.objects.get(leaf)
                if obj is None:
                    continue
                item = items.add()
                item.name = name
                item.object_name = obj.name
                item.package = str(old.get("package", ""))
                item.version = str(old.get("version", "1.0.0"))
                item.config = json.dumps(old.get("config", {}), ensure_ascii=False)
                item.physics = json.dumps(old.get("physics", {}), ensure_ascii=False)
                for key, value in (old.get("config", {}) or {}).items():
                    kv = item.config_items.add()
                    kv.key = str(key)
                    kv.value_type = "bool" if isinstance(value, bool) else "int" if isinstance(value, int) else "float" if isinstance(value, float) else "string"
                    kv.value = str(value).lower() if isinstance(value, bool) else str(value)
                for key, value in (old.get("physics", {}) or {}).items():
                    kv = item.physics_items.add()
                    kv.key = str(key)
                    kv.value_type = "bool" if isinstance(value, bool) else "int" if isinstance(value, int) else "float" if isinstance(value, float) else "string"
                    kv.value = str(value).lower() if isinstance(value, bool) else str(value)
                override = old.get("override") or {}
                item.override_path = str(override.get("path", ""))
        scene.hpm_virtual_list_ready = True
    result: list[dict[str, Any]] = []
    for item in items:
        payload = _virtual_payload(item)
        if payload is None:
            warnings.append(f"虚拟设备 {item.name} 找不到物体 {item.object_name}")
            continue
        if payload["name"] in exported_names:
            warnings.append(f"虚拟设备 {item.name} 与项目设备重名，已跳过")
            continue
        exported_names.add(payload["name"])
        result.append(payload)
    return result

def _environment_objects() -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for mesh in scene.environment_meshes():
        scene.ensure_physics_props(mesh)
        result.append({
            "node": _scene_path(mesh),
            "physics": _physics_dict(mesh),
        })
    return result


def _scene_path(obj: bpy.types.Object) -> str:
    names: list[str] = []
    node: bpy.types.Object | None = obj
    while node is not None:
        names.append(node.name)
        node = node.parent
    names.reverse()
    return "/".join(names)


def _instance_override(root: bpy.types.Object) -> dict[str, Any]:
    raw = str(scene.get_prop(root, "hpm_override", "") or "")
    if not raw:
        return {}
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else {}
    except ValueError:
        return {}


def _root_entry(project: dict[str, Any], entry: dict[str, Any],
                root: bpy.types.Object) -> dict[str, Any]:
    override = _instance_override(root)
    source = str(override.get("path", ""))
    spec = {"path": source} if source else None
    return data.build_entry(project["root"], project.get("mcu", ""),
                            entry["name"], entry.get("spec", {}), spec)


def _ensure_manifest(pack_dir: str, name: str, version: str, target: str) -> None:
    manifest_path = os.path.join(pack_dir, "manifest.json")
    manifest = data.read_json(manifest_path)
    if not manifest:
        manifest = {}
    manifest.setdefault("type", "hpm-virtual-pack")
    manifest.setdefault("name", name)
    manifest.setdefault("version", version)
    if target:
        manifest.setdefault("target", target)
    manifest.setdefault("license", "MIT")
    data.write_json(manifest_path, manifest)


def _copy_override_pack(override: dict[str, Any], project_root: str,
                        target: str, warnings: list[str]) -> str:
    source = str(override.get("path", ""))
    name = str(override.get("name", ""))
    version = str(override.get("version", ""))
    if not source or not os.path.isdir(source):
        warnings.append(f"自定义包目录不存在：{source}")
        return ""
    folder = f"{name}-{version}" if version else name
    destination = os.path.join(project_root, "virtual", "packages", folder)
    if os.path.abspath(source) != os.path.abspath(destination):
        def ignore(_dir: str, entries: list[str]) -> set[str]:
            return {
                entry for entry in entries
                if entry in ("__pycache__", ".git")
                or entry.endswith(".blend1")
                or entry.endswith(".zip")
            }

        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copytree(source, destination, dirs_exist_ok=True, ignore=ignore)
    _ensure_manifest(destination, name, version or "1.0.0", target)
    return folder


def export_project(project: dict[str, Any]) -> dict[str, Any]:
    root = project["root"]
    virtual_dir = os.path.join(root, "virtual")
    os.makedirs(virtual_dir, exist_ok=True)

    warnings: list[str] = []
    devices: list[dict[str, Any]] = []
    used_overrides: list[tuple[dict[str, Any], dict[str, Any]]] = []
    glb_path = os.path.join(virtual_dir, "virtual.glb")
    json_path = os.path.join(virtual_dir, "virtual.json")
    existing = data.read_json(json_path) if os.path.isfile(json_path) else {}
    existing_devices = {}
    if isinstance(existing, dict):
        existing_devices = {
            str(item.get("name", "")): item
            for item in existing.get("devices", []) or []
            if isinstance(item, dict) and str(item.get("name", ""))
        }

    for entry in project.get("devices", []):
        name = entry["name"]
        device_root = scene.find_device_root(name)
        if device_root is None:
            warnings.append(f"设备 {name} 尚未放置，已跳过")
            continue
        current = _root_entry(project, entry, device_root)
        if current.get("override_error"):
            warnings.append(f"设备 {name}：{current['override_error']}")
        payload = _device_objects(current, device_root)
        # 保留 virtual.json 里 Blender 不管理的字段（config / physics / props / override）。
        old = existing_devices.get(name)
        if isinstance(old, dict):
            for key in ("config", "physics", "props", "override"):
                if key in old and key not in payload:
                    payload[key] = old[key]
        devices.append(payload)
        if current.get("override"):
            used_overrides.append((current["override"], current))

    # 纯虚拟设备由场景里的虚拟设备列表生成；旧 JSON 的虚拟设备先迁移到列表。
    exported_names = {str(item.get("name", "")) for item in devices}
    devices.extend(_prepare_virtual_devices(existing, exported_names, warnings))

    virtual_json = {
        "version": 1,
        "scene": "virtual.glb",
        "objects": _environment_objects(),
        "devices": devices,
    }

    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        export_apply=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        use_selection=False,
        use_visible=True,
    )

    data.write_json(json_path, virtual_json)

    packs: list[str] = []
    copied: set[str] = set()
    for override, entry in used_overrides:
        driver = str(entry.get("driver", ""))
        folder = _copy_override_pack(override, root, driver, warnings)
        if folder and folder not in copied:
            copied.add(folder)
            packs.append(folder)

    return {
        "ok": True,
        "glb": glb_path,
        "json": json_path,
        "devices": [item["name"] for item in devices],
        "packs": packs,
        "warnings": warnings,
    }
