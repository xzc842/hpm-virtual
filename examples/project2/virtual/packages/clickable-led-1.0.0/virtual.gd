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