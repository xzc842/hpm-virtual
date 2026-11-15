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

extends Node

const WINDOW_TITLE := "HPM Virtual"

var _theme: Theme
var _ui: CanvasLayer
var _welcome: Control
var _hud: Control
var _welcome_status: Label
var _status_label: Label
var _project_label: Label
var _device_label: Label
var _debug_label: Label
var _hint_label: Label
var _recent_box: VBoxContainer
var _tool_buttons: Dictionary = {}
var _current_tool := "select"
var _hover_hint := ""
var _ruler_count := 0
var _updating_tool_ui := false
var _file_dialog: FileDialog
var _missing_dialog: ConfirmationDialog
var _settings_dialog: AcceptDialog
var _language_option: OptionButton
var _mouse_option: OptionButton
var _i18n_nodes: Array = []
var _sim: SimView

func _ready() -> void:
	get_window().title = WINDOW_TITLE
	_theme = _make_theme()
	_build_ui()
	I18n.language_changed.connect(_refresh_i18n)
	_connect_signals()
	_refresh_recent()
	_handle_command_line()

# ---------------------------------------------------------------- 启动参数

func _handle_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		var candidate := arg
		if candidate.begins_with("--project="):
			candidate = candidate.trim_prefix("--project=")
		elif candidate.begins_with("--"):
			continue
		if DirAccess.dir_exists_absolute(candidate):
			_open_project(candidate)
			return

# ---------------------------------------------------------------- 界面

func _make_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei",
		"Microsoft YaHei", "PingFang SC", "sans-serif",
	])
	theme.default_font = font
	theme.default_font_size = 16
	return theme

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	_ui.add_child(root)

	_build_welcome(root)
	_build_hud(root)
	_build_file_dialog()
	_build_missing_dialog()
	_build_settings_dialog()

func _bind_text(control: Control, key: String) -> void:
	_i18n_nodes.append([control, key])
	control.text = I18n.t(key)

func _refresh_i18n() -> void:
	for item in _i18n_nodes:
		var control: Control = item[0]
		control.text = I18n.t(String(item[1]))
	for tool: String in _tool_buttons:
		var button: Button = _tool_buttons[tool]
		button.text = I18n.t("tool." + tool)
		button.tooltip_text = I18n.t("tool.tip", [_tool_shortcut(tool)])
	_file_dialog.title = I18n.t("dialog.open.title")
	_missing_dialog.title = I18n.t("dialog.missing.title")
	_missing_dialog.dialog_text = I18n.t("dialog.missing.text")
	_missing_dialog.ok_button_text = I18n.t("dialog.missing.ok")
	_missing_dialog.cancel_button_text = I18n.t("dialog.missing.cancel")
	_missing_dialog.add_button(I18n.t("dialog.missing.blender"), true, "blender")
	_settings_dialog.title = I18n.t("settings.title")
	_settings_dialog.ok_button_text = I18n.t("settings.close")
	if App.is_open():
		_project_label.text = I18n.t("hud.project", [App.root_dir.get_file(), String(App.project_json.get("mcu", ""))])
	if _language_option != null:
		_language_option.set_item_text(0, "中文")
		_language_option.set_item_text(1, "English")
	if _mouse_option != null:
		_mouse_option.set_item_text(0, I18n.t("settings.mouse.left"))
		_mouse_option.set_item_text(1, I18n.t("settings.mouse.right"))
	_refresh_hint()

func _tool_shortcut(tool: String) -> String:
	return "V" if tool == "select" else "M"

