# 无头冒烟测试：
#   Godot_v4.7 --headless --path . --script res://tests/smoke_test.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _init() -> void:
	_test_sse_parser()
	_test_project_context()
	_test_package_resolver()
	_test_model_and_physics()
	_test_external_script()
	_test_debug_url()

	print("SMOKE: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)

func _demo_dir() -> String:
	return ProjectSettings.globalize_path("res://examples/demo-project")

# ---------------------------------------------------------------- SSE

func _test_sse_parser() -> void:
	print("[SSE]")
	var parser := SseParser.new()
	var events: Array = []
	parser.event_received.connect(func(name: String, data: String, id: String) -> void:
		events.append({"name": name, "data": data, "id": id})
	)
	parser.feed("retry: 1000\nevent: snapshot\ndata: {\"type\":\"snapshot\"}\n\n".to_utf8_buffer())
	_check(events.size() == 1, "解析 snapshot 事件")
	_check(events[0]["name"] == "snapshot", "事件名")
	_check(events[0]["data"] == "{\"type\":\"snapshot\"}", "事件数据")
	_check(parser.retry_ms == 1000, "读取 retry")

	parser.feed("id: 18\ndata: {\"cursor\":18,".to_utf8_buffer())
	parser.feed(" \"type\":\"device\"}\n\n".to_utf8_buffer())
	_check(events.size() == 2, "分块到达的 data 能拼起来")
	_check(events[1]["id"] == "18", "读取事件 id")
	_check(events[1]["data"].contains("\"type\":\"device\""), "分块数据完整")

	parser.feed(": ping\n\n".to_utf8_buffer())
	_check(events.size() == 2, "忽略心跳注释")

	parser.feed("event: multi\ndata: a\ndata: b\n\n".to_utf8_buffer())
	_check(events.size() == 3 and events[2]["data"] == "a\nb", "多行 data")

	parser.feed("data: crlf\r\n\r\n".to_utf8_buffer())
	_check(events.size() == 4 and events[3]["data"] == "crlf", "CRLF 行尾")

# ---------------------------------------------------------------- 项目

func _test_project_context() -> void:
	print("[Project]")
	var context := ProjectContext.new()
	var result := context.open_project(_demo_dir())
	_check(bool(result.get("ok", false)), "打开 demo 项目")
	_check(not bool(result.get("needs_virtual", true)), "识别 virtual 目录")
	_check(context.virtual_json.get("devices", []).size() == 1, "读取 virtual.json 设备")
	_check(context.project_json.get("mcu", "") == "ch552g", "读取 project.json mcu")
	_check(context.virtual_scene_path().ends_with("virtual.glb"), "virtual 场景路径")
	context.free()

# ---------------------------------------------------------------- 包解析

func _test_package_resolver() -> void:
	print("[Packages]")
	var resolver := PackageResolver.new(_demo_dir())
	var pkg := resolver.find("led-demo", "1.0.0", "ch552g")
	_check(not pkg.is_empty(), "找到 led-demo 包")
	_check(pkg.get("manifest", {}).get("name", "") == "led-demo", "manifest name")

	var instance := {
		"name": "led",
		"node": "Devices/led",
		"package": "led-demo",
		"version": "1.0.0",
	}
	var resolved := resolver.resolve_device(instance, {"mcu": "ch552g"})
	_check(bool(resolved.get("ok", false)), "解析设备实例")
	_check(String(resolved.get("script_path", "")).ends_with("debug/virtual.gd"), "脚本路径")
	_check(FileAccess.file_exists(String(resolved.get("script_path", ""))), "脚本文件存在")
	_check(FileAccess.file_exists(String(resolved.get("model_path", ""))), "模型文件存在")

	var unknown := resolver.resolve_device({"name": "nope", "package": "missing"}, {"mcu": "ch552g"})
	_check(not bool(unknown.get("ok", true)), "缺失包返回失败")

# ---------------------------------------------------------------- 模型与摩擦

func _test_model_and_physics() -> void:
	print("[Model/Physics]")
	var path := _demo_dir().path_join("virtual/virtual.glb")
	var scene := ModelLoader.load_scene(path)
	_check(scene != null, "加载 virtual.glb")
	if scene == null:
		return
	_check(scene.get_node_or_null("Devices/led") != null, "找到 Devices/led 节点")
	_check(scene.get_node_or_null("Devices/led/Lamp") != null, "找到 Lamp 节点")

	var virtual_json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(_demo_dir().path_join("virtual/virtual.json"))
	)
	var company := PhysicsBuilder.apply(
		scene,
		virtual_json.get("physics", {}),
		virtual_json.get("objects", []),
		0.8,
		[scene.get_node("Devices/led")]
	)
	_check(company == 1, "环境只给地板生成碰撞体")
	var floor_body := scene.get_node_or_null("Environment/Floor/HPMPhysics_Floor") as StaticBody3D
	_check(floor_body != null, "地板碰撞体节点")
	if floor_body != null:
		_check(is_equal_approx(floor_body.physics_material_override.friction, 0.9), "地板摩擦 0.9")

	var device_json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(
			_demo_dir().path_join("packages/led-demo-1.0.0/debug/device.json")
		)
	)
	var device_root := scene.get_node("Devices/led")
	var device_count := PhysicsBuilder.apply(
		device_root,
		device_json.get("physics", {}),
		device_json.get("objects", []),
		0.8
	)
	_check(device_count == 3, "设备 3 个网格各一个碰撞体")

	var body := device_root.get_node_or_null("Body/HPMPhysics_Body") as StaticBody3D
	var lamp := device_root.get_node_or_null("Lamp/HPMPhysics_Lamp") as StaticBody3D
	var base := device_root.get_node_or_null("Base/HPMPhysics_Base") as StaticBody3D
	if body != null:
		_check(is_equal_approx(body.physics_material_override.friction, 0.6), "Body 摩擦 0.6")
	if lamp != null:
		_check(is_equal_approx(lamp.physics_material_override.friction, 0.3), "Lamp 摩擦 0.3")
		_check(is_equal_approx(lamp.physics_material_override.bounce, 0.2), "Lamp 弹性 0.2")
	if base != null:
		_check(is_equal_approx(base.physics_material_override.friction, 0.6), "Base 用设备默认摩擦")

	scene.free()

