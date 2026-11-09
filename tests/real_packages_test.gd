# 真实设备包（gpio / pwm）测试。
#   godot --headless --path . --script res://tests/real_packages_test.gd
#
# 依赖已安装的 ~/.hpm/packages/gpio-* 和 pwm-stc90c51-* 以及
# examples/real-project/virtual/virtual.glb。包不存在时跳过（退出码 0）。
extends SceneTree

var _failures := 0
var _checks := 0

func _init() -> void:
	var resolver := PackageResolver.new("")
	var gpio_pkg := resolver.find("gpio", "", "stc90c51")
	var pwm_pkg := resolver.find("pwm-stc90c51", "", "stc90c51")
	if gpio_pkg.is_empty() or pwm_pkg.is_empty():
		print("SKIP: 未安装 gpio / pwm 设备包")
		quit(0)
		return

	print("[Packages] ", gpio_pkg.get("dir_name", ""), " / ", pwm_pkg.get("dir_name", ""))
	var project := {"mcu": "stc90c51"}
	var led_instance := {
		"name": "led", "node": "Devices/led", "package": "gpio", "version": "1.0.0",
		"props": {"color": "green"},
	}
	var servo_instance := {
		"name": "servo", "node": "Devices/servo", "package": "pwm-stc90c51",
		"version": "1.0.0", "props": {"speed_deg_per_s": 240},
	}
	var led_resolved := resolver.resolve_device(led_instance, project)
	var servo_resolved := resolver.resolve_device(servo_instance, project)
	_check(bool(led_resolved.get("ok", false)), "解析 gpio 包")
	_check(bool(servo_resolved.get("ok", false)), "解析 pwm 包")
	if not bool(led_resolved.get("ok", false)) or not bool(servo_resolved.get("ok", false)):
		_finish()
		return

	var scene := ModelLoader.load_scene(
		ProjectSettings.globalize_path("res://examples/real-project/virtual/virtual.glb")
	)
	_check(scene != null, "加载 real-project/virtual.glb")
	if scene == null:
		_finish()
		return
	var led_node := scene.get_node_or_null("Devices/led") as Node3D
	var servo_node := scene.get_node_or_null("Devices/servo") as Node3D
	_check(led_node != null and led_node.get_node_or_null("LedBody") != null, "LED 节点 LedBody")
	_check(servo_node != null and servo_node.get_node_or_null("ServoHorn") != null, "舵机节点 ServoHorn")

	# 按物体摩擦：LED 与舵机的 device.json objects.
	var led_json: Dictionary = led_resolved.get("device_json", {})
	var servo_json: Dictionary = servo_resolved.get("device_json", {})
	var bodies := 0
	bodies += PhysicsBuilder.apply(led_node, led_json.get("physics", {}), led_json.get("objects", []), 0.8)
	bodies += PhysicsBuilder.apply(servo_node, servo_json.get("physics", {}), servo_json.get("objects", []), 0.8)
	_check(bodies == 13, "13 个网格生成碰撞体（LED 5 + 舵机 8）")

	# ServoHorn 是 Node3D，碰撞体挂在它的子网格下。
	var hub := servo_node.get_node_or_null("ServoHorn/ServoHub") as MeshInstance3D
	var horn_body := hub.get_node_or_null("HPMPhysics_ServoHub") as StaticBody3D if hub != null else null
	if horn_body != null:
		_check(is_equal_approx(horn_body.physics_material_override.friction, 0.35), "舵机摆臂摩擦 0.35")

	# LED 脚本
	var led_script := _instantiate(led_resolved)
	_check(led_script != null, "加载 LED 脚本")
	if led_script != null:
		led_script.model = led_node
		led_script._host_bind(null, {
			"name": "led", "title": "LED", "package": "gpio", "version": "1.0.0",
			"props": led_instance["props"], "model": led_node,
		})
		led_script._host_session_start()
		led_script._host_values({"power": true})
		var barrel := led_node.get_node_or_null("LedBody/LedBarrel") as MeshInstance3D
		_check(barrel != null and barrel.material_override != null, "LED 灯珠材质")
		if barrel != null and barrel.material_override != null:
			_check(barrel.material_override.emission_energy_multiplier > 0.0, "LED 点亮")
			_check(barrel.material_override.albedo_color.g > barrel.material_override.albedo_color.r, "使用绿色")

	# 舵机脚本
	var servo_script := _instantiate(servo_resolved)
	_check(servo_script != null, "加载舵机脚本")
	if servo_script != null:
		servo_script.model = servo_node
		servo_script._host_bind(null, {
			"name": "servo", "title": "舵机", "package": "pwm-stc90c51",
			"version": "1.0.0", "props": servo_instance["props"], "model": servo_node,
		})
		servo_script._host_session_start()
		servo_script._host_values({"angle": 150.0, "duty_pct": 9.17})
		servo_script._on_tick(1.0)
		var horn := servo_node.get_node("ServoHorn") as Node3D
		_check(is_equal_approx(horn.rotation_degrees.y, 60.0), "舵机 150° -> 摆臂 +60°")
		servo_script._host_values({"duty_pct": 5.0})
		servo_script._on_tick(2.0)
		_check(is_equal_approx(horn.rotation_degrees.y, -90.0), "占空比 5% -> 摆臂 -90°")

	if led_script != null:
		led_script._host_unbind()
		led_script.free()
	if servo_script != null:
		servo_script._host_unbind()
		servo_script.free()
	scene.free()

	# 实例级覆盖（Blender 导出的 devices[].objects 形态）
	var scene2 := ModelLoader.load_scene(
		ProjectSettings.globalize_path("res://examples/real-project/virtual/virtual.glb")
	)
	var servo2 := scene2.get_node("Devices/servo")
	var merged := PhysicsBuilder.merge_overrides(servo_json, {
		"physics": {"friction": 0.2},
		"objects": [{"node": "ServoHorn/ServoHub", "physics": {"friction": 0.42, "bounce": 0.3}}],
	})
	_check(is_equal_approx(float(merged["physics"].get("friction", 0.0)), 0.2), "实例 physics 覆盖")
	_check(merged["objects"][0]["node"] == "ServoHorn/ServoHub", "实例 objects 优先")
	PhysicsBuilder.apply(servo2, merged["physics"], merged["objects"], 0.8)
	var hub2 := servo2.get_node_or_null("ServoHorn/ServoHub/HPMPhysics_ServoHub") as StaticBody3D
	if hub2 != null:
		_check(is_equal_approx(hub2.physics_material_override.friction, 0.42), "实例物体摩擦写入")
		_check(is_equal_approx(hub2.physics_material_override.bounce, 0.3), "实例物体弹性写入")
	scene2.free()
	_finish()

func _instantiate(resolved: Dictionary) -> VirtualDevice:
	var cached := ScriptHost.cache_script(
		String(resolved.get("package_path", "")), String(resolved.get("script_path", ""))
	)
	var script := ScriptHost.load_script(cached)
	if script == null:
		return null
	var instance = script.new()
	return instance as VirtualDevice

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)

func _finish() -> void:
	print("REAL PACKAGES: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
