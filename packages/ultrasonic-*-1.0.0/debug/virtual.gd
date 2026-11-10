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

# 超声波 3D 测量：
# - 从调试服务接收 target_distance（输入目标距离）
# - 把场景里的 Target 移到该距离，用射线做真实测量
# - 把实测距离通过 send("distance", cm) 写回模拟器
# - 实测值 < effective_distance 时实时更新标尺
extends "res://sdk/virtual_device.gd"

var _target: Node3D
var _ruler_id := -1
var _effective := 30.0
var _max_distance := 400.0
var _last_target := -1.0
var _last_measured := -1.0
var _auto_measure := false
var _auto_timer := 0.0

func _on_bind(_ctx: Dictionary) -> void:
	_effective = float(get_config("effective_distance", 30.0))
	_max_distance = float(get_config("max_distance", 400.0))
	var mode := String(get_config("sensor_mode", "single"))
	var report_enabled := bool(get_config("report_enabled", true))
	_auto_measure = bool(get_config("auto_measure", false))
	_target = get_scene_node("Target") as Node3D
	if _target == null:
		var root := get_scene_root()
		if root != null:
			_target = root.find_child("Target", true, false) as Node3D
	if _target != null:
		_target.visible = true
	log_info("有效距离 %.1f cm，模式 %s，上报 %s%s" % [
		_effective, mode, "开" if report_enabled else "关",
		"，自动测量" if _auto_measure else ""
	])
	set_process(_auto_measure)

func _on_values(new_values: Dictionary) -> void:
	if _auto_measure or not new_values.has("target_distance"):
		return
	var target_cm := float(new_values.get("target_distance", _max_distance))
	if absf(target_cm - _last_target) < 0.01:
		return
	_last_target = target_cm
	_measure.call_deferred(target_cm)

func _on_tick(delta: float) -> void:
	if not _auto_measure:
		return
	_auto_timer += delta
	if _auto_timer < 0.1:
		return
	_auto_timer = 0.0
	_measure_auto()

func _measure_auto() -> void:
	if model == null:
		return
	var forward := model.global_transform.basis.z.normalized()
	var origin := model.global_position + forward * 0.06 + Vector3.UP * 0.03
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 5.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _sensor_bodies()
	var hit := model.get_world_3d().direct_space_state.intersect_ray(query)
	var measured := _max_distance
	var hit_position := origin + forward * 5.0
	if not hit.is_empty():
		hit_position = hit.get("position", hit_position)
		measured = origin.distance_to(hit_position) * 100.0
	if absf(measured - _last_measured) < 0.1:
		return
	_last_measured = measured
	send("distance", measured)
	if measured < _effective:
		_update_ruler(origin, hit_position, measured)
	else:
		_clear_ruler()

func _measure(target_cm: float) -> void:
	if _target == null or model == null:
		return
	var forward := model.global_transform.basis.z.normalized()
	var meters := clampf(target_cm / 100.0, 0.02, maxf(_max_distance / 100.0, 5.0))
	_target.global_position = model.global_position + forward * meters + Vector3.UP * 0.08
	_target.visible = true
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	var origin := model.global_position + forward * 0.12 + Vector3.UP * 0.06
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 5.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _sensor_bodies()
	var hit := model.get_world_3d().direct_space_state.intersect_ray(query)
	var measured := _max_distance
	var hit_position := origin + forward * (target_cm / 100.0)
	if not hit.is_empty():
		hit_position = hit.get("position", hit_position)
		measured = origin.distance_to(hit_position) * 100.0
	_last_measured = measured
	send("distance", measured)

	if measured < _effective:
		_update_ruler(origin, hit_position, measured)
	else:
		_clear_ruler()

func _sensor_bodies() -> Array[RID]:
	var result: Array[RID] = []
	for node in model.find_children("*", "StaticBody3D", true, false):
		result.append((node as StaticBody3D).get_rid())
	return result

func _update_ruler(from_point: Vector3, to_point: Vector3, measured: float) -> void:
	if sim_view == null:
		return
	if _ruler_id < 0 or not sim_view.has_method("update_ruler"):
		_ruler_id = draw_ruler(from_point, to_point, "超声波")
		if _ruler_id >= 0:
			log_info("实测 %.1f cm < 有效距离，绘制标尺" % measured)
		return
	if not bool(sim_view.update_ruler(_ruler_id, from_point, to_point, "超声波")):
		_ruler_id = draw_ruler(from_point, to_point, "超声波")

func _clear_ruler() -> void:
	if _ruler_id >= 0 and sim_view != null and sim_view.has_method("remove_ruler"):
		sim_view.remove_ruler(_ruler_id)
	_ruler_id = -1

func _on_session_stop() -> void:
	_clear_ruler()

func _on_unbind() -> void:
	_clear_ruler()
