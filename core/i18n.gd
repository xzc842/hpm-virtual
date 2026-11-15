# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 3 of the License.

extends Node

signal language_changed
signal mouse_swap_changed

const SETTINGS_PATH := "user://settings.cfg"
const LANGUAGES := ["zh", "en"]

var language := "zh"
var mouse_swap := false
var _dictionary: Dictionary = {}

func _ready() -> void:
	_load_settings()
	_load_dictionary()

func t(key: String, args: Array = []) -> String:
	var text := String(_dictionary.get(key, key))
	if not args.is_empty():
		return text % args
	return text

func set_language(code: String) -> void:
	if code not in LANGUAGES or code == language:
		return
	language = code
	_load_dictionary()
	_save_settings()
	language_changed.emit()

func set_mouse_swap(enabled: bool) -> void:
	if enabled == mouse_swap:
		return
	mouse_swap = enabled
	_save_settings()
	mouse_swap_changed.emit()

func interact_button() -> int:
	return MOUSE_BUTTON_RIGHT if mouse_swap else MOUSE_BUTTON_LEFT

func camera_button() -> int:
	return MOUSE_BUTTON_LEFT if mouse_swap else MOUSE_BUTTON_RIGHT

func _load_dictionary() -> void:
	var path := "res://i18n/%s.json" % language
	_dictionary = {}
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY:
		_dictionary = data

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		language = String(cfg.get_value("ui", "language", "zh"))
		mouse_swap = bool(cfg.get_value("ui", "mouse_swap", false))
	if language not in LANGUAGES:
		language = "zh"

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "language", language)
	cfg.set_value("ui", "mouse_swap", mouse_swap)
	cfg.save(SETTINGS_PATH)
