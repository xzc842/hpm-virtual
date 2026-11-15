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

# 四轮车辆：STEP/DIR 控制 VehicleWheel3D 的驱动力，轮胎与地面摩擦推动车身。
extends "res://sdk/virtual_device.gd"

const WHEELS := ["stepper_fl", "stepper_fr", "stepper_rl", "stepper_rr"]
const WHEEL_NODES := ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]
const MAX_ENGINE_FORCE := 10.0

var _car: Node3D
var _vehicle: VehicleBody3D
var _wheels: Array[VehicleWheel3D] = []
var _last: Dictionary = {}
var _accum: Dictionary = {}
var _sync_time := 0.0
var _visual_local := Transform3D.IDENTITY

func _on_bind(_ctx: Dictionary) -> void:
	_car = get_scene_node("Car") as Node3D
	if _car == null:
		_car = model
	if _car == null:
		return
	_vehicle = _car.find_child("HPMVehicle", true, false) as VehicleBody3D
	if _vehicle == null:
		log_warn("缺少 HPMVehicle，底盘不会移动")
		return
	_visual_local = _vehicle.global_transform.affine_inverse() * _car.global_transform
	_vehicle.freeze = true
	_vehicle.can_sleep = false
	for name: String in WHEEL_NODES:
		var wheel := _vehicle.get_node_or_null(name) as VehicleWheel3D
		if wheel != null:
			_wheels.append(wheel)
	for name: String in WHEELS:
		_last[name] = 0.0
		_accum[name] = 0.0
	log_info("车辆底盘已绑定")

func _on_session_start() -> void:
	if _vehicle != null:
		_vehicle.freeze = true
		_vehicle.sleeping = false

func _on_session_stop() -> void:
	if _vehicle != null:
		_vehicle.freeze = true
		_vehicle.linear_velocity = Vector3.ZERO
		_vehicle.angular_velocity = Vector3.ZERO

func _on_tick(delta: float) -> void:
	if _car == null or _vehicle == null or sim_view == null or delta <= 0.0:
		return
	if not active:
		return
	var scripts: Dictionary = sim_view.get_device_scripts()
	if scripts.is_empty():
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

	var total := 0.0
	for name: String in WHEELS:
		total += absf(float(_accum.get(name, 0.0)))
	if total < 0.01:
		_sync_time = 0.0
		return
	var dt := _sync_time
	_sync_time = 0.0
	if _vehicle.freeze:
		_vehicle.freeze = false
		_vehicle.sleeping = false

	var fl := float(signf(float(_accum.get("stepper_fl", 0.0))))
	var fr := float(signf(float(_accum.get("stepper_fr", 0.0))))
	var rl := float(signf(float(_accum.get("stepper_rl", 0.0))))
	var rr := float(signf(float(_accum.get("stepper_rr", 0.0))))
	var left_angle := (float(_accum["stepper_fl"]) + float(_accum["stepper_rl"])) * 0.5
	var right_angle := (float(_accum["stepper_fr"]) + float(_accum["stepper_rr"])) * 0.5
	for name: String in WHEELS:
		_accum[name] = 0.0

	var forward := _vehicle.global_transform.basis.z.normalized()
	var current := _vehicle.linear_velocity.dot(forward)
	var left_speed := clampf(left_angle * PI / 180.0 / dt * 0.08, -0.6, 0.6)
	var right_speed := clampf(right_angle * PI / 180.0 / dt * 0.08, -0.6, 0.6)
	if absf(left_speed) < 0.02: left_speed = 0.0
	if absf(right_speed) < 0.02: right_speed = 0.0
	var left_force := clampf((left_speed - current) * _vehicle.mass * 10.0, -MAX_ENGINE_FORCE, MAX_ENGINE_FORCE)
	var right_force := clampf((right_speed - current) * _vehicle.mass * 10.0, -MAX_ENGINE_FORCE, MAX_ENGINE_FORCE)
	if _wheels.size() == 4:
		_wheels[0].engine_force = left_force
		_wheels[2].engine_force = left_force
		_wheels[1].engine_force = right_force
		_wheels[3].engine_force = right_force
		for wheel in _wheels:
			wheel.brake = 0.0

	_car.global_transform = _vehicle.global_transform * _visual_local
