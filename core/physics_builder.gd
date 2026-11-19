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

# 按物体生成静态碰撞、摩擦与质量元数据。
#
# 每个 MeshInstance3D 得到一个 StaticBody3D 子节点，摩擦来自：
#   1) overrides 中匹配该节点（或它的祖先）的 physics；
#   2) default_physics；
#   3) default_friction 兜底。
# 静态碰撞体没有真实质量，质量写入 body 的 hpm_mass 元数据，
# 供脚本、HUD 和导出使用。
# 设备模型用 device.json 的 physics/objects，场景用 virtual.json 的同名字段。
class_name PhysicsBuilder
extends RefCounted

## 合并设备包默认值与 virtual.json 的实例覆盖；实例规则优先。
static func merge_overrides(base: Dictionary, instance: Dictionary) -> Dictionary:
	var physics: Dictionary = base.get("physics", {}).duplicate(true)
	var instance_physics: Variant = instance.get("physics", {})
	if typeof(instance_physics) == TYPE_DICTIONARY:
		for key: Variant in instance_physics:
			physics[key] = instance_physics[key]

	var objects: Array = []
	var instance_objects: Variant = instance.get("objects", [])
	if typeof(instance_objects) == TYPE_ARRAY:
		objects.append_array(instance_objects)
	objects.append_array(base.get("objects", []))
	return {"physics": physics, "objects": objects}

static func apply(
	root: Node,
	default_physics: Dictionary = {},
	overrides: Array = [],
	default_friction: float = 0.8,
	skip: Array = []
) -> int:
	if root == null:
		return 0
	var rules: Array = []
	for item: Variant in overrides:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var target := find_node(root, String(entry.get("node", "")))
		if target == null:
			print_verbose("physics override 跳过不存在的节点：%s" % entry.get("node", ""))
			continue
		var physics: Variant = entry.get("physics", {})
		if typeof(physics) == TYPE_DICTIONARY:
			rules.append({"node": target, "physics": physics})
	return _walk(root, root, default_physics, rules, default_friction, skip)

static func find_node(root: Node, path: String) -> Node:
	if path.is_empty():
		return root
	var node := root.get_node_or_null(path)
	if node != null:
		return node
	if not path.contains("/"):
		return root.find_child(path, true, false)
	return null

static func _walk(
	node: Node,
	root: Node,
	default_physics: Dictionary,
	rules: Array,
	default_friction: float,
	skip: Array
) -> int:
	if skip.has(node):
		return 0
	var count := 0
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and not mesh.has_meta("hpm_physics_built"):
			var physics := _pick_physics(mesh, root, rules)
			if physics.is_empty():
				physics = default_physics
			if physics.is_empty():
				physics = {"friction": default_friction}
			if not bool(physics.get("enabled", true)):
				pass
			elif _build_body(mesh, physics, default_friction):
				count += 1
	for child in node.get_children():
		count += _walk(child, root, default_physics, rules, default_friction, skip)
	return count

static func _pick_physics(mesh: MeshInstance3D, root: Node, rules: Array) -> Dictionary:
	var node: Node = mesh
	while node != null:
		for rule: Dictionary in rules:
			var target: Node = rule["node"]
			if target == node:
				return rule["physics"]
		if node == root:
			break
		node = node.get_parent()
	return {}

static func _build_body(mesh: MeshInstance3D, physics: Dictionary, default_friction: float) -> bool:
	var shape_resource := mesh.mesh.create_trimesh_shape()
	if shape_resource == null:
		return false
	var body := StaticBody3D.new()
	body.name = "HPMPhysics_" + mesh.name.validate_node_name()
	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = shape_resource
	body.add_child(collision)
	body.physics_material_override = make_material(physics, default_friction)
	body.set_meta("hpm_mass", clampf(float(physics.get("mass", 1.0)), 0.001, 100000.0))
	body.set_meta("hpm_physics", physics.duplicate(true))
	mesh.add_child(body)
	mesh.set_meta("hpm_physics_built", true)
	return true


