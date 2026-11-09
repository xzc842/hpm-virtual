# 按物体生成静态碰撞与摩擦。
#
# 每个 MeshInstance3D 得到一个 StaticBody3D 子节点，摩擦来自：
#   1) overrides 中匹配该节点（或它的祖先）的 physics；
#   2) default_physics；
#   3) default_friction 兜底。
# 设备模型用 device.json 的 physics/objects，场景用 virtual.json 的同名字段。
class_name PhysicsBuilder
extends RefCounted

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
			push_warning("physics override 找不到节点：%s" % entry.get("node", ""))
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
	mesh.add_child(body)
	mesh.set_meta("hpm_physics_built", true)
	return true

static func make_material(physics: Dictionary, default_friction: float = 0.8) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = clampf(float(physics.get("friction", default_friction)), 0.0, 1.0)
	material.rough = bool(physics.get("rough", true))
	material.bounce = clampf(float(physics.get("bounce", 0.0)), 0.0, 1.0)
	material.absorbent = bool(physics.get("absorbent", false))
	return material
