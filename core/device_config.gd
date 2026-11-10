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

# device.json / manifest.json 的 config 解析：
# - device.json 声明类型为 number / bool / string
# - manifest.config 兼容 HPM 的 int / string
# - project.json 与 virtual.json 的实例值优先，字符串会按声明类型转换
class_name DeviceConfig
extends RefCounted

static func resolve(
	device_json: Dictionary,
	manifest: Dictionary,
	project_device: Dictionary = {},
	instance: Dictionary = {}
) -> Dictionary:
	var schema := _collect_schema(manifest.get("config", {}), device_json.get("config", {}))
	var project_values: Dictionary = project_device.get("config", {}) if project_device.get("config") is Dictionary else {}
	var instance_values: Dictionary = instance.get("config", {}) if instance.get("config") is Dictionary else {}

	var result: Dictionary = {}
	for key: String in schema:
		var spec: Dictionary = schema[key]
		var value: Variant = spec.get("default", _type_default(spec.get("type", "string")))
		if project_values.has(key):
			value = project_values[key]
		if instance_values.has(key):
			value = instance_values[key]
		result[key] = _coerce(value, spec.get("type", "string"))

	# 未声明但 project/instance 里出现的键也交给脚本，保持为字符串。
	for source: Dictionary in [project_values, instance_values]:
		for key: Variant in source:
			var text := String(key)
			if not result.has(text):
				result[text] = source[key]
	return result

static func _collect_schema(manifest_config: Variant, device_config: Variant) -> Dictionary:
	var schema: Dictionary = {}
	if typeof(manifest_config) == TYPE_DICTIONARY:
		for key: Variant in manifest_config:
			if typeof(manifest_config[key]) == TYPE_DICTIONARY:
				schema[String(key)] = _normalize_spec(manifest_config[key])
	if typeof(device_config) == TYPE_DICTIONARY:
		for key: Variant in device_config:
			if typeof(device_config[key]) == TYPE_DICTIONARY:
				schema[String(key)] = _normalize_spec(device_config[key])
	return schema

static func _normalize_spec(raw: Dictionary) -> Dictionary:
	var spec := raw.duplicate(true)
	var kind := String(spec.get("type", "string")).to_lower()
	if kind in ["int", "float", "double", "number", "integer"]:
		spec["type"] = "number"
	elif kind in ["bool", "boolean"]:
		spec["type"] = "bool"
	else:
		spec["type"] = "string"
	return spec

static func _type_default(kind: Variant) -> Variant:
	match String(kind):
		"number":
			return 0.0
		"bool":
			return false
		_:
			return ""

static func _coerce(value: Variant, kind: Variant) -> Variant:
	match String(kind):
		"number":
			if typeof(value) == TYPE_BOOL:
				return 1.0 if value else 0.0
			if typeof(value) == TYPE_STRING:
				return value.to_float()
			return float(value)
		"bool":
			if typeof(value) == TYPE_BOOL:
				return value
			if typeof(value) == TYPE_STRING:
				var text: String = String(value).strip_edges().to_lower()
				if text in ["true", "1", "on", "yes", "y"]:
					return true
				if text in ["false", "0", "off", "no", "n", ""]:
					return false
			return bool(value)
		_:
			return str(value) if value != null else ""
