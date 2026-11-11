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

# 在 ~/.hpm/packages（以及项目内 packages/、.hpm/packages/、$HPM_PACKAGES_DIR）
# 中查找设备包，并解析出 debug/device.json、virtual.gd、device.gltf。
class_name PackageResolver
extends RefCounted

var project_dir := ""
var roots: PackedStringArray = []

var _packages: Array = []
var _scanned := false

func _init(project_dir_override: String = "") -> void:
	project_dir = project_dir_override
	_build_roots()

func _build_roots() -> void:
	roots = []
	var env := OS.get_environment("HPM_PACKAGES_DIR")
	if not env.is_empty():
		for part in env.split(":", false):
			if not part.is_empty():
				roots.append(part)
	if not project_dir.is_empty():
		roots.append(project_dir.path_join("packages"))
		roots.append(project_dir.path_join(".hpm/packages"))
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		roots.append(home.path_join(".hpm/packages"))

func scan(force: bool = false) -> Array:
	if _scanned and not force:
		return _packages
	_scanned = true
	_packages = []
	var seen := {}
	for root in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if not entry.begins_with("."):
				var path := root.path_join(entry)
				if DirAccess.dir_exists_absolute(path):
					var manifest := _read_json(path.path_join("manifest.json"))
					if not manifest.is_empty():
						var key := "%s@%s@%s" % [
							String(manifest.get("name", "")),
							String(manifest.get("version", "")),
							String(manifest.get("chip", "")),
						]
						if not seen.has(key):
							seen[key] = true
							_packages.append({
								"dir_name": entry,
								"path": path,
								"manifest": manifest,
							})
			entry = dir.get_next()
		dir.list_dir_end()
	return _packages

## 按 manifest.name / version / chip 查包；name 允许是 project.json 里的 driver 简写。
func find(package: String, version: String = "", chip: String = "") -> Dictionary:
	var candidates: Array = []
	for pkg: Dictionary in scan():
		var manifest: Dictionary = pkg["manifest"]
		if not _name_matches(String(manifest.get("name", "")), package, chip):
			continue
		if not chip.is_empty() and not _chip_matches(pkg, chip):
			continue
		candidates.append(pkg)

	if candidates.is_empty():
		return {}

	var matched: Array = []
	if not version.is_empty():
		for pkg: Dictionary in candidates:
			if String(pkg["manifest"].get("version", "")) == version:
				matched.append(pkg)
		if matched.is_empty():
			# 版本对不上时回退到同名的其它版本，由调用方在报告里提示。
			matched = candidates
	else:
		matched = candidates

	matched.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _version_cmp(String(a["manifest"].get("version", "")), String(b["manifest"].get("version", ""))) > 0
	)
	return matched[0]

## 把 virtual.json 中的一个设备实例解析成完整的运行时描述。
## 支持 devices[].override 覆盖模型、device.json 与 virtual.gd（见 docs/spec/custom-virtual-pack.md）。
func resolve_device(instance: Dictionary, project: Dictionary) -> Dictionary:
	var base := _resolve_base_package(instance, project)

	var override: Dictionary = {}
	var override_error := ""
	if instance.get("override") != null:
		override = find_virtual_pack(instance.get("override"))
		if override.is_empty():
			override_error = "自定义虚拟包缺失：%s" % str(instance.get("override"))

	if base.is_empty() and override.is_empty():
		return {
			"ok": false,
			"error": "找不到设备包：%s" % String(instance.get("package", "")),
			"package": String(instance.get("package", "")),
			"version": String(instance.get("version", "")),
		}

	var base_path := String(base.get("path", ""))
	var base_manifest: Dictionary = base.get("manifest", {})
	var base_json := _read_json(base_path.path_join("debug/device.json")) if not base_path.is_empty() else {}
	var base_script := ""
	var base_model := ""
	if not base_path.is_empty():
		var script_rel := String(instance.get("script", base_json.get("script", "debug/virtual.gd")))
		var model_rel := String(instance.get("model", base_json.get("model", "debug/device.gltf")))
		base_script = _resolve_relative(base_path, script_rel, "debug/virtual.gd")
		base_model = _resolve_relative(base_path, model_rel, "debug/device.gltf")

	var device_json: Dictionary = base_json
	var script_path := base_script
	var model_path := base_model
	var package_name := String(base_manifest.get("name", instance.get("package", "")))
	var package_version := String(base_manifest.get("version", instance.get("version", "")))

	if not override.is_empty():
		var override_path := String(override.get("path", ""))
		var override_manifest: Dictionary = override.get("manifest", {})
		var override_json := _read_json(override_path.path_join("device.json"))
		if not override_json.is_empty():
			device_json = override_json
			if package_name.is_empty():
				package_name = String(override_manifest.get("target", override_manifest.get("name", "")))
			if package_version.is_empty():
				package_version = String(override_manifest.get("version", ""))

		var override_script := _first_existing([
			override_path.path_join("virtual.gd"),
			override_path.path_join("debug/virtual.gd"),
			override_path.path_join(String(override_json.get("script", ""))),
		])
		if not override_script.is_empty():
			script_path = override_script

		var override_model := _first_existing([
			override_path.path_join(String(override_manifest.get("model", ""))),
			override_path.path_join(String(override_json.get("model", ""))),
			override_path.path_join("model.gltf"),
			override_path.path_join("model.glb"),
			override_path.path_join("device.gltf"),
			override_path.path_join("device.glb"),
		])
		if not override_model.is_empty():
			model_path = override_model

	var cache_root := base_path if not base_path.is_empty() else String(override.get("path", ""))
	return {
		"ok": true,
		"package": package_name,
		"version": package_version,
		"package_path": cache_root,
		"manifest": base_manifest,
		"device_json": device_json,
		"script_path": script_path,
		"model_path": model_path,
		"override": override,
		"override_error": override_error,
	}