# ---------------------------------------------------------------- 外部脚本

func _test_external_script() -> void:
	print("[Script]")
	var resolver := PackageResolver.new(_demo_dir())
	var resolved := resolver.resolve_device(
		{"name": "led", "package": "led-demo", "version": "1.0.0"}, {"mcu": "ch552g"}
	)
	var cached := ScriptHost.cache_script(
		String(resolved.get("package_path", "")), String(resolved.get("script_path", ""))
	)
	_check(cached.begins_with("user://"), "脚本复制到 user:// 缓存")
	_check(FileAccess.file_exists(cached), "缓存脚本存在")

	var script := ScriptHost.load_script(cached)
	_check(script != null, "加载 GDScript")
	if script == null:
		return
	var instance = script.new()
	_check(instance is VirtualDevice, "脚本继承 VirtualDevice")
	if not instance is VirtualDevice:
		return
	var model := Node3D.new()
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var sphere := SphereMesh.new()
	lamp.mesh = sphere
	model.add_child(lamp)
	instance.model = model
	instance._host_bind(null, {"name": "led", "title": "演示 LED", "package": "led-demo"})

	instance._host_values({"power": true})
	var material := lamp.material_override as StandardMaterial3D
	_check(material != null, "power=true 时设置了材质")
	if material != null:
		_check(material.emission_energy_multiplier > 0.0, "LED 发光")
	var glow := model.get_node_or_null("Glow") as OmniLight3D
	_check(glow != null and glow.light_energy > 0.0, "点光源亮起")

	instance._host_values({"power": false})
	if material != null:
		_check(lamp.material_override.emission_energy_multiplier <= 0.0, "power=false 时熄灭")

	instance._host_unbind()
	instance.free()
	model.free()

# ---------------------------------------------------------------- 调试服务地址

func _test_debug_url() -> void:
	print("[Debug URL]")
	var bridge = load("res://core/debug_service.gd").new()
	bridge.set_service_url("http://127.0.0.1:19999")
	_check(bridge.get_base_url() == "http://127.0.0.1:19999", "解析服务地址")
	bridge.set_service_url("http://localhost:17321/")
	_check(bridge.get_base_url() == "http://localhost:17321", "去掉尾部斜杠")
	bridge.free()