func _build_welcome(root: Control) -> void:
	_welcome = Control.new()
	_welcome.name = "Welcome"
	_welcome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_welcome)

	var background := ColorRect.new()
	background.color = Color(0.045, 0.052, 0.075)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var logo := TextureRect.new()
	logo.texture = load("res://logo.png")
	logo.custom_minimum_size = Vector2(120, 120)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)

	var title := Label.new()
	title.text = "HPM Virtual"
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	var copyright := Label.new()
	copyright.text = "Copyright XueZicheng 2026 GNU General Public License v3.0 only"
	copyright.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	copyright.add_theme_font_size_override("font_size", 14)
	box.add_child(copyright)

	var subtitle := Label.new()
	_bind_text(subtitle, "welcome.subtitle")
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.72, 0.8))
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var open_button := Button.new()
	_bind_text(open_button, "welcome.open")
	open_button.custom_minimum_size = Vector2(0, 44)
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.pressed.connect(_show_open_dialog)
	actions.add_child(open_button)
	var settings_button := Button.new()
	_bind_text(settings_button, "welcome.settings")
	settings_button.custom_minimum_size = Vector2(100, 44)
	settings_button.pressed.connect(_show_settings)
	actions.add_child(settings_button)

	var recent_caption := Label.new()
	_bind_text(recent_caption, "welcome.recent")
	recent_caption.add_theme_color_override("font_color", Color(0.6, 0.66, 0.74))
	box.add_child(recent_caption)

	_recent_box = VBoxContainer.new()
	_recent_box.add_theme_constant_override("separation", 6)
	box.add_child(_recent_box)

	_welcome_status = Label.new()
	_welcome_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_welcome_status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.86))
	box.add_child(_welcome_status)

func _build_hud(root: Control) -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.visible = false
	root.add_child(_hud)

	var top_panel := PanelContainer.new()
	top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(top_panel)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 16)
	top_margin.add_theme_constant_override("margin_right", 16)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_bottom", 8)
	top_panel.add_child(top_margin)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	top_margin.add_child(top_bar)

	_project_label = Label.new()
	_bind_text(_project_label, "status.no_project")
	top_bar.add_child(_project_label)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.8, 0.9))
	top_bar.add_child(_status_label)

	var settings_button := Button.new()
	_bind_text(settings_button, "welcome.settings")
	settings_button.pressed.connect(_show_settings)
	top_bar.add_child(settings_button)

	var reset_button := Button.new()
	_bind_text(reset_button, "hud.reset")
	reset_button.tooltip_text = I18n.t("hud.reset.tip")
	reset_button.pressed.connect(_reset_sim)
	top_bar.add_child(reset_button)

	var back_button := Button.new()
	_bind_text(back_button, "hud.back")
	back_button.pressed.connect(_close_project)
	top_bar.add_child(back_button)

	_build_toolbar()
	_build_hint_panel()

	var device_panel := PanelContainer.new()
	device_panel.anchor_left = 0.0
	device_panel.anchor_top = 1.0
	device_panel.anchor_right = 0.0
	device_panel.anchor_bottom = 1.0
	device_panel.offset_left = 16.0
	device_panel.offset_top = -150.0
	device_panel.offset_right = 440.0
	device_panel.offset_bottom = -16.0
	device_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(device_panel)

	var device_margin := MarginContainer.new()
	device_margin.add_theme_constant_override("margin_left", 12)
	device_margin.add_theme_constant_override("margin_right", 12)
	device_margin.add_theme_constant_override("margin_top", 8)
	device_margin.add_theme_constant_override("margin_bottom", 8)
	device_panel.add_child(device_margin)

	var device_box := VBoxContainer.new()
	device_box.add_theme_constant_override("separation", 6)
	device_margin.add_child(device_box)

	_device_label = Label.new()
	_device_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_device_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.92))
	device_box.add_child(_device_label)

	_debug_label = Label.new()
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label.add_theme_color_override("font_color", Color(0.65, 0.8, 0.7))
	device_box.add_child(_debug_label)

