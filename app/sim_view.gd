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

# 仿真视图：加载 virtual.glb、按物体生成摩擦、绑定设备脚本、分发调试输出。
class_name SimView
extends Node3D

signal binding_report(report: Dictionary)
signal interaction_hover_changed(device_name: String, hint: String)
signal interaction_triggered(device_name: String)
signal tool_changed(tool: String)
signal ruler_count_changed(count: int)

const DeviceConfigScript := preload("res://core/device_config.gd")

const DEVICE_DEFAULT_FRICTION := 0.8
const ENV_DEFAULT_FRICTION := 0.8
const CAMERA_MOVE_SPEED := 2.5
const CAMERA_ROTATE_SPEED := 90.0

var project_dir := ""
var current_tool := "select"

var _resolver: PackageResolver
var _scene_root: Node3D
var _device_scripts: Dictionary = {}
var _device_nodes: Dictionary = {}
var _report: Dictionary = {
	"scene_loaded": false,
	"placeholder": false,
	"bound": [],
	"overrides": [],
	"errors": [],
	"missing_nodes": [],
	"physics_bodies": 0,
}
var _camera: Camera3D
var _bridge_connected := false

var _ruler_tool: RulerTool
var _node_to_device_name: Dictionary = {}
var _hovered_name := ""
var _hovered_root: Node3D
var _hovered_overlays: Dictionary = {}
var _highlight_material: StandardMaterial3D
var _camera_yaw := 0.0
var _camera_pitch := 0.0

func setup(info: Dictionary) -> void:
	project_dir = String(info.get("root", ""))
	_resolver = PackageResolver.new(project_dir)
	_build_environment()
	var virtual: Dictionary = info.get("virtual", {})
	var scene_path := String(info.get("virtual_dir", "")).path_join(String(virtual.get("scene", "virtual.glb")))
	if bool(info.get("has_virtual", false)) and FileAccess.file_exists(scene_path):
		_scene_root = ModelLoader.load_scene(scene_path)
		if _scene_root != null:
			_report["scene_loaded"] = true
	if _scene_root == null:
		_scene_root = _build_placeholder()
		_report["placeholder"] = true
	add_child(_scene_root)

	_ruler_tool = RulerTool.new()
	_ruler_tool.name = "RulerTool"
	add_child(_ruler_tool)
	_ruler_tool.setup(_camera)
	_ruler_tool.ruler_count_changed.connect(func(count: int) -> void:
		ruler_count_changed.emit(count)
	)

	_apply_environment_physics(virtual)
	_bind_devices(virtual)
	_frame_camera()
	_build_highlight_material()
	_connect_bridge()
	binding_report.emit(_report)
	_sync_session_state()
	set_tool("select")

func get_report() -> Dictionary:
	return _report

func get_device_scripts() -> Dictionary:
	return _device_scripts

# ---------------------------------------------------------------- 场景与环境

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.86)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

	_camera = Camera3D.new()
	_camera.position = Vector3(2.4, 2.0, 2.4)
	_camera.current = true
	add_child(_camera)

func _build_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "PlaceholderWorld"
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 0.2, 6.0)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0.0, -0.1, 0.0)
	floor_mesh.material_override = ModelLoader.make_material(Color(0.22, 0.24, 0.28))
	root.add_child(floor_mesh)
	return root

func _apply_environment_physics(virtual: Dictionary) -> void:
	var default_physics: Dictionary = virtual.get("physics", {})
	var overrides: Array = virtual.get("objects", [])
	var device_nodes: Array = []
	for instance: Variant in virtual.get("devices", []):
		if typeof(instance) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = instance
		var node := _find_device_node(String(entry.get("node", "")), String(entry.get("name", "")))
		if node != null:
			device_nodes.append(node)
	_report["physics_bodies"] += PhysicsBuilder.apply(
		_scene_root, default_physics, overrides, ENV_DEFAULT_FRICTION, device_nodes
	)

# ---------------------------------------------------------------- 设备绑定

