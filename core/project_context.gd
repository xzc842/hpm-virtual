# 当前打开的 HPM 项目上下文（Autoload: App）。
#
# 项目目录是用户磁盘上的任意目录，不是 res://；所有路径都按绝对路径处理。
class_name ProjectContext
extends Node

signal project_opened(info: Dictionary)
signal project_closed()
signal open_failed(message: String)

const RECENT_PATH := "user://recent_projects.json"
const MAX_RECENT := 10

var root_dir := ""
var project_json: Dictionary = {}
var virtual_json: Dictionary = {}
var has_virtual := false
var recent: Array = []

func _ready() -> void:
	_load_recent()

# ---------------------------------------------------------------- 打开/关闭

func open_project(dir: String) -> Dictionary:
	dir = _normalize_dir(dir)
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return _fail("目录不存在：%s" % dir)
	if not FileAccess.file_exists(dir.path_join("project.json")):
		return _fail("不是有效的 HPM 项目：缺少 project.json")

	var parsed := _read_json(dir.path_join("project.json"))
	if parsed.is_empty():
		return _fail("project.json 解析失败或为空")

	root_dir = dir
	project_json = parsed
	virtual_json = {}
	has_virtual = false

	var virtual_json_path := dir.path_join("virtual/virtual.json")
	if FileAccess.file_exists(virtual_json_path):
		var v := _read_json(virtual_json_path)
		if not v.is_empty():
			virtual_json = v
			has_virtual = true

	_add_recent(dir)
	var info := get_info()
	project_opened.emit(info)
	return {"ok": true, "needs_virtual": not has_virtual, "info": info}

func close_project() -> void:
	root_dir = ""
	project_json = {}
	virtual_json = {}
	has_virtual = false
	project_closed.emit()

func get_info() -> Dictionary:
	return {
		"root": root_dir,
		"name": root_dir.get_file() if not root_dir.is_empty() else "",
		"mcu": String(project_json.get("mcu", "")),
		"devices": project_json.get("devices", {}),
		"has_virtual": has_virtual,
		"virtual": virtual_json,
		"virtual_dir": virtual_dir(),
	}

func virtual_dir() -> String:
	return root_dir.path_join("virtual") if not root_dir.is_empty() else ""

func virtual_scene_path() -> String:
	if not has_virtual:
		return ""
	var scene := String(virtual_json.get("scene", "virtual.glb"))
	if scene.is_absolute_path():
		return scene
	return virtual_dir().path_join(scene)

func is_open() -> bool:
	return not root_dir.is_empty()

# ---------------------------------------------------------------- 最近项目

func _load_recent() -> void:
	recent.clear()
	if not FileAccess.file_exists(RECENT_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECENT_PATH))
	if typeof(data) == TYPE_ARRAY:
		for item: Variant in data:
			if typeof(item) == TYPE_STRING and not recent.has(item):
				recent.append(item)

func _save_recent() -> void:
	var f := FileAccess.open(RECENT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(recent, "\t"))

func _add_recent(dir: String) -> void:
	recent.erase(dir)
	recent.push_front(dir)
	while recent.size() > MAX_RECENT:
		recent.pop_back()
	_save_recent()

func clear_recent() -> void:
	recent.clear()
	_save_recent()

# ---------------------------------------------------------------- 工具

func _normalize_dir(dir: String) -> String:
	dir = dir.strip_edges()
	if dir.begins_with("~"):
		dir = OS.get_environment("HOME") + dir.substr(1)
	if dir.is_empty():
		return dir
	if not dir.is_absolute_path():
		var cwd := OS.get_environment("PWD")
		if cwd.is_empty():
			cwd = ProjectSettings.globalize_path("res://")
		dir = cwd.path_join(dir)
	dir = dir.simplify_path().trim_suffix("/")
	return dir

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("解析失败 %s: %s (行 %d)" % [path, json.get_error_message(), json.get_error_line()])
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("不是 JSON 对象：%s" % path)
		return {}
	return data

func _fail(message: String) -> Dictionary:
	push_error(message)
	open_failed.emit(message)
	return {"ok": false, "error": message, "needs_virtual": false}
