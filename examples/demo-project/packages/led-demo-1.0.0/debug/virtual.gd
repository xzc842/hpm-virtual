# 演示设备：根据输出通道 power 控制 LED 的发光和点光源。
extends "res://sdk/virtual_device.gd"

var _lamp: MeshInstance3D
var _light: OmniLight3D
var _on := false
var _flash := 0.0

func _on_bind(_ctx: Dictionary) -> void:
	_lamp = get_model_node("Lamp") as MeshInstance3D
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = Color(0.3, 1.0, 0.4)
	_light.omni_range = 0.9
	_light.light_energy = 0.0
	if model != null:
		model.add_child(_light)
	_apply(false)
	register_interaction("flash", _on_flash, "点击闪烁")
	log_info("LED 已绑定")

func _on_session_start() -> void:
	log_info("调试会话开始")

func _on_flash() -> void:
	_flash = 0.8
	log_info("交互：闪烁")

func _on_values(new_values: Dictionary) -> void:
	_apply(bool(new_values.get("power", false)))

func _on_session_stop() -> void:
	_apply(false)

func _on_tick(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta, 0.0)
	if _light != null:
		_light.light_energy = 2.4 if _flash > 0.0 else (1.6 if _on else 0.0)

func _apply(on: bool) -> void:
	_on = on
	log_info("LED %s" % ("亮" if on else "灭"))
	if _lamp != null:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.08, 0.25, 0.12) if on else Color(0.12, 0.13, 0.15)
		material.emission_enabled = true
		material.emission = Color(0.25, 1.0, 0.35)
		material.emission_energy_multiplier = 1.6 if on else 0.0
		_lamp.material_override = material
	if _light != null:
		_light.light_energy = 1.2 if on else 0.0
