"""Blender 场景中保存的项目与模型设置。"""

from __future__ import annotations

import json
from typing import Any

import bpy

from . import data


def _parse(raw: str, default: Any) -> Any:
    if not raw:
        return default
    try:
        return json.loads(raw)
    except ValueError:
        return default


def get_model_settings(context) -> dict[str, dict[str, Any]]:
    value = _parse(str(context.scene.hpm_model_settings or ""), {})
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
    value = _parse(str(context.scene.hpm_device_entries or ""), [])
    return value if isinstance(value, list) else []


def set_entries(context, entries: list[dict[str, Any]]) -> None:
    context.scene.hpm_device_entries = json.dumps(entries, ensure_ascii=False)


def get_packs(context) -> list[dict[str, Any]]:
    value = _parse(str(context.scene.hpm_custom_packs or ""), [])
    return value if isinstance(value, list) else []


def set_packs(context, packs: list[dict[str, Any]]) -> None:
    context.scene.hpm_custom_packs = json.dumps(packs, ensure_ascii=False)


def get_project(context) -> dict[str, Any]:
    root = str(context.scene.hpm_project_path or "")
    return {
        "root": root,
        "mcu": str(context.scene.hpm_mcu or ""),
        "devices": get_entries(context),
        "packs": get_packs(context),
    }


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
    root = str(context.scene.hpm_project_path or "")
    mcu = str(context.scene.hpm_mcu or "")
    setting = get_setting(context, device_name)
    override = None
    if setting.get("use_custom_pack") and setting.get("custom_pack_path"):
        override = {"path": setting["custom_pack_path"]}
    return data.build_entry(root, mcu, device_name, entry.get("spec", {}), override)
