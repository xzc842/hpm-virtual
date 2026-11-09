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

# 把设备包 debug/ 目录缓存到 user:// 后再加载 GDScript。
#
# 外部脚本按约定是可信的：GDScript 权限等同于主程序本身，没有沙箱。
class_name ScriptHost
extends RefCounted

const CACHE_ROOT := "user://pkg_cache"

## 复制/复用缓存并返回可 load() 的脚本路径；失败返回空字符串。
static func cache_script(package_path: String, script_path: String) -> String:
	if not FileAccess.file_exists(script_path):
		return ""
	var debug_dir := script_path.get_base_dir()
	var signature := _dir_signature(debug_dir)
	if signature.is_empty():
		return ""
	var cache_dir := CACHE_ROOT.path_join("%s-%s-%s" % [
		package_path.get_file().validate_filename(),
		signature,
		package_path.sha256_text().substr(0, 6),
	])
	var target := cache_dir.path_join(script_path.get_file())
	if not FileAccess.file_exists(target):
		_copy_dir(debug_dir, cache_dir)
	if not FileAccess.file_exists(target):
		push_error("脚本缓存失败：%s -> %s" % [script_path, target])
		return ""
	return target

static func load_script(script_path: String) -> GDScript:
	if script_path.is_empty():
		return null
	var res: Resource = load(script_path)
	if res is GDScript:
		return res
	push_error("不是 GDScript：%s" % script_path)
	return null

## 递归复制目录。DirAccess 的 copy_absolute 不创建目标父目录，需要先建。
static func _copy_dir(src: String, dst: String) -> void:
	var err := DirAccess.make_dir_recursive_absolute(dst)
	if err != OK:
		push_error("创建缓存目录失败：%s (%s)" % [dst, error_string(err)])
		return
	var dir := DirAccess.open(src)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var src_path := src.path_join(entry)
		var dst_path := dst.path_join(entry)
		if dir.current_is_dir():
			_copy_dir(src_path, dst_path)
		else:
			var copy_err := DirAccess.copy_absolute(src_path, dst_path)
			if copy_err != OK:
				push_error("复制失败：%s -> %s (%s)" % [src_path, dst_path, error_string(copy_err)])
		entry = dir.get_next()
	dir.list_dir_end()

## 目录签名：文件名 + 大小 + 修改时间，任一变化都会得到新缓存目录。
static func _dir_signature(dir_path: String) -> String:
	var entries := _collect_files(dir_path)
	if entries.is_empty():
		return ""
	var parts := PackedStringArray()
	for item: Dictionary in entries:
		parts.append("%s|%d|%d" % [item["path"], item["size"], item["mtime"]])
	return "\n".join(parts).sha256_text().substr(0, 12)

static func _collect_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var path := dir_path.path_join(entry)
			if dir.current_is_dir():
				out.append_array(_collect_files(path))
			else:
				out.append({
					"path": path,
					"size": _file_size(path),
					"mtime": FileAccess.get_modified_time(path),
				})
		entry = dir.get_next()
	dir.list_dir_end()
	return out

static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var size := f.get_length()
	f.close()
	return size
