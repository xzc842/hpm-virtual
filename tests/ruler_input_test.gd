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

extends Node

var _failures := 0

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child(viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 3.0)
	viewport.add_child(camera)
	camera.current = true

	var body := StaticBody3D.new()
	body.position = Vector3(0.0, 0.0, -2.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 0.1)
	shape.shape = box
	body.add_child(shape)
	viewport.add_child(body)

	var ruler := RulerTool.new()
	viewport.add_child(ruler)
	ruler.setup(camera)
	ruler.set_active(true)

	await get_tree().physics_frame

	_check(ruler.handle_input(_click(Vector2(300.0, 300.0), MOUSE_BUTTON_LEFT)), "第一次左键")
	_check(ruler.get_ruler_count() == 0, "未完成两点前不生成标尺")
	_check(ruler.handle_input(_click(Vector2(500.0, 300.0), MOUSE_BUTTON_LEFT)), "第二次左键")
	_check(ruler.get_ruler_count() == 1, "生成一条标尺")

	_check(ruler.handle_input(_click(Vector2(400.0, 300.0), MOUSE_BUTTON_RIGHT)), "右键命中标尺")
	_check(ruler.get_ruler_count() == 0, "右键删除标尺")

	await get_tree().process_frame
	print("RULER INPUT: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _click(position: Vector2, button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = true
	return event

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)