func _resolve_base_package(instance: Dictionary, project: Dictionary) -> Dictionary:
	var mcu := String(project.get("mcu", ""))
	var package := String(instance.get("package", ""))
	var version := String(instance.get("version", ""))
	var pkg := find(package, version, mcu)

	if pkg.is_empty() and not package.is_empty():
		pkg = find(package, "", mcu)

	# virtual.json 没写 package 时，用 project.json 的 driver 反查。
	if pkg.is_empty():
		var project_devices: Dictionary = project.get("devices", {})
		var device_name := String(instance.get("name", ""))
		if project_devices.has(device_name):
			var pcfg: Dictionary = project_devices[device_name]
			var driver := String(pcfg.get("driver", ""))
			if not driver.is_empty():
				pkg = find(driver, "", mcu)
	return pkg

## 查找自定义虚拟包。spec 支持字符串或 {name, version, path}。
func find_virtual_pack(spec: Variant) -> Dictionary:
	var name := ""
	var version := ""
	var explicit_path := ""
	if typeof(spec) == TYPE_STRING:
		name = String(spec)
		if _is_dir(name):
			explicit_path = name
	elif typeof(spec) == TYPE_DICTIONARY:
		var data: Dictionary = spec
		name = String(data.get("name", ""))
		version = String(data.get("version", ""))
		explicit_path = String(data.get("path", ""))

	if not explicit_path.is_empty():
		var path := explicit_path
		if not path.is_absolute_path() and not project_dir.is_empty():
			path = project_dir.path_join(path)
		if _is_dir(path):
			return _read_virtual_pack(path)
		if name.is_empty():
			return {}

	var candidates: Array = []
	for root in _virtual_pack_roots():
		if not _is_dir(root):
			continue
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if not entry.begins_with(".") and dir.current_is_dir():
				var path := root.path_join(entry)
				var manifest := _read_json(path.path_join("manifest.json"))
				var pack_name := String(manifest.get("name", entry))
				if _pack_name_matches(pack_name, name) or _pack_name_matches(entry, name):
					if version.is_empty() or String(manifest.get("version", "")) == version:
						candidates.append({"path": path, "manifest": manifest, "dir_name": entry})
			entry = dir.get_next()
		dir.list_dir_end()

	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _version_cmp(
			String(a["manifest"].get("version", "")),
			String(b["manifest"].get("version", ""))
		) > 0
	)
	return candidates[0]

func _virtual_pack_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	if not project_dir.is_empty():
		roots.append(project_dir.path_join("virtual/packages"))
	var env := OS.get_environment("HPM_VIRTUAL_PACKAGES")
	if not env.is_empty():
		for part in env.split(":", false):
			if not part.is_empty():
				roots.append(part)
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		roots.append(home.path_join(".hpm/virtual"))
	return roots

func _read_virtual_pack(path: String) -> Dictionary:
	return {
		"path": path,
		"manifest": _read_json(path.path_join("manifest.json")),
		"dir_name": path.get_file(),
	}

func _pack_name_matches(candidate: String, name: String) -> bool:
	if name.is_empty():
		return false
	return candidate == name or candidate.begins_with(name + "-")

func _is_dir(path: String) -> bool:
	return not path.is_empty() and DirAccess.dir_exists_absolute(path)

func _first_existing(paths: Array) -> String:
	for path: Variant in paths:
		var text := String(path)
		if not text.is_empty() and FileAccess.file_exists(text):
			return text
	return ""

# ---------------------------------------------------------------- 内部

func _chip_matches(pkg: Dictionary, chip: String) -> bool:
	var manifest: Dictionary = pkg["manifest"]
	var declared := String(manifest.get("chip", ""))
	if declared == "*":
		return true
	if not declared.is_empty():
		return declared == chip
	# 很多设备包 manifest 没写 chip，用目录名兜底（如 usb_cdc-ch552g-1.0.0）。
	var dir_name := String(pkg.get("dir_name", ""))
	return dir_name.contains(chip) or dir_name.contains("*")

func _name_matches(manifest_name: String, package: String, chip: String) -> bool:
	if package.is_empty():
		return false
	if manifest_name == package:
		return true
	if not chip.is_empty() and manifest_name == "%s-%s" % [package, chip]:
		return true
	if not chip.is_empty() and manifest_name.begins_with(package + "-") and manifest_name.ends_with("-" + chip):
		return true
	# pwm -> pwm-stc90c51；usb_cdc -> usb_cdc_stm32f103c8t6
	if manifest_name.begins_with(package + "-") or manifest_name.begins_with(package + "_"):
		return true
	return false

func _resolve_relative(pkg_path: String, rel: String, fallback_rel: String) -> String:
	rel = rel.strip_edges()
	if rel.is_empty():
		rel = fallback_rel
	if rel.is_absolute_path():
		return rel
	if rel.contains("/"):
		return pkg_path.path_join(rel)
	# device.json 里只写 "virtual.gd" 时，按 debug/ 目录理解。
	return pkg_path.path_join("debug").path_join(rel)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _version_cmp(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	var count := maxi(pa.size(), pb.size())
	for i in range(count):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na - nb
	return 0
