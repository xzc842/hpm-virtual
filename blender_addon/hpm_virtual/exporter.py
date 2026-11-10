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
        "node": root.name,
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

    override = entry.get("override") or {}
    if override:
        payload["override"] = {
            "name": override.get("name", ""),
            "version": override.get("version", ""),
        }
    return payload


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

    for entry in project.get("devices", []):
        name = entry["name"]
        device_root = scene.find_device_root(name)
        if device_root is None:
            warnings.append(f"设备 {name} 尚未放置，已跳过")
            continue
        current = _root_entry(project, entry, device_root)
        if current.get("override_error"):
            warnings.append(f"设备 {name}：{current['override_error']}")
        devices.append(_device_objects(current, device_root))
        if current.get("override"):
            used_overrides.append((current["override"], current))

    virtual_json = {
        "version": 1,
        "scene": "virtual.glb",
        "objects": _environment_objects(),
        "devices": devices,
    }

    glb_path = os.path.join(virtual_dir, "virtual.glb")
    json_path = os.path.join(virtual_dir, "virtual.json")

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
