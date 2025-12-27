extends PanelContainer

@onready var notepage_button_container: VBoxContainer = %NotepageButtonVBox
@onready var _notepage_button_scene: PackedScene = preload("res://notepage_button.tscn")

const SORT_TITLE := "title"
const SORT_MODIFIED := "modified"
const SORT_CREATED := "created"

var _sort_field: String = SORT_MODIFIED
var _sort_ascending: bool = false

func _ready() -> void:
	_reload_notepage_list()

# Instantiate NotepageButton nodes/classes, filling in their information based on the JSON saves.
func _reload_notepage_list() -> void:
	for child in notepage_button_container.get_children():
		child.queue_free()

	var notes = _load_notes()
	for n in notes:
		var button: NotepageButton = _notepage_button_scene.instantiate()
		button.configure(
			str(n.get("id", "")),
			str(n.get("title", "Unnamed Notepage")),
			int(n.get("created", 0)),
			int(n.get("modified", 0)),
			str(n.get("file_path", ""))
		)
		button.delete_requested.connect(_on_notepage_delete_requested)
		button.duplicate_requested.connect(_on_notepage_duplicate_requested)
		button.open_requested.connect(_on_notepage_open_requested)
		notepage_button_container.add_child(button)
	_apply_sort()

func _load_notes() -> Array:
	var notes: Array = []
	var dir = DirAccess.open("user://notes")
	if not dir:
		return notes

	dir.list_dir_begin()
	while true:
		var file_name = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".json"):
			continue
		var path = "user://notes/%s" % file_name
		var note = _load_note_dict(path)
		if note.is_empty():
			continue
		note["file_path"] = path
		notes.append(note)
	dir.list_dir_end()

	notes.sort_custom(func(a, b): return int(a.get("modified", 0)) > int(b.get("modified", 0)))
	return notes

func _load_note_dict(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _save_note_dict(note: Dictionary) -> String:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("notes"):
		dir.make_dir("notes")
	var note_id = str(note.get("id", ""))
	var path = "user://notes/%s.json" % note_id
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return ""
	f.store_string(JSON.stringify(note, "\t"))
	f.close()
	return path

func _create_note_id() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return "note_%d_%08x" % [int(Time.get_unix_time_from_system()), rng.randi()]

func _on_notepage_delete_requested(_note_id: String, file_path: String) -> void:
	if file_path == "":
		return
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	_reload_notepage_list()

func _on_notepage_duplicate_requested(_note_id: String, file_path: String) -> void:
	if file_path == "":
		return
	var note = _load_note_dict(file_path)
	if note.is_empty():
		return
	var now = int(Time.get_unix_time_from_system())
	note["id"] = _create_note_id()
	note["created"] = now
	note["modified"] = now
	var new_path = _save_note_dict(note)
	if new_path == "":
		return
	_reload_notepage_list()

func _on_notepage_open_requested(_note_id: String, file_path: String) -> void:
	if file_path == "":
		return
	var note = _load_note_dict(file_path)
	if note.is_empty():
		return
	var scene: PackedScene = load("res://notepage.tscn")
	if not scene:
		return
	var instance = scene.instantiate()
	if instance.has_method("load_note"):
		instance.load_note(note)
	var tree = get_tree()
	var root = tree.root
	if tree.current_scene:
		tree.current_scene.queue_free()
	root.add_child(instance)
	tree.current_scene = instance

func _on_title_sort_button_pressed() -> void:
	_set_sort_field(SORT_TITLE)

func _on_date_modified_sort_button_pressed() -> void:
	_set_sort_field(SORT_MODIFIED)

func _on_date_created_sort_button_pressed() -> void:
	_set_sort_field(SORT_CREATED)

func _set_sort_field(field: String) -> void:
	if _sort_field == field:
		_sort_ascending = not _sort_ascending
	else:
		_sort_field = field
		_sort_ascending = field == SORT_TITLE
	_apply_sort()

func _apply_sort() -> void:
	match _sort_field:
		SORT_TITLE:
			_sort_buttons_by_title(_sort_ascending)
		SORT_CREATED:
			_sort_buttons_by_created(_sort_ascending)
		_:
			_sort_buttons_by_modified(_sort_ascending)

func _sort_buttons_by_title(ascending: bool) -> void:
	var buttons = _collect_buttons()
	buttons.sort_custom(func(a, b):
		var at = a.get_title().to_lower()
		var bt = b.get_title().to_lower()
		return at < bt if ascending else at > bt
	)
	_apply_sorted_buttons(buttons)

func _sort_buttons_by_modified(ascending: bool) -> void:
	var buttons = _collect_buttons()
	if ascending:
		buttons.sort_custom(func(a, b): return a.get_modified_ts() < b.get_modified_ts())
	else:
		buttons.sort_custom(func(a, b): return a.get_modified_ts() > b.get_modified_ts())
	_apply_sorted_buttons(buttons)

func _sort_buttons_by_created(ascending: bool) -> void:
	var buttons = _collect_buttons()
	if ascending:
		buttons.sort_custom(func(a, b): return a.get_created_ts() < b.get_created_ts())
	else:
		buttons.sort_custom(func(a, b): return a.get_created_ts() > b.get_created_ts())
	_apply_sorted_buttons(buttons)

func _collect_buttons() -> Array:
	var buttons: Array = []
	for child in notepage_button_container.get_children():
		if child is NotepageButton:
			buttons.append(child)
	return buttons

func _apply_sorted_buttons(buttons: Array) -> void:
	for i in range(buttons.size()):
		notepage_button_container.move_child(buttons[i], i)

func _on_new_notepage_button_pressed() -> void:
	var scene: PackedScene = load("res://notepage.tscn")
	if not scene:
		return
	var instance = scene.instantiate()
	var tree = get_tree()
	var root = tree.root
	if tree.current_scene:
		tree.current_scene.queue_free()
	root.add_child(instance)
	tree.current_scene = instance

func _on_exit_button_pressed() -> void:
	get_tree().quit()
