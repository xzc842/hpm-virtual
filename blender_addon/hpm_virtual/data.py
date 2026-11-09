"""HPM 项目、设备包、自定义虚拟包的发现与解析（与 Godot 运行时保持一致）。"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any


def normalize_path(path: str | os.PathLike[str]) -> str:
    return str(Path(path).expanduser().resolve())


def read_json(path: str | os.PathLike[str]) -> dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path: str | os.PathLike[str], data: Any) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def package_roots(project_dir: str = "") -> list[str]:
    roots: list[str] = []
    env = os.environ.get("HPM_PACKAGES_DIR", "")
    for part in env.split(":"):
        if part.strip():
            roots.append(normalize_path(part.strip()))
    if project_dir:
        roots.append(os.path.join(project_dir, "packages"))
        roots.append(os.path.join(project_dir, ".hpm", "packages"))
    home = os.environ.get("HOME", "")
    if home:
        roots.append(os.path.join(home, ".hpm", "packages"))
    return _unique(roots)


def virtual_pack_roots(project_dir: str = "") -> list[str]:
    roots: list[str] = []
    if project_dir:
        roots.append(os.path.join(project_dir, "virtual", "packages"))
    env = os.environ.get("HPM_VIRTUAL_PACKAGES", "")
    for part in env.split(":"):
        if part.strip():
            roots.append(normalize_path(part.strip()))
    home = os.environ.get("HOME", "")
    if home:
        roots.append(os.path.join(home, ".hpm", "virtual-packages"))
    return _unique(roots)


def _unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item and item not in seen:
            seen.add(item)
            result.append(item)
    return result


def _version_key(version: str) -> tuple[int, ...]:
    parts = []
    for piece in re.split(r"[.\-+]", version or "0"):
        try:
            parts.append(int(piece))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def iter_packages(project_dir: str = "") -> list[dict[str, Any]]:
    packages: list[dict[str, Any]] = []
    seen: set[str] = set()
    for root in package_roots(project_dir):
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            path = os.path.join(root, entry)
            if not os.path.isdir(path) or path in seen:
                continue
            manifest = read_json(os.path.join(path, "manifest.json"))
            if not manifest:
                continue
            seen.add(path)
            packages.append({"path": path, "dir_name": entry, "manifest": manifest})
    return packages


def find_package(driver: str, mcu: str, project_dir: str = "") -> dict[str, Any]:
    candidates: list[dict[str, Any]] = []
    for package in iter_packages(project_dir):
        manifest = package["manifest"]
        name = str(manifest.get("name", ""))
        if not _driver_matches(name, driver):
            continue
        if not _chip_matches(package, mcu):
            continue
        candidates.append(package)
    if not candidates:
        return {}
    candidates.sort(
        key=lambda item: _version_key(str(item["manifest"].get("version", ""))),
        reverse=True,
    )
    return candidates[0]


def _driver_matches(manifest_name: str, driver: str) -> bool:
    if not driver:
        return False
    if manifest_name == driver:
        return True
    return manifest_name.startswith(driver + "-") or manifest_name.startswith(driver + "_")


def _chip_matches(package: dict[str, Any], mcu: str) -> bool:
    if not mcu:
        return True
    manifest = package["manifest"]
    declared = str(manifest.get("chip", ""))
    if declared:
        return declared == mcu
    dir_name = str(package.get("dir_name", ""))
    return mcu in dir_name or "*" in dir_name


def _resolve_rel(base: str, rel: str, fallback: str) -> str:
    rel = (rel or fallback).strip()
    if os.path.isabs(rel):
        return rel
    if "/" in rel or "\\" in rel:
        return os.path.join(base, rel)
    return os.path.join(base, "debug", rel)


def find_custom_pack(project_dir: str, spec: Any) -> dict[str, Any]:
    name = ""
    version = ""
    explicit = ""
    if isinstance(spec, str):
        name = spec
        if os.path.isdir(normalize_path(spec)):
            explicit = spec
    elif isinstance(spec, dict):
        name = str(spec.get("name", ""))
        version = str(spec.get("version", ""))
        explicit = str(spec.get("path", ""))

    if explicit:
        path = explicit
        if not os.path.isabs(path) and project_dir:
            path = os.path.join(project_dir, path)
        path = normalize_path(path)
        if os.path.isdir(path):
            return _virtual_pack(path)

    candidates: list[dict[str, Any]] = []
    for root in virtual_pack_roots(project_dir):
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            path = os.path.join(root, entry)
            if not os.path.isdir(path):
                continue
            manifest = read_json(os.path.join(path, "manifest.json"))
            if str(manifest.get("type", "hpm-virtual-pack")) != "hpm-virtual-pack":
                continue
            pack_name = str(manifest.get("name", entry))
            if not (pack_name == name or pack_name.startswith(name + "-")
                    or entry == name or entry.startswith(name + "-")):
                continue
            if version and str(manifest.get("version", "")) != version:
                continue
            candidates.append(_virtual_pack(path))
    if not candidates:
        return {}
    candidates.sort(
        key=lambda item: _version_key(str(item["manifest"].get("version", ""))),
        reverse=True,
    )
    return candidates[0]


def _virtual_pack(path: str) -> dict[str, Any]:
    manifest = read_json(os.path.join(path, "manifest.json"))
    return {
        "path": path,
        "manifest": manifest,
        "name": str(manifest.get("name", os.path.basename(path))),
        "version": str(manifest.get("version", "")),
        "target": str(manifest.get("target", "")),
        "has_manifest": bool(manifest),
    }


def scan_custom_packs(project_dir: str) -> list[dict[str, Any]]:
    packs: list[dict[str, Any]] = []
    seen: set[str] = set()
    for root in virtual_pack_roots(project_dir):
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            path = os.path.join(root, entry)
            if not os.path.isdir(path) or path in seen:
                continue
            manifest = read_json(os.path.join(path, "manifest.json"))
            if str(manifest.get("type", "hpm-virtual-pack")) != "hpm-virtual-pack":
                continue
            seen.add(path)
            packs.append({
                "path": path,
                "name": str(manifest.get("name", entry)),
                "version": str(manifest.get("version", "")),
                "target": str(manifest.get("target", "")),
                "description": str(manifest.get("description", "")),
            })
    packs.sort(key=lambda item: (item["name"], _version_key(item["version"])), reverse=True)
    return packs


def pack_matches_device(pack: dict[str, Any], entry: dict[str, Any]) -> bool:
    target = str(pack.get("target", ""))
    if not target:
        return True
    driver = str(entry.get("driver", ""))
    package = str(entry.get("package", ""))
    return target in (driver, package) or package.startswith(target + "-") or target.startswith(package + "-")


def build_entry(project_dir: str, mcu: str, name: str, spec: dict[str, Any],
                override: Any = None) -> dict[str, Any]:
    driver = str(spec.get("driver", ""))
    package = find_package(driver, mcu, project_dir)
    entry: dict[str, Any] = {
        "name": name,
        "driver": driver,
        "spec": spec,
        "package": "",
        "version": "",
        "package_path": "",
        "device_json": {},
        "model_path": "",
        "script_path": "",
        "override": {},
        "error": "",
    }

    if package:
        package_path = package["path"]
        manifest = package["manifest"]
        device_json_path = os.path.join(package_path, "debug", "device.json")
        device_json = read_json(device_json_path)
        model_rel = str(device_json.get("model", "debug/device.gltf"))
        script_rel = str(device_json.get("script", "debug/virtual.gd"))
        entry.update({
            "package": str(manifest.get("name", driver)),
            "version": str(manifest.get("version", "")),
            "package_path": package_path,
            "device_json": device_json,
            "model_path": _resolve_rel(package_path, model_rel, "debug/device.gltf"),
            "script_path": _resolve_rel(package_path, script_rel, "debug/virtual.gd"),
        })
    else:
        entry["error"] = f"找不到设备包：{driver or '(空 driver)'}"

    override_pack = find_custom_pack(project_dir, override) if override else {}
    if override_pack:
        override_path = override_pack["path"]
        override_json = read_json(os.path.join(override_path, "device.json"))
        if override_json:
            entry["device_json"] = override_json
        model_candidates = [
            os.path.join(override_path, str(override_pack["manifest"].get("model", ""))),
            os.path.join(override_path, str(override_json.get("model", ""))),
            os.path.join(override_path, "model.gltf"),
            os.path.join(override_path, "model.glb"),
            os.path.join(override_path, "device.gltf"),
            os.path.join(override_path, "device.glb"),
        ]
        override_model = ""
        for candidate in model_candidates:
            if candidate and os.path.isfile(candidate):
                override_model = candidate
                break
        if override_model:
            entry["model_path"] = override_model
        else:
            fallback_model = _first_model_file(override_path)
            if fallback_model:
                entry["model_path"] = fallback_model
        for candidate in (
            os.path.join(override_path, "virtual.gd"),
            os.path.join(override_path, "debug", "virtual.gd"),
        ):
            if os.path.isfile(candidate):
                entry["script_path"] = candidate
                break
        entry["override"] = {
            "name": override_pack["name"],
            "version": override_pack["version"],
            "path": override_path,
            "target": override_pack["target"],
        }
    elif override:
        entry["error"] = (entry["error"] + "；" if entry["error"] else "") + f"自定义虚拟包缺失：{override}"

    return entry


def _first_model_file(directory: str) -> str:
    for entry in sorted(os.listdir(directory)):
        if entry.lower().endswith((".gltf", ".glb")):
            path = os.path.join(directory, entry)
            if os.path.isfile(path):
                return path
    return ""


def load_project(project_dir: str, overrides: dict[str, Any] | None = None) -> dict[str, Any]:
    root = normalize_path(project_dir)
    project_json = read_json(os.path.join(root, "project.json"))
    if not project_json:
        raise ValueError(f"不是有效的 HPM 项目（缺少 project.json）：{root}")
    mcu = str(project_json.get("mcu", ""))
    raw_devices = project_json.get("devices", {})
    if not isinstance(raw_devices, dict):
        raw_devices = {}
    overrides = overrides or {}
    devices: list[dict[str, Any]] = []
    for name, spec in raw_devices.items():
        if isinstance(spec, dict):
            devices.append(build_entry(root, mcu, str(name), spec, overrides.get(str(name))))
    return {
        "root": root,
        "project_json": project_json,
        "mcu": mcu,
        "devices": devices,
        "packs": scan_custom_packs(root),
    }