func _build_toolbar() -> void:
	var toolbar := PanelContainer.new()
	toolbar.name = "Toolbar"
	toolbar.anchor_left = 0.0
	toolbar.anchor_top = 0.5
	toolbar.anchor_right = 0.0
	toolbar.anchor_bottom = 0.5
	toolbar.offset_left = 16.0
	toolbar.offset_right = 132.0
	toolbar.offset_top = -78.0
	toolbar.offset_bottom = 78.0
	toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	toolbar.add_theme_stylebox_override("panel", _panel_style(0.62))
	_hud.add_child(toolbar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	toolbar.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	_bind_text(title, "tools.title")
	title.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	box.add_child(title)

	var group := ButtonGroup.new()
	for entry in [["select", "选择", "V"], ["ruler", "标尺", "M"]]:
		var button := Button.new()
		button.text = I18n.t("tool." + String(entry[0]))
		button.tooltip_text = I18n.t("tool.tip", [String(entry[2])])
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 36)
		button.button_pressed = entry[0] == _current_tool
		button.toggled.connect(_on_tool_button_toggled.bind(String(entry[0])))
		box.add_child(button)
		_tool_buttons[entry[0]] = button

func _build_hint_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "HintPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -680.0
	panel.offset_right = -16.0
	panel.offset_top = -84.0
	panel.offset_bottom = -14.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(0.55))
	_hud.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.94))
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_hint_label)
	_refresh_hint()