## 车辆底盘：VehicleBody3D + 四个 VehicleWheel3D，轮子由轮胎摩擦驱动。
static func build_vehicle(root: Node3D, physics: Dictionary) -> VehicleBody3D:
	if root == null:
		return null
	var body_box := AABB()
	var full_box := AABB()
	var first := true
	var full_first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		if full_first:
			full_box = box
			full_first = false
		else:
			full_box = full_box.merge(box)
		var parent := mesh.get_parent()
		var is_wheel := parent != null and String(parent.name).begins_with("stepper_")
		var is_sensor := String(mesh.name).begins_with("Body2") or parent != null and String(parent.name) == "sonar"
		if is_wheel or is_sensor:
			continue
		if first:
			body_box = box
			first = false
		else:
			body_box = body_box.merge(box)
	if not body_box.has_volume():
		return null
	var body := VehicleBody3D.new()
	body.name = "HPMVehicle"
	body.mass = clampf(float(physics.get("mass", 1.0)), 0.001, 100000.0)
	body.physics_material_override = make_material(physics, 0.8)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0.0, -0.08, 0.0)
	body.continuous_cd = true
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_meta("hpm_mass", body.mass)
	root.add_child(body)
	body.top_level = true
	body.global_position = body_box.get_center()
	var collision := CollisionShape3D.new()
	collision.name = "ChassisShape"
	var shape := BoxShape3D.new()
	# 底盘碰撞盒缩到车轮内侧，避免挡住 VehicleWheel 向下射线。
	shape.size = Vector3(body_box.size.x * 0.82, body_box.size.y, body_box.size.z * 0.82)
	collision.shape = shape
	body.add_child(collision)
	var wheels: Array = physics.get("wheels", [])
	for i in range(wheels.size()):
		var spec: Dictionary = wheels[i]
		var wheel := VehicleWheel3D.new()
		wheel.name = "Wheel" + String(spec.get("name", str(i)))
		wheel.position = Vector3(float(spec.get("x", 0.0)), float(spec.get("y", -0.05)), float(spec.get("z", 0.0)))
		wheel.wheel_radius = float(physics.get("wheel_radius", 0.08))
		wheel.wheel_rest_length = 0.015
		wheel.suspension_travel = 0.06
		wheel.suspension_stiffness = 60.0
		wheel.suspension_max_force = 200.0
		wheel.damping_compression = 4.0
		wheel.damping_relaxation = 4.0
		wheel.wheel_friction_slip = 2.0
		wheel.use_as_traction = true
		wheel.use_as_steering = false
		body.add_child(wheel)
	return body

## 为小车底盘创建单个 RigidBody3D；每个网格生成碰撞盒（轮子自身接地，底盘盒不贴地）。
static func build_rigid(root: Node3D, physics: Dictionary) -> RigidBody3D:
	if root == null:
		return null
	var meshes: Array[MeshInstance3D] = []
	var boxes: Array[AABB] = []
	var total := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var mesh_box := mesh.global_transform * mesh.get_aabb()
		meshes.append(mesh)
		boxes.append(mesh_box)
		if first:
			total = mesh_box
			first = false
		else:
			total = total.merge(mesh_box)
	if not total.has_volume():
		return null
	var body := RigidBody3D.new()
	body.name = "HPMRigidBody"
	body.mass = clampf(float(physics.get("mass", 1.0)), 0.001, 100000.0)
	var car_material := make_material(physics, 0.8)
	# 轮胎牵引力由 car-controller 计算；避免接触摩擦重复抵消牵引力。
	car_material.friction = 0.0
	body.physics_material_override = car_material
	body.continuous_cd = true
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_meta("hpm_mass", body.mass)
	body.set_meta("hpm_physics", physics.duplicate(true))
	root.add_child(body)
	body.top_level = true
	body.global_position = total.get_center()
	for i in range(meshes.size()):
		var mesh_box := boxes[i]
		var collision := CollisionShape3D.new()
		collision.name = "Shape_" + String(meshes[i].name).validate_node_name()
		var shape := BoxShape3D.new()
		shape.size = mesh_box.size
		collision.shape = shape
		collision.position = mesh_box.get_center() - body.global_position
		body.add_child(collision)
	return body

static func get_mass(body: StaticBody3D) -> float:
	if body == null:
		return 0.0
	return float(body.get_meta("hpm_mass", 1.0))


static func make_material(physics: Dictionary, default_friction: float = 0.8) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = clampf(float(physics.get("friction", default_friction)), 0.0, 1.0)
	material.rough = bool(physics.get("rough", true))
	material.bounce = clampf(float(physics.get("bounce", 0.0)), 0.0, 1.0)
	material.absorbent = bool(physics.get("absorbent", false))
	return material
