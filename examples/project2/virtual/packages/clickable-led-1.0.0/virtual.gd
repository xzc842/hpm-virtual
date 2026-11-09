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

# 可点击 LED：在普通 LED 的基础上，点击切换红/蓝颜色。
extends "res://sdk/virtual_device.gd"

const COLORS := [Color(0.9, 0.08, 0.08), Color(0.12, 0.35, 1.0)]

var _emissive: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _color_index := 0
var _power := false

func _on_bind(_ctx: Dictionary) -> void:
	var body := get_model_node("Body")
	if body == null:
		body = model
	_collect_meshes(body, _emissive)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.omni_range = 1.4
	_light.light_energy = 0.0
	if model != null:
		_light.position = Vector3(0.0, 0.15, 0.0)
		model.add_child(_light)

	register_interaction("color", _toggle_color, "点击切换颜色")
	_apply(false)
	log_info("可点击 LED 已绑定")

func _on_values(values: Dictionary) -> void:
	_apply(bool(values.get("power", false)))

func _on_session_stop() -> void:
	_apply(false)

func _toggle_color() -> void:
	_color_index = (_color_index + 1) % COLORS.size()
	_apply(_power)
	log_info("点击切换颜色：%s" % ("红" if _color_index == 0 else "蓝"))

func _apply(on: bool) -> void:
	_power = on
	var color: Color = COLORS[_color_index]
	for mesh: MeshInstance3D in _emissive:
		var material := StandardMaterial3D.new()
		material.albedo_color = color.darkened(0.65) if not on else color
		material.roughness = 0.25
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.2 if on else 0.0
		mesh.material_override = material
	if _light != null:
		_light.light_color = color
		_light.light_energy = 1.6 if on else 0.0

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)
