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
	body.physics_material_override = make_material(physics, 0.8)
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
