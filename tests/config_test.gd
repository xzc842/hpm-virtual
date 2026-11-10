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

# device.json config 声明与 project.json 覆盖测试。
#   godot --headless --path . --script res://tests/config_test.gd
extends SceneTree

const DeviceConfigScript := preload("res://core/device_config.gd")

var _failures := 0
var _checks := 0

func _init() -> void:
	var device_json := {
		"config": {
			"effective_distance": {
				"type": "number", "title": "有效距离", "default": 30.0,
			},
			"enabled": {"type": "bool", "default": true},
			"mode": {"type": "string", "default": "auto"},
		},
	}
	var manifest := {
		"config": {
			"effective_distance": {"type": "int", "default": "20"},
			"max_distance": {"type": "int", "default": "400"},
		},
	}
	var project_device := {
		"config": {
			"effective_distance": "35",
			"enabled": "false",
			"mode": "manual",
			"extra_key": "kept",
		},
	}
	var config := DeviceConfigScript.resolve(device_json, manifest, project_device, {})
	_check(is_equal_approx(float(config.get("effective_distance", 0.0)), 35.0), "数值覆盖并转换")
	_check(config.get("enabled") == false, "布尔字符串转换")
	_check(String(config.get("mode", "")) == "manual", "字符串保留")
	_check(is_equal_approx(float(config.get("max_distance", 0.0)), 400.0), "manifest 默认值")
	_check(String(config.get("extra_key", "")) == "kept", "未声明键保留")
	_check(config.get("effective_distance") is float, "数值类型为 float")

	var instance := {"config": {"effective_distance": 12.5}}
	var config2 := DeviceConfigScript.resolve(device_json, manifest, project_device, instance)
	_check(is_equal_approx(float(config2.get("effective_distance", 0.0)), 12.5), "实例配置优先")
	_check(config2.get("enabled") == false, "未覆盖字段沿用项目值")

	print("CONFIG: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)
