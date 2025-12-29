extends PanelContainer

const TILE_SIZES := [128, 256, 512, 1024, 2048]
const UI_SCALES := [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0, 2.5]

var _tile_size_option: OptionButton = null
var _ui_scale_option: OptionButton = null

func _ready() -> void:
	_tile_size_option = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer2/CachingTileSizeHBox/OptionButton")
	_ui_scale_option = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/UIScaleHBox/UIScaleOptionButton")
	_sync_from_settings()
	EventBus.settings_loaded.connect(_on_settings_loaded)
	EventBus.cache_tile_size_updated.connect(_on_tile_size_updated)
	EventBus.ui_scale_updated.connect(_on_ui_scale_updated)

func _on_exit_button_pressed() -> void:
	hide()

func _on_option_button_item_selected(index: int) -> void:
	if index < 0 or index >= TILE_SIZES.size():
		return
	EventBus.set_setting("tile_size", TILE_SIZES[index])

func _on_settings_loaded(_settings: Dictionary) -> void:
	_sync_from_settings()

func _on_tile_size_updated(new_tile_size: int) -> void:
	if _tile_size_option == null:
		return
	var index = TILE_SIZES.find(new_tile_size)
	if index == -1:
		return
	if _tile_size_option.selected != index:
		_tile_size_option.selected = index

func _sync_from_settings() -> void:
	if _tile_size_option != null:
		var saved = int(EventBus.get_setting("tile_size", 512))
		var index = TILE_SIZES.find(saved)
		if index == -1:
			index = 2
		if _tile_size_option.selected != index:
			_tile_size_option.selected = index
	if _ui_scale_option != null:
		var saved_scale = float(EventBus.get_setting("ui_scale", 1.0))
		var scale_index = UI_SCALES.find(saved_scale)
		if scale_index == -1:
			scale_index = 2
		if _ui_scale_option.selected != scale_index:
			_ui_scale_option.selected = scale_index

func _on_check_box_toggled(toggled_on: bool) -> void:
	EventBus.toggle_debug_lines.emit(toggled_on)

func _on_ui_scale_option_button_item_selected(index: int) -> void:
	# Options are (in order, %): 75, 90, 100, 110, 125, 150, 200, 250
	if index < 0 or index >= UI_SCALES.size():
		return
	EventBus.set_setting("ui_scale", UI_SCALES[index])

func _on_ui_scale_updated(new_scale: float) -> void:
	if _ui_scale_option == null:
		return
	var index = UI_SCALES.find(new_scale)
	if index == -1:
		return
	if _ui_scale_option.selected != index:
		_ui_scale_option.selected = index
