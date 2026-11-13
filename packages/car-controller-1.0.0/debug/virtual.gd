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

# 四轮差速底盘：只把固件的 STEP/DIR 指令转换成轮子接地点力，不做自主避障。
extends "res://sdk/virtual_device.gd"

const WHEELS := ["stepper_fl", "stepper_fr", "stepper_rl", "stepper_rr"]
const WHEEL_RADIUS := 0.08

var _car: Node3D
var _body: RigidBody3D
var _last: Dictionary = {}
var _accum: Dictionary = {}
var _sync_time := 0.0
var _visual_offset := Vector3.ZERO

func _on_bind(_ctx: Dictionary) -> void:
	_car = get_scene_node("Car") as Node3D
	if _car == null:
		_car = model
	if _car == null:
		return
	_body = _car.find_child("HPMRigidBody", true, false) as RigidBody3D
	if _body != null:
		_visual_offset = _body.global_position - _car.global_position
		_body.linear_damp = 0.2
		_body.angular_damp = 0.5
		_body.freeze = true
		_body.can_sleep = false
		log_info("物理底盘已绑定")
	else:
		log_warn("缺少 HPMRigidBody，底盘不会移动")
	for name: String in WHEELS:
		_last[name] = 0.0
		_accum[name] = 0.0

func _on_session_start() -> void:
	if _body != null:
		_body.freeze = false
		_body.sleeping = false

func _on_session_stop() -> void:
	if _body != null:
		_body.freeze = true
		_body.linear_velocity = Vector3.ZERO
		_body.angular_velocity = Vector3.ZERO

func _on_tick(delta: float) -> void:
	if _car == null or _body == null or sim_view == null or delta <= 0.0:
		return
	if not active:
		return
	var scripts: Dictionary = sim_view.get_device_scripts()
	if scripts.is_empty():
		return
	var fl: VirtualDevice = scripts.get("stepper_fl", null)
	var fr: VirtualDevice = scripts.get("stepper_fr", null)
	if fl == null or fr == null:
		return
	if not fl.has_method("get_direction") or not fr.has_method("get_direction"):
		return

	for name: String in WHEELS:
		var script: VirtualDevice = scripts.get(name, null)
		if script == null or not script.has_method("get_angle"):
			return
		var angle := float(script.get_angle())
		_accum[name] = float(_accum.get(name, 0.0)) + angle - float(_last.get(name, 0.0))
		_last[name] = angle
	_sync_time += delta
	if _sync_time < 0.05:
		return

	var left_angle := (float(_accum["stepper_fl"]) + float(_accum["stepper_rl"])) * 0.5
	var right_angle := (float(_accum["stepper_fr"]) + float(_accum["stepper_rr"])) * 0.5
	var accumulated := 0.0
	var angle_dirs: Dictionary = {}
	for name: String in WHEELS:
		var step_angle := float(_accum.get(name, 0.0))
		accumulated += absf(step_angle)
		angle_dirs[name] = signf(step_angle)
		_accum[name] = 0.0
	var wheel_speed := (left_angle + right_angle) * 0.5 * PI / 180.0 * WHEEL_RADIUS / _sync_time
	_sync_time = 0.0

	_car.global_position = _body.global_position - _visual_offset
	_car.global_rotation = _body.global_rotation
	if accumulated < 0.01:
		return

	var forward := _body.global_transform.basis.z.normalized()
	var positions: Array[Vector3] = [
		Vector3(-0.17, -0.05, 0.20),
		Vector3(0.17, -0.05, 0.20),
		Vector3(-0.17, -0.05, -0.20),
		Vector3(0.17, -0.05, -0.20),
	]
	var dirs := [
		float(angle_dirs["stepper_fl"]),
		float(angle_dirs["stepper_fr"]),
		float(angle_dirs["stepper_rl"]),
		float(angle_dirs["stepper_rr"]),
	]
	var left_drive := (float(dirs[0]) + float(dirs[2])) * 0.5
	var right_drive := (float(dirs[1]) + float(dirs[3])) * 0.5
	var turn := right_drive - left_drive
	if absf(turn) > 0.5:
		# 左右轮反向：绕 Y 轴施加转向力矩。
		_body.apply_torque(Vector3.UP * turn * 8.0)

	var target_speed := clampf(wheel_speed, -1.4, 1.4)
	var current_speed := _body.linear_velocity.dot(forward)
	var force := clampf((target_speed - current_speed) * _body.mass * 40.0, -80.0, 80.0)
	for i in range(4):
		_body.apply_force(forward * (absf(force) * 0.25) * float(dirs[i]), positions[i])
