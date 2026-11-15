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

"""Blender 场景中保存的项目与模型设置。"""

from __future__ import annotations

import json
import os
from typing import Any

import bpy

from . import data


def _scene_prop(context, name: str, default: Any = "") -> Any:
    scene = context.scene
    value = getattr(scene, name, default)
    if value not in (None, ""):
        return value
    try:
        if name in scene.keys():
            return scene[name]
    except (AttributeError, TypeError):
        pass
    return default if value is None else value


def get_project_path(context) -> str:
    return str(_scene_prop(context, "hpm_project_path", ""))


def _parse(raw: str, default: Any) -> Any:
    if not raw:
        return default
    try:
        return json.loads(raw)
    except ValueError:
        return default


def get_model_settings(context) -> dict[str, dict[str, Any]]:
    value = _parse(str(_scene_prop(context, "hpm_model_settings", "")), {})
    return value if isinstance(value, dict) else {}


def set_model_settings(context, settings: dict[str, dict[str, Any]]) -> None:
    context.scene.hpm_model_settings = json.dumps(settings, ensure_ascii=False)


def get_setting(context, device_name: str) -> dict[str, Any]:
    value = get_model_settings(context).get(device_name, {})
    return value if isinstance(value, dict) else {}


def set_setting(context, device_name: str, setting: dict[str, Any]) -> None:
    settings = get_model_settings(context)
    if setting.get("use_custom_pack") and setting.get("custom_pack_path"):
        settings[device_name] = {
            "use_custom_pack": True,
            "custom_pack_path": setting["custom_pack_path"],
        }
    else:
        settings.pop(device_name, None)
    set_model_settings(context, settings)


def get_entries(context) -> list[dict[str, Any]]:
    value = _parse(str(_scene_prop(context, "hpm_device_entries", "")), [])
    if isinstance(value, list) and value:
        return value
    return recover_entries(context, persist=False)


def set_entries(context, entries: list[dict[str, Any]]) -> None:
    context.scene.hpm_device_entries = json.dumps(entries, ensure_ascii=False)


def get_packs(context) -> list[dict[str, Any]]:
    value = _parse(str(_scene_prop(context, "hpm_custom_packs", "")), [])
    return value if isinstance(value, list) else []


def set_packs(context, packs: list[dict[str, Any]]) -> None:
    context.scene.hpm_custom_packs = json.dumps(packs, ensure_ascii=False)


def get_project(context) -> dict[str, Any]:
    root = str(_scene_prop(context, "hpm_project_path", ""))
    return {
        "root": root,
        "mcu": str(_scene_prop(context, "hpm_mcu", "")),
        "devices": get_entries(context),
        "packs": get_packs(context),
    }


def recover_entries(context, persist: bool = False) -> list[dict[str, Any]]:
    """重新打开旧文件时，如果 entries 丢了，从项目目录和场景恢复。"""
    project_dir = str(_scene_prop(context, "hpm_project_path", ""))
    if not project_dir or not os.path.isdir(project_dir):
        return []
    overrides = {}
    for name, setting in get_model_settings(context).items():
        if setting.get("use_custom_pack") and setting.get("custom_pack_path"):
            overrides[name] = {"path": setting["custom_pack_path"]}
    try:
        project = data.load_project(project_dir, overrides)
    except ValueError:
        return []
    entries = project.get("devices", [])
    if persist and entries:
        set_entries(context, entries)
        set_packs(context, project.get("packs", []))
    return entries


def store_project(context, project: dict[str, Any]) -> None:
    context.scene.hpm_project_path = project["root"]
    context.scene.hpm_mcu = project.get("mcu", "")
    set_entries(context, project.get("devices", []))
    set_packs(context, project.get("packs", []))
    context.scene.hpm_last_export = ""


def find_entry(context, device_name: str) -> dict[str, Any] | None:
    for entry in get_entries(context):
        if entry.get("name") == device_name:
            return entry
    return None


def resolve_entry(context, device_name: str) -> dict[str, Any] | None:
    """按“当前模型设置”重新解析设备，用于新的放置。"""
    entry = find_entry(context, device_name)
    if entry is None:
        return None
    root = str(_scene_prop(context, "hpm_project_path", ""))
    mcu = str(context.scene.hpm_mcu or "")
    setting = get_setting(context, device_name)
    override = None
    if setting.get("use_custom_pack") and setting.get("custom_pack_path"):
        override = {"path": setting["custom_pack_path"]}
    return data.build_entry(root, mcu, device_name, entry.get("spec", {}), override)


def recover_virtual_devices(context) -> None:
    """从已有 virtual.json 恢复纯虚拟设备列表（不覆盖用户已编辑的列表）。"""
    scene = context.scene
    if bool(getattr(scene, "hpm_virtual_list_ready", False)) and len(scene.hpm_virtual_devices) > 0:
        return
    root = str(getattr(scene, "hpm_project_path", "") or "")
    if not root:
        return
    virtual_path = os.path.join(root, "virtual", "virtual.json")
    virtual = data.read_json(virtual_path)
    project_names = {str(entry.get("name", "")) for entry in get_entries(context)}
    items = scene.hpm_virtual_devices
    for entry in virtual.get("devices", []) or []:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name", ""))
        if not name or name in project_names:
            continue
        if any(item.name == name for item in items):
            continue
        node = str(entry.get("node", ""))
        obj = bpy.data.objects.get(node.rsplit("/", 1)[-1])
        if obj is None:
            continue
        item = items.add()
        item.name = name
        item.object_name = obj.name
        item.package = str(entry.get("package", ""))
        item.version = str(entry.get("version", "1.0.0"))
        item.override_path = str((entry.get("override") or {}).get("path", ""))
        for key, value in (entry.get("config", {}) or {}).items():
            kv = item.config_items.add()
            kv.key = str(key)
            kv.value_type = "bool" if isinstance(value, bool) else "int" if isinstance(value, int) else "float" if isinstance(value, float) else "string"
            kv.value = str(value).lower() if isinstance(value, bool) else str(value)
        for key, value in (entry.get("physics", {}) or {}).items():
            kv = item.physics_items.add()
            kv.key = str(key)
            kv.value_type = "bool" if isinstance(value, bool) else "int" if isinstance(value, int) else "float" if isinstance(value, float) else "string"
            kv.value = str(value).lower() if isinstance(value, bool) else str(value)
    scene.hpm_virtual_list_ready = True
