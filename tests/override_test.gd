# 自定义虚拟包解析测试。
#   godot --headless --path . --script res://tests/override_test.gd
extends SceneTree

const TEMP_DIR := "user://override_test"

var _failures := 0
var _checks := 0

func _init() -> void:
	_cleanup()
	var project_dir := ProjectSettings.globalize_path(TEMP_DIR)
	var pack_dir := project_dir.path_join("virtual/packages/blue-led-1.0.0")
	DirAccess.make_dir_recursive_absolute(pack_dir)
	_write(pack_dir.path_join("manifest.json"), JSON.stringify({
		"type": "hpm-virtual-pack",
		"name": "blue-led",
		"version": "1.0.0",
		"target": "gpio",
	}))
	_write(pack_dir.path_join("device.json"), JSON.stringify({
		"name": "gpio",
		"display_name": "Blue LED",
		"physics": {"friction": 0.11, "rough": true},
		"objects": [{"node": "LedBody", "physics": {"friction": 0.22}}],
	}))
	_write(pack_dir.path_join("virtual.gd"), 'extends "res://sdk/virtual_device.gd"\n')

	var resolver := PackageResolver.new(project_dir)
	var resolved := resolver.resolve_device({
		"name": "led", "package": "gpio", "version": "1.0.0", "override": "blue-led",
	}, {"mcu": "stc90c51"})
	_check(bool(resolved.get("ok", false)), "解析带 override 的设备")
	_check(String(resolved.get("script_path", "")).ends_with("blue-led-1.0.0/virtual.gd"), "脚本来自自定义包")
	_check(String(resolved.get("device_json", {}).get("display_name", "")) == "Blue LED", "device.json 来自自定义包")
	_check(is_equal_approx(float(resolved.get("device_json", {}).get("physics", {}).get("friction", 0.0)), 0.11), "物理参数来自自定义包")
	_check(not (resolved.get("override", {}) as Dictionary).is_empty(), "返回 override 元信息")

	var by_path := resolver.resolve_device({
		"name": "led", "package": "gpio", "version": "1.0.0",
		"override": {"path": "virtual/packages/blue-led-1.0.0"},
	}, {"mcu": "stc90c51"})
	_check(String(by_path.get("script_path", "")).ends_with("blue-led-1.0.0/virtual.gd"), "override.path 相对项目根")

	var missing := resolver.resolve_device({
		"name": "led", "package": "gpio", "version": "1.0.0", "override": "missing-pack",
	}, {"mcu": "stc90c51"})
	_check(bool(missing.get("ok", false)), "缺失自定义包时回退基础包")
	_check(String(missing.get("script_path", "")).ends_with("gpio-*/debug/virtual.gd") or String(missing.get("script_path", "")).contains("gpio"), "回退到 gpio 脚本")
	_check(not String(missing.get("override_error", "")).is_empty(), "报告缺失自定义包")

	_cleanup()
	print("OVERRIDE: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)

func _cleanup() -> void:
	var path := ProjectSettings.globalize_path(TEMP_DIR)
	if DirAccess.dir_exists_absolute(path):
		_remove_dir(path)

func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if dir.current_is_dir():
			_remove_dir(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
