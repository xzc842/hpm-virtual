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

var _wheel_names: Array[String] = []
const WHEEL_NODES := ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]
const MAX_ENGINE_FORCE := 4.0

var _car: Node3D
var _vehicle: VehicleBody3D
var _wheels: Array[VehicleWheel3D] = []
var _last: Dictionary = {}
var _accum: Dictionary = {}
var _sync_time := 0.0
var _visual_local := Transform3D.IDENTITY
var _left_force := 0.0
var _right_force := 0.0
var _target_left := 0.0
var _target_right := 0.0
var _step_hold := 0.0
var _primed := false

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
	_wheel_names = [
		String(get_config("wheel_fl", "")),
		String(get_config("wheel_fr", "")),
		String(get_config("wheel_rl", "")),
		String(get_config("wheel_rr", "")),
	]
	if _wheel_names.any(func(name: String) -> bool: return name.is_empty()):
		log_error("car-controller 缺少 wheel_fl/fr/rl/rr 设备名配置")
		return
	for name: String in _wheel_names:
		_last[name] = 0.0
		_accum[name] = 0.0
	log_info("车辆底盘已绑定")

func _on_session_start() -> void:
	if _vehicle != null:
		_vehicle.freeze = true
		_vehicle.sleeping = false
	_primed = false

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
	for name: String in _wheel_names:
		var script: VirtualDevice = scripts.get(name, null)
		if script == null or not script.has_method("get_angle"):
			return
		var angle := float(script.get_angle())
		if not _primed:
			_last[name] = angle
			_accum[name] = 0.0
			continue
		_accum[name] = float(_accum.get(name, 0.0)) + angle - float(_last.get(name, 0.0))
		_last[name] = angle
	if not _primed:
		_primed = true
		_sync_time = 0.0
		return
	_sync_time += delta
	if _sync_time < 0.05:
		return

	var dt := _sync_time
	_sync_time = 0.0
	var left_delta := float(_accum[_wheel_names[0]]) + float(_accum[_wheel_names[2]])
	var right_delta := float(_accum[_wheel_names[1]]) + float(_accum[_wheel_names[3]])
	var total := absf(left_delta) + absf(right_delta)
	for name: String in _wheel_names:
		_accum[name] = 0.0

	var target_left := 0.0
	var target_right := 0.0
	var braking := false
	if total >= 0.01:
		_step_hold = 0.25
		var left_sign := signf(left_delta)
		var right_sign := signf(right_delta)
		if left_sign != 0.0 and right_sign != 0.0 and left_sign != right_sign:
			# 左右反向：只做原地差速转向。
			target_left = MAX_ENGINE_FORCE * left_sign
			target_right = MAX_ENGINE_FORCE * right_sign
		else:
			# 同向直行：四轮使用同一个基础驱动力，避免逐轮相位差造成左右摆动。
			# STEP 只是方向指令；车辆目标速度固定，避免逐 STEP 速度噪声导致车身前后抽动。
			var target_speed := 0.5 * signf(left_delta + right_delta)
			var forward := _vehicle.global_transform.basis.z.normalized()
			var current := _vehicle.linear_velocity.dot(forward)
			var base := clampf((target_speed - current) * _vehicle.mass * 3.0,
				-MAX_ENGINE_FORCE, MAX_ENGINE_FORCE)
			target_left = base
			target_right = base
		_target_left = target_left
		_target_right = target_right
	else:
		# 保留上一次目标一小段时间，避免 STEP 脉冲间隙被误判为刹车。
		_step_hold = maxf(0.0, _step_hold - dt)
		if _step_hold > 0.0:
			target_left = _target_left
			target_right = _target_right
		else:
			braking = true

	if _vehicle.freeze:
		if braking:
			return
		_vehicle.freeze = false
		_vehicle.sleeping = false

	# 低通限速，避免 STEP 脉冲让 engine_force 瞬间跳变。
	var max_step := MAX_ENGINE_FORCE * 2.0 * dt
	_left_force = move_toward(_left_force, target_left, max_step)
	_right_force = move_toward(_right_force, target_right, max_step)
	if _wheels.size() == 4:
		_wheels[0].engine_force = _left_force
		_wheels[2].engine_force = _left_force
		_wheels[1].engine_force = _right_force
		_wheels[3].engine_force = _right_force
		for wheel in _wheels:
			wheel.brake = 2.0 if braking else 0.0

	_car.global_transform = _vehicle.global_transform * _visual_local
	_car.global_position.y = maxf(0.0, _car.global_position.y)
