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
	var result := App.open_project(ProjectSettings.globalize_path("res://tests/fixtures/demo-project"))
	if not bool(result.get("ok", false)):
		_fail("打开 demo 项目")
		_finish()
		return

	var sim := SimView.new()
	add_child(sim)
	sim.setup(App.get_info())
	await get_tree().process_frame

	var scripts := sim.get_device_scripts()
	_check(scripts.has("led"), "绑定 LED 脚本")
	var led: VirtualDevice = scripts.get("led", null)
	if led == null:
		_finish()
		return
	_check(led.has_interaction(), "LED 注册了交互")
	_check(led.get_scene_root() != null, "脚本可读场景根")
	_check(led.get_scene_node("Environment/Floor") != null, "脚本可读场景节点")

	var meshes := led.model.find_children("*", "MeshInstance3D", true, false)
	var screen := sim._camera.unproject_position(led.model.global_position + Vector3(0.0, 0.06, 0.0))
	var hit := sim._raycast_mouse(screen)
	_check(not hit.is_empty(), "鼠标射线命中设备")
	if not hit.is_empty():
		_check(sim._device_name_for_collider(hit.get("collider")) == "led", "射线解析到 led")

	sim._set_hover("led", led.get_interaction_hint())
	_check(_first_overlay(meshes) != null, "悬停高亮")
	sim._clear_hover()
	_check(_first_overlay(meshes) == null, "取消高亮")

	_check(led.trigger_interaction("flash"), "触发 LED 交互")
	sim.queue_free()
	await get_tree().process_frame
	_finish()

func _first_overlay(meshes: Array) -> Material:
	for item in meshes:
		var mesh := item as MeshInstance3D
		if mesh != null and mesh.material_overlay != null:
			return mesh.material_overlay
	return null

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_fail(message)

func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL ", message)

func _finish() -> void:
	print("INTERACTION: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
