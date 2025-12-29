extends Node

signal ui_scale_updated(new_scale: float)
signal cache_tile_size_updated(new_tile_size: int)
signal settings_loaded(settings: Dictionary)
signal toggle_debug_lines(showing: bool)

const SETTINGS_PATH := "user://settings.json"

var _settings: Dictionary = {}

func _ready() -> void:
	ui_scale_updated.connect(_apply_ui_scale)
	_load_settings()
	_emit_settings()

func get_setting(key: String, default_value: Variant = null) -> Variant:
	if _settings.has(key):
		return _settings[key]
	return default_value

func set_setting(key: String, value: Variant, emit: bool = true) -> void:
	_settings[key] = value
	_save_settings()
	if emit:
		_emit_settings()

func _default_settings() -> Dictionary:
	return {
		"tile_size": 512,
		"ui_scale": 1.0,
	}

func _load_settings() -> void:
	var settings = _default_settings()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				for k in parsed.keys():
					settings[k] = parsed[k]
	_settings = settings

func _save_settings() -> void:
	var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(_settings, "\t"))
	f.close()

func _emit_settings() -> void:
	settings_loaded.emit(_settings)
	var tile_size = int(get_setting("tile_size", 512))
	cache_tile_size_updated.emit(tile_size)
	var ui_scale = float(get_setting("ui_scale", 1.0))
	ui_scale_updated.emit(ui_scale)

func _apply_ui_scale(new_scale: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_factor = new_scale
