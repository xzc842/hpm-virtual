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
func resolve_device(instance: Dictionary, project: Dictionary) -> Dictionary:
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

	if pkg.is_empty():
		return {"ok": false, "error": "找不到设备包：%s" % package, "package": package, "version": version}

	var pkg_path := String(pkg["path"])
	var manifest: Dictionary = pkg["manifest"]
	var device_json := _read_json(pkg_path.path_join("debug/device.json"))
	var script_rel := String(instance.get("script", device_json.get("script", "debug/virtual.gd")))
	var model_rel := String(instance.get("model", device_json.get("model", "debug/device.gltf")))

	return {
		"ok": true,
		"package": String(manifest.get("name", package)),
		"version": String(manifest.get("version", version)),
		"package_path": pkg_path,
		"manifest": manifest,
		"device_json": device_json,
		"script_path": _resolve_relative(pkg_path, script_rel, "debug/virtual.gd"),
		"model_path": _resolve_relative(pkg_path, model_rel, "debug/device.gltf"),
	}

# ---------------------------------------------------------------- 内部

func _chip_matches(pkg: Dictionary, chip: String) -> bool:
	var manifest: Dictionary = pkg["manifest"]
	var declared := String(manifest.get("chip", ""))
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