func _panel_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.07, 0.10, alpha)
	style.border_color = Color(0.35, 0.55, 0.75, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style

func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.title = I18n.t("dialog.open.title")
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.size = Vector2i(900, 600)
	_file_dialog.current_dir = OS.get_environment("HOME")
	_file_dialog.dir_selected.connect(_on_directory_selected)
	add_child(_file_dialog)

func _build_missing_dialog() -> void:
	_missing_dialog = ConfirmationDialog.new()
	_missing_dialog.title = I18n.t("dialog.missing.title")
	_missing_dialog.dialog_text = I18n.t("dialog.missing.text")
	_missing_dialog.ok_button_text = I18n.t("dialog.missing.ok")
	_missing_dialog.cancel_button_text = I18n.t("dialog.missing.cancel")
	_missing_dialog.confirmed.connect(_enter_sim)
	_missing_dialog.custom_action.connect(_on_missing_custom_action)
	add_child(_missing_dialog)

func _build_settings_dialog() -> void:
	_settings_dialog = AcceptDialog.new()
	_settings_dialog.title = I18n.t("settings.title")
	_settings_dialog.ok_button_text = I18n.t("settings.close")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(520, 0)
	_settings_dialog.add_child(box)

	var language_label := Label.new()
	_bind_text(language_label, "settings.language")
	box.add_child(language_label)
	_language_option = OptionButton.new()
	_language_option.add_item("中文", 0)
	_language_option.add_item("English", 1)
	_language_option.selected = 0 if I18n.language == "zh" else 1
	_language_option.item_selected.connect(_on_language_selected)
	box.add_child(_language_option)

	var mouse_label := Label.new()
	_bind_text(mouse_label, "settings.mouse")
	box.add_child(mouse_label)
	_mouse_option = OptionButton.new()
	_mouse_option.add_item(I18n.t("settings.mouse.left"), 0)
	_mouse_option.add_item(I18n.t("settings.mouse.right"), 1)
	_mouse_option.selected = 1 if I18n.mouse_swap else 0
	_mouse_option.item_selected.connect(_on_mouse_selected)
	box.add_child(_mouse_option)
	add_child(_settings_dialog)

func _show_settings() -> void:
	_language_option.selected = 0 if I18n.language == "zh" else 1
	_mouse_option.selected = 1 if I18n.mouse_swap else 0
	_settings_dialog.popup_centered()

func _on_language_selected(index: int) -> void:
	I18n.set_language("zh" if index == 0 else "en")
	_refresh_i18n()

func _on_mouse_selected(index: int) -> void:
	I18n.set_mouse_swap(index == 1)
	_refresh_hint()

func _on_missing_custom_action(action: StringName) -> void:
	if action == &"blender":
		_launch_blender()
	else:
		_missing_dialog.hide()

func _show_open_dialog() -> void:
	_file_dialog.popup_centered()

func _on_directory_selected(dir: String) -> void:
	_open_project(dir)

# ---------------------------------------------------------------- 项目流程

func _open_project(dir: String) -> void:
	_welcome_status.text = I18n.t("status.opening", [dir])
	var result := App.open_project(dir)
	if not bool(result.get("ok", false)):
		_welcome_status.text = String(result.get("error", I18n.t("status.open_failed")))
		return
	Bridge.set_project_dir(App.root_dir)
	_welcome_status.text = ""
	if bool(result.get("needs_virtual", false)):
		_refresh_recent()
		_missing_dialog.popup_centered()
		return
	_enter_sim()

func _enter_sim() -> void:
	if not App.is_open():
		return
	_free_sim()
	_sim = SimView.new()
	_sim.name = "SimView"
	_sim.binding_report.connect(_on_binding_report)
	_sim.interaction_hover_changed.connect(_on_interaction_hover_changed)
	_sim.interaction_triggered.connect(_on_interaction_triggered)
	_sim.tool_changed.connect(_on_tool_changed)
	_sim.ruler_count_changed.connect(_on_ruler_count_changed)
	add_child(_sim)
	_sim.setup(App.get_info())
	_set_tool(_current_tool)

	_project_label.text = "%s  ·  %s" % [App.root_dir.get_file(), String(App.project_json.get("mcu", ""))]
	_welcome.visible = false
	_hud.visible = true
	_on_bridge_state(Bridge.get_service_state())

func _reset_sim() -> void:
	if not App.is_open():
		return
	_enter_sim()
	_set_status(I18n.t("status.reset"))

func _close_project() -> void:
	_free_sim()
	App.close_project()
	Bridge.set_project_dir("")
	_hud.visible = false
	_welcome.visible = true
	_set_status("")
	_refresh_recent()

func _free_sim() -> void:
	if _sim != null:
		_sim.queue_free()
		_sim = null
	_hover_hint = ""
	_ruler_count = 0
	_refresh_hint()

func _launch_blender() -> void:
	var virtual_dir := App.virtual_dir()
	DirAccess.make_dir_recursive_absolute(virtual_dir)
	var blend_path := virtual_dir.path_join("virtual.blend")
	var args := PackedStringArray()
	if FileAccess.file_exists(blend_path):
		args.append(blend_path)
	else:
		args.append("--factory-startup")
	var pid := OS.create_process("blender", args)
	if pid > 0:
		_set_status(I18n.t("status.blender_started"))
	else:
		_set_status(I18n.t("status.blender_failed"))

func _refresh_recent() -> void:
	if _recent_box == null:
		return
	for child in _recent_box.get_children():
		child.queue_free()
	if App.recent.is_empty():
		var empty := Label.new()
		empty.text = I18n.t("welcome.recent_empty")
		empty.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62))
		_recent_box.add_child(empty)
		return
	for path: String in App.recent.slice(0, 5):
		var button := Button.new()
		button.text = "%s\n%s" % [path.get_file(), path]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = path
		button.pressed.connect(_open_project.bind(path))
		_recent_box.add_child(button)

# ---------------------------------------------------------------- 信号

func _connect_signals() -> void:
	App.open_failed.connect(func(message: String) -> void: _welcome_status.text = message)
	Bridge.state_changed.connect(_on_bridge_state)
	Bridge.stream_changed.connect(_on_stream_changed)
	Bridge.session_changed.connect(_on_session_changed)
	Bridge.devices_changed.connect(_on_devices_changed)
	Bridge.input_failed.connect(func(_payload: Dictionary, message: String) -> void:
		_set_status(I18n.t("status.input_failed", [message]))
	)
	_on_bridge_state(Bridge.get_service_state())

func _on_bridge_state(state: String) -> void:
	match state:
		"offline":
			_set_status(I18n.t("status.service_offline"))
		"idle":
			_set_status(I18n.t("status.connected_wait"))
		"running":
			_set_status(I18n.t("status.connecting_stream"))
		"other_project":
			_set_status(I18n.t("status.other_project"))
		_:
			_set_status(I18n.t("status.unknown", [state]))