func _bind_devices(virtual: Dictionary) -> void:
	var instances: Array = virtual.get("devices", [])
	if instances.is_empty():
		# 没有 virtual.json 时，按 project.json 的设备名自动找同名节点。
		var project_devices: Dictionary = App.project_json.get("devices", {})
		for device_name: String in project_devices:
			instances.append({"name": device_name, "node": device_name})
			if project_devices[device_name] is Dictionary:
				_report["errors"].append("设备 %s 未在 virtual.json 登记，使用同名节点兜底" % device_name)

	for instance: Variant in instances:
		if typeof(instance) != TYPE_DICTIONARY:
			continue
		_bind_device(instance)

func _bind_device(instance: Dictionary) -> void:
	var device_name := String(instance.get("name", ""))
	var node := _find_device_node(String(instance.get("node", "")), device_name)
	if node == null:
		_report["missing_nodes"].append(device_name)
		_report["errors"].append("virtual.glb 中找不到设备 %s 的节点：%s" % [
			device_name, instance.get("node", device_name)
		])
		return

	var resolved := _resolver.resolve_device(instance, App.project_json)
	if not bool(resolved.get("ok", false)):
		_report["errors"].append("设备 %s：%s" % [device_name, resolved.get("error", "包解析失败")])
		PhysicsBuilder.apply(node, {"friction": DEVICE_DEFAULT_FRICTION}, [], DEVICE_DEFAULT_FRICTION)
		return

	var device_json: Dictionary = resolved.get("device_json", {})
	var merged := _merge_physics(device_json, instance)
	if bool(merged.get("physics", {}).get("vehicle", false)):
		PhysicsBuilder.build_vehicle(node, merged["physics"])
	elif bool(merged.get("physics", {}).get("rigid", false)):
		PhysicsBuilder.build_rigid(node, merged["physics"])
	elif bool(merged.get("physics", {}).get("enabled", true)):
		_report["physics_bodies"] += PhysicsBuilder.apply(
			node, merged["physics"], merged["objects"], DEVICE_DEFAULT_FRICTION
		)
	if not String(resolved.get("override_error", "")).is_empty():
		_report["errors"].append("设备 %s：%s" % [device_name, resolved.get("override_error")])
	elif not (resolved.get("override", {}) as Dictionary).is_empty():
		_report["overrides"].append(device_name)

	_device_nodes[device_name] = node
	_node_to_device_name[node] = device_name

	var script_path := String(resolved.get("script_path", ""))
	if not FileAccess.file_exists(script_path):
		_report["errors"].append("设备 %s 缺少外部脚本：%s" % [device_name, script_path])
		return
	var cached := ScriptHost.cache_script(String(resolved.get("package_path", "")), script_path)
	var gd := ScriptHost.load_script(cached)
	if gd == null:
		_report["errors"].append("设备 %s 脚本加载失败：%s" % [device_name, script_path])
		return

	var instance_node: Node = gd.new()
	if not instance_node is VirtualDevice:
		_report["errors"].append("设备 %s 的脚本没有继承 res://sdk/virtual_device.gd" % device_name)
		return
	instance_node.name = "HPMVirtualScript"
	node.add_child(instance_node)

	var title := String(device_json.get("display_name", device_name))
	var project_device: Dictionary = App.project_json.get("devices", {}).get(device_name, {})
	var config := DeviceConfigScript.resolve(
		device_json, resolved.get("manifest", {}), project_device, instance
	)
	var ctx := {
		"name": device_name,
		"title": title,
		"package": String(resolved.get("package", "")),
		"version": String(resolved.get("version", "")),
		"node_path": String(instance.get("node", "")),
		"props": instance.get("props", {}),
		"config": config,
		"device": project_device,
		"model": node,
		"scene_root": _scene_root,
		"sim": self,
	}
	(instance_node as VirtualDevice)._host_bind(Bridge, ctx)
	_device_scripts[device_name] = instance_node
	_report["bound"].append(device_name)

## 实例级 physics/objects 覆盖 device.json 的默认值；实例规则优先。
func _merge_physics(device_json: Dictionary, instance: Dictionary) -> Dictionary:
	return PhysicsBuilder.merge_overrides(device_json, instance)

