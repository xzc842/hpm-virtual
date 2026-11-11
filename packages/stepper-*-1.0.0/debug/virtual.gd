# MIT License
#
# Copyright (c) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# 步进电机轮子：angle 累计角度 -> 绕 X 轴旋转。
extends "res://sdk/virtual_device.gd"

var _wheel: Node3D
var _angle := 0.0
var _direction := 1

func _on_bind(_ctx: Dictionary) -> void:
	_wheel = get_model_node()
	if _wheel == null:
		log_warn("步进电机缺少模型根节点")
		return
	_apply()

func _on_values(new_values: Dictionary) -> void:
	if new_values.has("angle"):
		_angle = float(new_values["angle"])
	if new_values.has("direction"):
		_direction = int(new_values["direction"])
	_apply()

func _apply() -> void:
	if _wheel != null:
		_wheel.rotation_degrees.x = _angle

func get_angle() -> float:
	return _angle

func get_direction() -> int:
	return _direction
