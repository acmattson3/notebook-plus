extends PanelContainer

@export var ink_canvas: InkCanvas

var _note_id: String = ""
var _created_ts: int = 0
var _modified_ts: int = 0
var _dirty: bool = false
var _autosave_timer: Timer
var _pending_note: Dictionary = {}
var _debugging: bool = false

@onready var _title_text: TextEdit = $MainContainer/TopBarContainer/TitleTextEdit

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_ensure_note_initialized()
	if not _pending_note.is_empty():
		_apply_loaded_note(_pending_note)
		_pending_note = {}

	if ink_canvas:
		ink_canvas.dirty_changed.connect(_on_canvas_dirty_changed)
		ink_canvas.strokes_changed.connect(_on_canvas_strokes_changed)
		ink_canvas.gui_input.connect(_on_ink_canvas_gui_input)
		if not ink_canvas.touch_state_changed.is_connected(_on_ink_canvas_touch_state_changed):
			ink_canvas.touch_state_changed.connect(_on_ink_canvas_touch_state_changed)

	if _title_text:
		_title_text.text_changed.connect(_on_title_changed)
		_title_text.gui_input.connect(_on_title_gui_input)

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 30.0
	_autosave_timer.one_shot = false
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(_on_autosave_timeout)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_canvas_dirty_changed(is_dirty: bool) -> void:
	if is_dirty:
		_mark_dirty()

func _on_canvas_strokes_changed() -> void:
	_mark_dirty()

func _on_title_changed() -> void:
	_mark_dirty()

func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_title_text.release_focus()
			accept_event()

func _on_ink_canvas_gui_input(event: InputEvent) -> void:
	if not _title_text:
		return
	if not _title_text.has_focus():
		return
	if event is InputEventMouseButton and event.pressed:
		_title_text.release_focus()
	if event is InputEventScreenTouch and event.pressed:
		_title_text.release_focus()

func _mark_dirty() -> void:
	_ensure_note_initialized()
	_dirty = true
	_modified_ts = int(Time.get_unix_time_from_system())
	if _autosave_timer.is_stopped():
		_autosave_timer.start()

func _on_autosave_timeout() -> void:
	if not _dirty:
		_autosave_timer.stop()
		return
	_save_note_to_disk()
	_dirty = false

func _ensure_note_initialized() -> void:
	if _note_id != "":
		return
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	_note_id = "note_%d_%08x" % [int(Time.get_unix_time_from_system()), rng.randi()]
	_created_ts = int(Time.get_unix_time_from_system())
	_modified_ts = _created_ts

func _build_note_data() -> Dictionary:
	var canvas_data: Dictionary = {}
	if ink_canvas:
		canvas_data = ink_canvas.get_note_data()
	return {
		"id": _note_id,
		"title": _title_text.text.strip_edges() if _title_text else "",
		"created": _created_ts,
		"modified": _modified_ts,
		"page": canvas_data.get("page", {}),
		"strokes": canvas_data.get("strokes", []),
	}

func _save_note_to_disk() -> void:
	_modified_ts = int(Time.get_unix_time_from_system())
	var root = DirAccess.open("user://")
	if root and not root.dir_exists("notes"):
		root.make_dir("notes")

	var path = "user://notes/%s.json" % _note_id
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(_build_note_data(), "\t"))
	f.close()

func load_note(note: Dictionary) -> void:
	_pending_note = note.duplicate(true)
	if is_inside_tree():
		_apply_loaded_note(_pending_note)
		_pending_note = {}

func _apply_loaded_note(note: Dictionary) -> void:
	_note_id = str(note.get("id", ""))
	_created_ts = int(note.get("created", 0))
	_modified_ts = int(note.get("modified", _created_ts))
	if _title_text:
		_title_text.text = str(note.get("title", ""))
	if ink_canvas:
		ink_canvas.load_from_note_data(note)
	_dirty = false

func _on_color_picker_button_color_changed(color: Color) -> void:
	ink_canvas.set_pen_color(color)

func _on_undo_button_pressed() -> void:
	ink_canvas.undo()

func _on_redo_button_pressed() -> void:
	ink_canvas.redo()

func _on_save_button_pressed() -> void:
	_save_note_to_disk()

func _on_exit_button_pressed() -> void:
	_save_note_to_disk()
	var scene: PackedScene = load("res://main_menu.tscn")
	if not scene:
		return
	var instance = scene.instantiate()
	var tree = get_tree()
	var root = tree.root
	if tree.current_scene:
		tree.current_scene.queue_free()
	root.add_child(instance)
	tree.current_scene = instance

func _on_ink_canvas_touch_state_changed(state: Dictionary) -> void:
	if not _debugging:
		return
	%DebugLabel.text = ""
	for key in state.keys():
		%DebugLabel.text += str(key) + ": " + str(state[key]) + ";  "

func _on_thickness_slider_value_changed(value: float) -> void:
	ink_canvas.set_pen_thickness(value)

func _on_eraser_slider_value_changed(value: float) -> void:
	ink_canvas.set_eraser_radius(value)