func _find_device_node(path: String, device_name: String) -> Node3D:
	var node: Node = null
	if not path.is_empty():
		node = _scene_root.get_node_or_null(path)
	if node == null and not device_name.is_empty():
		node = _scene_root.find_child(device_name, true, false)
	return node as Node3D

# ---------------------------------------------------------------- 调试分发

func _connect_bridge() -> void:
	if _bridge_connected:
		return
	_bridge_connected = true
	Bridge.session_changed.connect(_on_session_changed)
	Bridge.device_values.connect(_on_device_values)
	Bridge.devices_changed.connect(_on_devices_changed)

func _sync_session_state() -> void:
	_on_session_changed(Bridge.is_active())

func _on_session_changed(active: bool) -> void:
	for script: VirtualDevice in _device_scripts.values():
		if active:
			script._host_session_start()
		else:
			script._host_session_stop()

func _on_device_values(device_name: String, values: Dictionary) -> void:
	var script: VirtualDevice = _device_scripts.get(device_name, null)
	if script != null:
		script._host_values(values)

func _on_devices_changed(devices: Array) -> void:
	# 用调试服务的 title 补全显示名。
	for item: Variant in devices:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var name := String(entry.get("name", entry.get("device", "")))
		var script: VirtualDevice = _device_scripts.get(name, null)
		if script != null and entry.has("title"):
			script.device_title = String(entry.get("title"))

# ---------------------------------------------------------------- 相机

func _frame_camera() -> void:
	var box := AABB()
	var first := true
	if not _device_nodes.is_empty():
		for node: Node3D in _device_nodes.values():
			var device_box := _compute_aabb(node)
			if not device_box.has_volume():
				continue
			if first:
				box = device_box
				first = false
			else:
				box = box.merge(device_box)
	if _scene_root != null:
		var focus := _scene_root.find_child("Target", true, false) as Node3D
		if focus != null:
			var focus_box := _compute_aabb(focus)
			if focus_box.has_volume():
				if first:
					box = focus_box
					first = false
				else:
					box = box.merge(focus_box)
	if first:
		box = _compute_aabb(_scene_root)
	if not box.has_volume():
		return
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.22)
	var direction := Vector3(0.85, 1.0, 0.85).normalized()
	_camera.global_position = center + direction * radius * 4.0
	var target_direction := (center - _camera.global_position).normalized()
	_camera_yaw = rad_to_deg(atan2(-target_direction.x, -target_direction.z))
	_camera_pitch = rad_to_deg(asin(clampf(target_direction.y, -1.0, 1.0)))
	_camera.rotation_degrees = Vector3(_camera_pitch, _camera_yaw, 0.0)

func _compute_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			box = mesh_box
			first = false
		else:
			box = box.merge(mesh_box)
	return box

# ---------------------------------------------------------------- 工具 / 相机 / 交互

func set_tool(tool: String) -> void:
	current_tool = tool
	if _ruler_tool != null:
		_ruler_tool.set_active(tool == "ruler")
	if tool != "select":
		_clear_hover()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	tool_changed.emit(tool)

func add_ruler(from_point: Vector3, to_point: Vector3, label_text: String = "") -> int:
	if _ruler_tool == null:
		return -1
	return _ruler_tool.add_ruler(from_point, to_point, label_text)

func update_ruler(id: int, from_point: Vector3, to_point: Vector3,
		label_text: String = "") -> bool:
	if _ruler_tool == null:
		return false
	return _ruler_tool.update_ruler(id, from_point, to_point, label_text)


func clear_rulers() -> void:
	if _ruler_tool != null:
		_ruler_tool.clear_rulers()

func remove_ruler(id: int) -> void:
	if _ruler_tool != null:
		_ruler_tool.remove_ruler(id)

func get_ruler_count() -> int:
	return _ruler_tool.get_ruler_count() if _ruler_tool != null else 0

