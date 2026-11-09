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

# 标尺工具：射线取点、绘制透明蓝色标尺、自适应 m/cm 显示。
class_name RulerTool
extends Node3D

signal ruler_added(id: int, start: Vector3, end: Vector3)
signal ruler_removed(id: int)
signal ruler_count_changed(count: int)

const LINE_THICKNESS := 0.005
const ENDPOINT_RADIUS := 0.012
const DELETE_RADIUS_PX := 36.0

var _camera: Camera3D
var _active := false
var _next_id := 1
var _rulers: Array = []
var _pending_start: Variant = null
var _preview: Dictionary = {}

func setup(camera: Camera3D) -> void:
	_camera = camera
	set_process(false)

func set_active(active: bool) -> void:
	_active = active
	set_process(active)
	if not active:
		_cancel_pending()

func is_active() -> bool:
	return _active

func get_ruler_count() -> int:
	return _rulers.size()

func get_rulers() -> Array:
	return _rulers

# ---------------------------------------------------------------- 外部脚本 API

func add_ruler(start: Vector3, end: Vector3, label_text: String = "") -> int:
	if start.distance_to(end) < 0.0001:
		return -1
	var id := _next_id
	_next_id += 1
	var data := _create_visual(start, end, label_text)
	data["id"] = id
	data["start"] = start
	data["end"] = end
	data["custom_label"] = label_text
	_rulers.append(data)
	ruler_added.emit(id, start, end)
	ruler_count_changed.emit(_rulers.size())
	return id

func remove_ruler(id: int) -> bool:
	for index in range(_rulers.size()):
		if int(_rulers[index]["id"]) == id:
			_free_visual(_rulers[index])
			_rulers.remove_at(index)
			ruler_removed.emit(id)
			ruler_count_changed.emit(_rulers.size())
			return true
	return false

func clear_rulers() -> void:
	for data: Dictionary in _rulers:
		_free_visual(data)
	_rulers.clear()
	ruler_count_changed.emit(0)

# ---------------------------------------------------------------- 输入

func handle_input(event: InputEvent) -> bool:
	if not _active or _camera == null:
		return false
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			var hit = _raycast(mouse.position)
			if hit == null:
				return true
			if _pending_start == null:
				_pending_start = hit
				_create_preview(hit)
			else:
				add_ruler(_pending_start, hit)
				_cancel_pending()
			return true
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if _pending_start != null:
				_cancel_pending()
				return true
			var id := _ruler_at_screen(mouse.position)
			if id > 0:
				remove_ruler(id)
			return true
	return false

func _process(_delta: float) -> void:
	if not _active or _camera == null or _pending_start == null:
		return
	if get_viewport().gui_get_hovered_control() != null:
		_set_preview_visible(false)
		return
	var mouse := get_viewport().get_mouse_position()
	var hit = _raycast(mouse)
	if hit == null:
		_set_preview_visible(false)
		return
	_set_preview_visible(true)
	_update_visual(_preview, _pending_start, hit, "")
	_preview["start"] = _pending_start
	_preview["end"] = hit

# ---------------------------------------------------------------- 视觉

func _create_visual(start: Vector3, end: Vector3, custom_label: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Ruler"
	add_child(root)

	var material := _make_material(0.55)
	var line := MeshInstance3D.new()
	line.name = "Line"
	var box := BoxMesh.new()
	box.size = Vector3(LINE_THICKNESS, LINE_THICKNESS, 1.0)
	line.mesh = box
	line.material_override = material
	root.add_child(line)

	var start_marker := _make_marker()
	start_marker.material_override = _make_material(0.8)
	root.add_child(start_marker)

	var end_marker := _make_marker()
	end_marker.material_override = _make_material(0.8)
	root.add_child(end_marker)

	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.font_size = 42
	label.pixel_size = 0.001
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.modulate = Color(0.65, 0.88, 1.0)
	label.text = ""
	root.add_child(label)

	var data := {
		"id": 0,
		"root": root,
		"line": line,
		"start_marker": start_marker,
		"end_marker": end_marker,
		"label": label,
		"custom_label": custom_label,
		"start": start,
		"end": end,
	}
	_update_visual(data, start, end, custom_label)
	return data

func _update_visual(data: Dictionary, start: Vector3, end: Vector3,
		custom_label: String = "") -> void:
	var root: Node3D = data["root"]
	var line: MeshInstance3D = data["line"]
	var start_marker: MeshInstance3D = data["start_marker"]
	var end_marker: MeshInstance3D = data["end_marker"]
	var label: Label3D = data["label"]
	var delta := end - start
	var length := delta.length()
	if length < 0.0001:
		root.visible = false
		return
	root.visible = true
	var direction := delta.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.FORWARD
	line.transform = Transform3D(Basis.looking_at(direction, up), (start + end) * 0.5)
	var box := line.mesh as BoxMesh
	if box != null:
		box.size = Vector3(LINE_THICKNESS, LINE_THICKNESS, length)
	start_marker.position = start
	end_marker.position = end
	label.position = (start + end) * 0.5 + Vector3(0.0, 0.035, 0.0)
	var text := format_distance(length)
	if not custom_label.is_empty():
		text = custom_label + "\n" + text
	label.text = text

func _create_preview(start: Vector3) -> void:
	_cancel_preview()
	_preview = _create_visual(start, start, "")
	_preview["root"].name = "RulerPreview"
	_preview["root"].visible = false

func _cancel_preview() -> void:
	if not _preview.is_empty():
		_free_visual(_preview)
		_preview = {}

func _cancel_pending() -> void:
	_pending_start = null
	_cancel_preview()

func _set_preview_visible(visible: bool) -> void:
	if not _preview.is_empty():
		(_preview["root"] as Node3D).visible = visible

func _free_visual(data: Dictionary) -> void:
	var root: Node3D = data.get("root", null)
	if root != null and is_instance_valid(root):
		root.queue_free()

func _make_marker() -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = ENDPOINT_RADIUS
	sphere.height = ENDPOINT_RADIUS * 2.0
	marker.mesh = sphere
	return marker

func _make_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.65, 1.0, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func format_distance(distance: float) -> String:
	if distance >= 1.0:
		return "%.2f m" % distance
	return "%.1f cm" % (distance * 100.0)

# ---------------------------------------------------------------- 射线

func _raycast(screen_position: Vector2):
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var end := origin + direction * 500.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result.get("position", null)

func _ruler_at_screen(screen_position: Vector2) -> int:
	if _camera == null:
		return -1
	var best_id := -1
	var best_distance := DELETE_RADIUS_PX
	for data: Dictionary in _rulers:
		var start: Vector3 = data["start"]
		var end: Vector3 = data["end"]
		for i in range(9):
			var point := start.lerp(end, float(i) / 8.0)
			if _camera.is_position_behind(point):
				continue
			var screen := _camera.unproject_position(point)
			var distance := screen.distance_to(screen_position)
			if distance < best_distance:
				best_distance = distance
				best_id = int(data["id"])
	return best_id
