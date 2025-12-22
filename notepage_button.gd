extends PanelContainer
class_name NotepageButton

signal open_requested(note_id: String, file_path: String)
signal delete_requested(note_id: String, file_path: String)
signal duplicate_requested(note_id: String, file_path: String)

@export var table_key: bool = false # Reserved for the top-most element

var _title: String = "Unnamed Notepage"
func set_title(title: String) -> void:
	$VBoxContainer/HBoxContainer/TitleLabel.text = title if title != "" else "Unnamed Notepage"
	_title = title
func get_title() -> String:
	return _title

var _date_modified: String = "0000-00-00" # YYYY-MM-DD
func set_date_modified(date_modified: String) -> void:
	$VBoxContainer/HBoxContainer/DateModifiedLabel.text = date_modified
	_date_modified = date_modified
func get_date_modified() -> String:
	return _date_modified

var _date_created: String = "0000-00-00" # YYYY-MM-DD
func set_date_created(date_created: String) -> void:
	$VBoxContainer/HBoxContainer/DateCreatedLabel.text = date_created
	_date_created = date_created
func get_date_created() -> String:
	return _date_created

var _note_id: String = ""
var _file_path: String = ""
var _created_ts: int = 0
var _modified_ts: int = 0

func configure(note_id: String, title: String, created_ts: int, modified_ts: int, file_path: String) -> void:
	_note_id = note_id
	_file_path = file_path
	_created_ts = created_ts
	_modified_ts = modified_ts
	set_title(title)
	set_date_created(_format_date(created_ts))
	set_date_modified(_format_date(modified_ts))

func get_created_ts() -> int:
	return _created_ts

func get_modified_ts() -> int:
	return _modified_ts

func _ready() -> void:
	if table_key:
		%Button.queue_free()
		$VBoxContainer/HBoxContainer/TitleLabel.add_theme_font_size_override("font_size", 32)
		$VBoxContainer/HBoxContainer/DateModifiedLabel.add_theme_font_size_override("font_size", 32)
		$VBoxContainer/HBoxContainer/DateCreatedLabel.add_theme_font_size_override("font_size", 32)

var holding_button: bool = false
func _on_button_button_down() -> void:
	holding_button = true
	%HoldingTimer.start()

func _on_button_button_up() -> void:
	holding_button = false
	%HoldingTimer.stop() # Cancel operation

func _on_holding_timer_timeout() -> void: # User held down button for 1 second
	show_options()

func show_options() -> void:
	%OptionsContainer.show()
	%Button.disabled = true

func hide_options() -> void:
	%OptionsContainer.hide()
	%Button.disabled = false

func _on_options_container_mouse_exited() -> void:
	hide_options()

func _on_button_pressed() -> void: # User selected this notepage
	if table_key:
		return
	emit_signal("open_requested", _note_id, _file_path)

func _on_delete_button_pressed() -> void: # User requested to delete this notepage
	if table_key:
		return
	hide_options()
	emit_signal("delete_requested", _note_id, _file_path)

func _on_duplicate_button_pressed() -> void: # User requested to duplicate this notepage
	if table_key:
		return
	hide_options()
	emit_signal("duplicate_requested", _note_id, _file_path)

func _format_date(ts: int) -> String:
	if ts <= 0:
		return "0000-00-00"
	var tz = Time.get_time_zone_from_system()
	var bias_min = int(tz.get("bias", 0))
	var local_ts = ts + bias_min * 60
	var d = Time.get_datetime_dict_from_unix_time(local_ts)
	var hour24 = int(d["hour"])
	var ampm = "am"
	var hour12 = hour24
	if hour24 == 0:
		hour12 = 12
	elif hour24 == 12:
		ampm = "pm"
	elif hour24 > 12:
		hour12 = hour24 - 12
		ampm = "pm"
	return "%04d-%02d-%02d %02d:%02d %s" % [
		int(d["year"]), int(d["month"]), int(d["day"]), hour12, int(d["minute"]), ampm
	]