func _process(delta: float) -> void:
	_update_camera(delta)
	if current_tool == "select":
		_update_hover()

func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	var rotate := 0.0
	if Input.is_key_pressed(KEY_LEFT):
		rotate += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		rotate -= 1.0
	_camera_yaw += rotate * CAMERA_ROTATE_SPEED * delta

	var pitch := 0.0
	if Input.is_key_pressed(KEY_UP):
		pitch += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pitch -= 1.0
	_camera_pitch = clampf(_camera_pitch + pitch * CAMERA_ROTATE_SPEED * delta, -85.0, 85.0)
	_camera.rotation_degrees = Vector3(_camera_pitch, _camera_yaw, 0.0)

	var move := Vector3.ZERO
	var basis := Basis(Vector3.UP, deg_to_rad(_camera_yaw))
	var forward := -basis.z
	var right := basis.x
	if Input.is_key_pressed(KEY_W):
		move += forward
	if Input.is_key_pressed(KEY_S):
		move -= forward
	if Input.is_key_pressed(KEY_D):
		move += right
	if Input.is_key_pressed(KEY_A):
		move -= right
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move.length_squared() > 0.0:
		_camera.position += move.normalized() * CAMERA_MOVE_SPEED * delta

func _unhandled_input(event: InputEvent) -> void:
	if _ruler_tool != null and current_tool == "ruler":
		if _mouse_over_ui():
			return
		if _ruler_tool.handle_input(event):
			get_viewport().set_input_as_handled()
		return

	if current_tool != "select":
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			if _mouse_over_ui():
				return
			_update_hover()
			if _hovered_name.is_empty():
				return
			var script: VirtualDevice = _device_scripts.get(_hovered_name, null)
			if script != null and script.trigger_interaction():
				interaction_triggered.emit(_hovered_name)
				get_viewport().set_input_as_handled()

func _mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _update_hover() -> void:
	if _camera == null or _mouse_over_ui():
		_clear_hover()
		return
	var hit := _raycast_mouse(get_viewport().get_mouse_position())
	if hit.is_empty():
		_clear_hover()
		return
	var device_name := _device_name_for_collider(hit.get("collider"))
	var script: VirtualDevice = _device_scripts.get(device_name, null)
	if script == null or not script.has_interaction():
		_clear_hover()
		return
	_set_hover(device_name, script.get_interaction_hint())

func _raycast_mouse(screen_position: Vector2) -> Dictionary:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 500.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _device_name_for_collider(collider: Object) -> String:
	var node := collider as Node
	while node != null:
		if _node_to_device_name.has(node):
			return String(_node_to_device_name[node])
		node = node.get_parent()
	return ""

func _set_hover(device_name: String, hint: String) -> void:
	if device_name == _hovered_name:
		return
	_clear_hover()
	if device_name.is_empty():
		return
	var root: Node3D = _device_nodes.get(device_name, null)
	if root == null:
		return
	_hovered_name = device_name
	_hovered_root = root
	_apply_highlight(root, true)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	interaction_hover_changed.emit(device_name, hint)

func _clear_hover() -> void:
	if _hovered_root != null:
		_apply_highlight(_hovered_root, false)
	var had_hover := not _hovered_name.is_empty()
	_hovered_name = ""
	_hovered_root = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if had_hover:
		interaction_hover_changed.emit("", "")

func _build_highlight_material() -> void:
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_material.albedo_color = Color(0.18, 0.65, 1.0, 0.32)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_highlight_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _apply_highlight(root: Node3D, enabled: bool) -> void:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.push_front(root)
	if enabled:
		for item in meshes:
			var mesh := item as MeshInstance3D
			_hovered_overlays[mesh] = mesh.material_overlay
			mesh.material_overlay = _highlight_material
	else:
		for mesh: MeshInstance3D in _hovered_overlays:
			if is_instance_valid(mesh):
				mesh.material_overlay = _hovered_overlays[mesh]
		_hovered_overlays.clear()

func _exit_tree() -> void:
	for script: VirtualDevice in _device_scripts.values():
		script._host_unbind()
