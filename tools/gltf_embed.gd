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

# 把 .gltf 的外部 .bin 内嵌为 base64，保证 HPM 包内没有二进制文件。
extends RefCounted

static func embed(path: String) -> bool:
	if not path.ends_with(".gltf"):
		return false
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var buffers: Variant = data.get("buffers", [])
	if typeof(buffers) != TYPE_ARRAY:
		return false
	var changed := false
	for buffer: Variant in buffers:
		if typeof(buffer) != TYPE_DICTIONARY:
			continue
		var uri := String(buffer.get("uri", ""))
		if uri.is_empty() or uri.begins_with("data:"):
			continue
		var bin_path := path.get_base_dir().path_join(uri)
		if not FileAccess.file_exists(bin_path):
			continue
		var bytes := FileAccess.get_file_as_bytes(bin_path)
		var data_uri := "data:application/octet-stream;base64," + Marshalls.raw_to_base64(bytes)
		var old := "\"uri\":\"" + uri + "\""
		if text.contains(old):
			text = text.replace(old, "\"uri\":\"" + data_uri + "\"")
		else:
			var regex := RegEx.new()
			regex.compile("\"uri\"\\s*:\\s*\"" + uri + "\"")
			if regex.search(text) == null:
				continue
			text = regex.sub(text, "\"uri\":\"" + data_uri + "\"", true)
		DirAccess.remove_absolute(bin_path)
		changed = true
	if changed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(text)
		file.close()
	return changed