func _on_stream_changed(connected: bool, message: String) -> void:
	if not Bridge.is_active():
		return
	if connected:
		_set_status(I18n.t("status.stream_connected"))
	elif message.is_empty():
		_set_status(I18n.t("status.stream_disconnected"))
	else:
		_set_status(I18n.t("status.stream_reconnecting", [message]))

func _on_session_changed(active: bool) -> void:
	if active:
		_set_status(I18n.t("status.session_started"))
	else:
		_set_status(I18n.t("status.session_ended"))

func _on_devices_changed(devices: Array) -> void:
	if _sim == null:
		return
	var names := PackedStringArray()
	for item: Variant in devices:
		if typeof(item) == TYPE_DICTIONARY:
			names.append(String(item.get("name", item.get("device", ""))))
	if not names.is_empty() and _debug_label != null:
		_debug_label.text = I18n.t("hud.debug_devices", [", ".join(names)])

func _on_binding_report(report: Dictionary) -> void:
	var bound: Array = report.get("bound", [])
	var errors: Array = report.get("errors", [])
	var lines := PackedStringArray()
	lines.append(I18n.t("hud.scene", [
		I18n.t("hud.placeholder") if bool(report.get("placeholder", false)) else "virtual.glb",
		bound.size(),
	]))
	lines.append(I18n.t("hud.physics", [int(report.get("physics_bodies", 0))]))
	if not errors.is_empty():
		lines.append("")
		for error: Variant in errors:
			lines.append("⚠ " + String(error))
	_device_label.text = "\n".join(lines)
	for error in errors:
		push_warning(String(error))

func _on_tool_button_toggled(pressed: bool, tool: String) -> void:
	if pressed and not _updating_tool_ui:
		_apply_tool(tool)

func _apply_tool(tool: String) -> void:
	_current_tool = tool
	_updating_tool_ui = true
	for key: String in _tool_buttons:
		(_tool_buttons[key] as Button).button_pressed = key == tool
	_updating_tool_ui = false
	if _sim != null:
		_sim.set_tool(tool)
	_hover_hint = ""
	_refresh_hint()

func _set_tool(tool: String) -> void:
	_apply_tool(tool)

func _on_tool_changed(tool: String) -> void:
	_current_tool = tool
	_refresh_hint()

func _on_interaction_hover_changed(device_name: String, hint: String) -> void:
	if device_name.is_empty():
		_hover_hint = ""
	else:
		var action := I18n.t("interact.right" if I18n.mouse_swap else "interact.left")
		_hover_hint = I18n.t("hint.hover", [device_name, hint, action])
	_refresh_hint()

func _on_interaction_triggered(device_name: String) -> void:
	_hover_hint = I18n.t("hint.triggered", [device_name])
	_refresh_hint()

func _on_ruler_count_changed(count: int) -> void:
	_ruler_count = count
	_refresh_hint()

func _refresh_hint() -> void:
	if _hint_label == null:
		return
	var lines := PackedStringArray()
	lines.append(I18n.t("hint.camera.swap" if I18n.mouse_swap else "hint.camera"))
	if not _hover_hint.is_empty():
		lines.append(_hover_hint)
	elif _current_tool == "ruler":
		lines.append(I18n.t("hint.ruler"))
	else:
		var action := I18n.t("interact.right" if I18n.mouse_swap else "interact.left")
		lines.append(I18n.t("hint.select", [action]))
	if _ruler_count > 0:
		lines.append(I18n.t("hint.ruler.count", [_ruler_count]))
	_hint_label.text = "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if _sim == null or not _hud.visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_V:
					_apply_tool("select")
				KEY_M:
					_apply_tool("ruler")

func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
	if _welcome_status != null and _welcome.visible:
		_welcome_status.text = text
	if text.begins_with("调试") or text.begins_with("输出流") or text.begins_with("输入"):
		print("[status] ", text)
