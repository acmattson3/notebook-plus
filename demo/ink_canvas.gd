extends Control
class_name InkCanvas

# -----------------------------
# Signals (Notepage can connect)
# -----------------------------
signal dirty_changed(is_dirty: bool)
signal stroke_committed(stroke_id: String)
signal strokes_changed() # general "something changed" signal
signal touch_state_changed(state: Dictionary)

# -----------------------------
# Public settings (tools/UI)
# -----------------------------
@export var page_width_px: float = 1600.0
@export var side_margin_px: float = 0.0

@export var pen_color: Color = Color(1, 1, 1, 1)
@export var pen_thickness: float = 5.0

@export var eraser_radius_px: float = 18.0
@export var scroll_clamp_top: float = 0.0
@export var bottom_padding_px: float = 600.0

# Two-finger scroll tuning
@export var scroll_speed: float = 1.0

# Stylus heuristic
@export var stylus_pressure_threshold: float = 0.001
@export var stylus_tilt_threshold: float = 0.001
@export var finger_pressure_max: float = 0.99
@export var stylus_use_pressure: bool = false
@export var treat_nan_pressure_as_finger: bool = true
@export var debug_input: bool = false
@export var use_android_raw_input: bool = true
@export var force_android_raw_input: bool = true
@export var stroke_smoothing_enabled: bool = true
@export var stroke_smoothing_window: int = 3

# -----------------------------
# Internal state
# -----------------------------
var _scroll_y: float = 0.0
var _max_doc_y: float = 2000.0 # grows as you write

var _dirty: bool = false

# Active pointers: index -> {pos, last_pos, is_stylus}
var _pointers := {}

# Desktop mouse indices
const INVALID_POINTER_ID := -999999
const MOUSE_DRAW_ID := -1001
const MOUSE_ERASE_ID := -1002
const MOUSE_SCROLL_ID_A := -1003
const MOUSE_SCROLL_ID_B := -1004

# Current mode: "none", "draw", "erase", "scroll"
var _mode: String = "none"
var _active_stylus_index: int = INVALID_POINTER_ID

# Undo/redo stacks: each entry is a Dictionary describing an action
var _undo := []
var _redo := []

# Strokes: list of stroke dicts
# stroke = { id, color, thickness, points:[{x,y,p,t}], bbox:Rect2 }
var strokes: Array = []

# Active stroke being drawn
var _active_stroke: Dictionary = {}

var _mouse_scroll_active: bool = false
var _debug_label: Label
var _raw_input = null
var _raw_input_active: bool = false
var _last_raw_event_msec: int = 0
var _last_raw_empty_log_msec: int = 0
var _last_raw_status_emit_msec: int = 0
const ERASER_PREVIEW_COLOR := Color(1, 0.2, 0.2, 0.25)

# Android MotionEvent constants (subset)
const RAW_ACTION_DOWN := 0
const RAW_ACTION_UP := 1
const RAW_ACTION_MOVE := 2
const RAW_ACTION_CANCEL := 3
const RAW_ACTION_POINTER_DOWN := 5
const RAW_ACTION_POINTER_UP := 6

const RAW_TOOL_TYPE_FINGER := 1
const RAW_TOOL_TYPE_STYLUS := 2
const RAW_TOOL_TYPE_MOUSE := 3
const RAW_TOOL_TYPE_ERASER := 4

# -----------------------------
# Node setup
# -----------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("[InkCanvas] ready size=%s visible=%s" % [size, str(visible)])
	call_deferred("_log_post_layout_size")
	if use_android_raw_input and Engine.has_singleton("NotebookPlusRawInput"):
		_raw_input = Engine.get_singleton("NotebookPlusRawInput")
		_emit_raw_status("singleton_loaded")
	if OS.is_debug_build():
		_debug_label = Label.new()
		_debug_label.name = "InputDebug"
		_debug_label.visible = debug_input
		_debug_label.z_index = 1000
		_debug_label.add_theme_font_size_override("font_size", 14)
		_debug_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		add_child(_debug_label)
	queue_redraw()

func _process(_delta: float) -> void:
	_poll_android_raw_input()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and debug_input:
		print("[InkCanvas] resized size=%s" % [size])

func _log_post_layout_size() -> void:
	if debug_input:
		print("[InkCanvas] post-layout size=%s" % [size])

# -----------------------------
# Public API for Notepage
# -----------------------------
func set_pen_color(c: Color) -> void:
	pen_color = c

func set_pen_thickness(t: float) -> void:
	pen_thickness = max(0.5, t)

func set_eraser_radius(r: float) -> void:
	eraser_radius_px = max(1.0, r)

func undo() -> void:
	if _undo.is_empty():
		return
	var action = _undo.pop_back()
	_apply_undo(action)
	_redo.push_back(action)
	_set_dirty(true)
	emit_signal("strokes_changed")
	queue_redraw()

func redo() -> void:
	if _redo.is_empty():
		return
	var action = _redo.pop_back()
	_apply_redo(action)
	_undo.push_back(action)
	_set_dirty(true)
	emit_signal("strokes_changed")
	queue_redraw()

func clear_all() -> void:
	strokes.clear()
	_undo.clear()
	_redo.clear()
	_active_stroke = {}
	_set_dirty(true)
	emit_signal("strokes_changed")
	queue_redraw()

# Load/save data boundary
func load_from_note_data(note: Dictionary) -> void:
	# Expects note["strokes"] list; points in doc coords.
	strokes.clear()
	for s in note.get("strokes", []):
		var stroke = s.duplicate(true)
		stroke["bbox"] = _compute_bbox_for_points(stroke.get("points", []))
		strokes.append(stroke)
	_undo.clear()
	_redo.clear()
	_active_stroke = {}
	_recompute_max_doc_y()
	_set_dirty(false)
	emit_signal("strokes_changed")
	queue_redraw()

func get_note_data() -> Dictionary:
	# Return ONLY what InkCanvas owns (strokes, page width, scroll)
	var export_strokes: Array = []
	for s in strokes:
		export_strokes.append({
			"id": s.get("id", ""),
			"tool": s.get("tool", "pen"),
			"color": s.get("color", _color_to_html(pen_color)),
			"thickness": s.get("thickness", pen_thickness),
			"points": s.get("points", []),
		})
	return {
		"page": {
			"width_px": page_width_px,
			"scroll_y_px": _scroll_y,
		},
		"strokes": export_strokes,
	}

func set_scroll_y(y: float) -> void:
	_scroll_y = _clamp_scroll(y)
	queue_redraw()

func get_scroll_y() -> float:
	return _scroll_y

# -----------------------------
# Input handling
# -----------------------------
func _gui_input(event: InputEvent) -> void:
	if use_android_raw_input and _raw_input != null and (force_android_raw_input or _raw_input_active):
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			return
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			return
	if debug_input:
		print("[InkCanvas] event: %s pos=%s" % [event.get_class(), _event_position_string(event)])
		_update_debug_label()

	if event is InputEventScreenTouch:
		_handle_touch(event)
		accept_event()
		return

	if event is InputEventScreenDrag:
		_handle_drag(event)
		accept_event()
		return

	# Optional: mouse support for desktop testing
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
		accept_event()
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
		accept_event()
		return

func _handle_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if debug_input:
			print("[InkCanvas] touch down idx=%d %s" % [e.index, _debug_event_info(e)])
		var is_styl = _looks_like_stylus(e)
		_emit_touch_state(e, is_styl)
		_pointers[e.index] = {
			"pos": e.position,
			"last_pos": e.position,
			"is_stylus": is_styl,
		}

		# Basic palm rejection:
		# If stylus is active (drawing), ignore new non-stylus touches.
		if _mode == "draw" and _active_stylus_index != INVALID_POINTER_ID and not is_styl:
			_pointers.erase(e.index)
			return

		_update_mode()
		_begin_mode_if_needed()
	else:
		# Release
		var release_is_stylus = false
		if _pointers.has(e.index):
			release_is_stylus = _pointers[e.index].get("is_stylus", false)
		else:
			release_is_stylus = _looks_like_stylus(e)
		_emit_touch_state(e, release_is_stylus)
		if e.index == _active_stylus_index and _mode == "draw" and _active_stroke.get("points", []).size() == 1:
			var doc = _screen_to_doc(e.position)
			_add_point_to_stroke(_active_stroke, doc, e, float(Time.get_unix_time_from_system()))
		if _pointers.has(e.index):
			_pointers.erase(e.index)

		# If released pointer was stylus, end stroke
		if e.index == _active_stylus_index and _mode == "draw":
			_finish_active_stroke()

		_update_mode()
		queue_redraw()
		# If mode becomes none, nothing else to do

func _handle_drag(e: InputEventScreenDrag) -> void:
	if not _pointers.has(e.index):
		return

	# Update pointer positions
	_pointers[e.index]["last_pos"] = _pointers[e.index]["pos"]
	_pointers[e.index]["pos"] = e.position
	var is_styl = _looks_like_stylus(e)
	_pointers[e.index]["is_stylus"] = is_styl
	_emit_touch_state(e, is_styl)
	if debug_input and _pointers[e.index]["is_stylus"] and e.relative.length() == 0:
		print("[InkCanvas] drag idx=%d %s" % [e.index, _debug_event_info(e)])

	# Re-evaluate mode on the fly; allows switching to scroll mid-gesture
	var old_mode = _mode
	_update_mode()

	# If we switched into scroll while drawing, commit stroke first
	if old_mode == "draw" and _mode == "scroll":
		_finish_active_stroke()

	if _mode == "scroll":
		_scroll_by_two_fingers()
		queue_redraw()
		return

	if _mode == "draw":
		_continue_active_stroke(e)
		queue_redraw()
		return

	if _mode == "erase":
		_erase_at_screen_pos(e.position)
		queue_redraw()
		return

func _handle_mouse_button(e: InputEventMouseButton) -> void:
	# Desktop testing convenience:
	# - Left drag draws
	# - Right drag erases
	# - Middle drag scrolls
	if _is_emulated_mouse(e):
		if e.pressed:
			var is_styl = _mouse_event_is_stylus(e)
			if is_styl:
				_start_mouse_draw(e.position)
			else:
				_start_mouse_erase(e.position)
			_emit_touch_state(e, is_styl)
			return
		else:
			if _pointers.has(MOUSE_DRAW_ID):
				_stop_mouse_draw()
			if _pointers.has(MOUSE_ERASE_ID):
				_stop_mouse_erase()
			_emit_touch_state(e, _mouse_event_is_stylus(e))
			return
	if debug_input:
		print("[InkCanvas] mouse button %s pressed=%s pos=%s" % [str(e.button_index), str(e.pressed), str(e.position)])
	if e.pressed:
		if e.button_index == MOUSE_BUTTON_MIDDLE or (e.button_index == MOUSE_BUTTON_LEFT and e.shift_pressed):
			_start_mouse_scroll(e.position)
			_emit_touch_state(e, false)
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			_start_mouse_draw(e.position)
			_emit_touch_state(e, true)
			return
		if e.button_index == MOUSE_BUTTON_RIGHT:
			_start_mouse_erase(e.position)
			_emit_touch_state(e, false)
			return
	else:
		if _mouse_scroll_active and (e.button_index == MOUSE_BUTTON_MIDDLE or e.button_index == MOUSE_BUTTON_LEFT):
			_stop_mouse_scroll()
			_emit_touch_state(e, false)
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			_stop_mouse_draw()
			queue_redraw()
			_emit_touch_state(e, true)
			return
		if e.button_index == MOUSE_BUTTON_RIGHT:
			_stop_mouse_erase()
			queue_redraw()
			_emit_touch_state(e, false)
			return

func _handle_mouse_motion(e: InputEventMouseMotion) -> void:
	# Desktop testing convenience: implement if desired
	if _is_emulated_mouse(e):
		var is_styl = _mouse_event_is_stylus(e)
		if (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if is_styl:
				if not _pointers.has(MOUSE_DRAW_ID):
					_start_mouse_draw(e.position)
			else:
				if not _pointers.has(MOUSE_ERASE_ID):
					_start_mouse_erase(e.position)

		_update_mouse_pointers(e.position)
		_emit_touch_state(e, is_styl)

		var old_mode = _mode
		_update_mode()
		if old_mode == "draw" and _mode == "scroll":
			_finish_active_stroke()

		if _mode == "scroll":
			_scroll_by_two_fingers()
			queue_redraw()
			_update_debug_label()
			return

		if _mode == "draw":
			_continue_active_stroke_mouse(MOUSE_DRAW_ID, e.position, _mouse_event_pressure(e))
			queue_redraw()
			_update_debug_label()
			return

		if _mode == "erase":
			_erase_at_screen_pos(e.position)
			queue_redraw()
			_update_debug_label()
			return
	if debug_input:
		print("[InkCanvas] mouse motion pos=%s rel=%s" % [str(e.position), str(e.relative)])
	if _pointers.is_empty():
		if debug_input and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			print("[InkCanvas] motion with left down but no pointers")
		return

	_update_mouse_pointers(e.position)
	_emit_touch_state(e, (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)

	# If right mouse is down, force erase behavior for desktop testing.
	if _pointers.has(MOUSE_ERASE_ID) and not _pointers.has(MOUSE_DRAW_ID) and not _mouse_scroll_active:
		_erase_at_screen_pos(e.position)
		queue_redraw()
		_update_debug_label()
		return

	var old_mode = _mode
	_update_mode()
	if old_mode == "draw" and _mode == "scroll":
		_finish_active_stroke()

	if _mode == "scroll":
		_scroll_by_two_fingers()
		queue_redraw()
		_update_debug_label()
		return

	if _mode == "draw":
		_continue_active_stroke_mouse(MOUSE_DRAW_ID, e.position, 1.0)
		queue_redraw()
		_update_debug_label()
		return

	if _mode == "erase":
		_erase_at_screen_pos(e.position)
		queue_redraw()
		_update_debug_label()
		return

# -----------------------------
# Mode management
# -----------------------------
func _update_mode() -> void:
	# Determine desired mode based on active pointers.
	# Priority: 2-finger scroll > stylus draw > finger erase > none
	var stylus_indices := []
	var finger_indices := []

	for idx in _pointers.keys():
		var p = _pointers[idx]
		if p["is_stylus"]:
			stylus_indices.append(idx)
		else:
			finger_indices.append(idx)

	# Two-finger scroll = two (or more) fingers, no stylus draw in progress
	if finger_indices.size() >= 2 and stylus_indices.is_empty():
		_mode = "scroll"
		_active_stylus_index = INVALID_POINTER_ID
		if debug_input:
			print("[InkCanvas] mode=scroll stylus=%d finger=%d" % [stylus_indices.size(), finger_indices.size()])
		return

	# Stylus draw
	if stylus_indices.size() >= 1:
		_mode = "draw"
		_active_stylus_index = int(stylus_indices[0])
		if debug_input:
			print("[InkCanvas] mode=draw stylus=%d finger=%d active_stylus=%d" % [
				stylus_indices.size(), finger_indices.size(), _active_stylus_index
			])
		return

	# Single finger erase
	if finger_indices.size() == 1:
		_mode = "erase"
		_active_stylus_index = INVALID_POINTER_ID
		if debug_input:
			print("[InkCanvas] mode=erase stylus=%d finger=%d" % [stylus_indices.size(), finger_indices.size()])
		return

	_mode = "none"
	_active_stylus_index = INVALID_POINTER_ID
	_update_debug_label()
	if debug_input:
		print("[InkCanvas] mode=none stylus=%d finger=%d" % [stylus_indices.size(), finger_indices.size()])

func _begin_mode_if_needed() -> void:
	if _mode == "draw":
		if debug_input:
			print("[InkCanvas] begin draw")
		_start_active_stroke()
	elif _mode == "erase":
		# No setup needed; erase on drag
		pass
	elif _mode == "scroll":
		# No setup needed; scroll on drag
		pass

# -----------------------------
# Stylus heuristic
# -----------------------------
func _looks_like_stylus(e: InputEvent) -> bool:
	# Godot touch events expose pressure/tilt on some devices.
	# This heuristic may be device dependent; keep it adjustable.
	var explicit_stylus := false
	var source = _get_event_source(e)
	if source != null:
		var stylus_source = _get_input_event_const("SOURCE_STYLUS")
		if stylus_source != null and int(source) == int(stylus_source):
			explicit_stylus = true
			return true
		var touch_source = _get_input_event_const("SOURCE_TOUCHSCREEN")
		if touch_source != null and int(source) == int(touch_source):
			return false

	var tool = _get_event_tool(e)
	if tool != null:
		var stylus_tool = _get_input_event_const("TOOL_TYPE_STYLUS")
		if stylus_tool != null and int(tool) == int(stylus_tool):
			explicit_stylus = true
			return true
		var eraser_tool = _get_input_event_const("TOOL_TYPE_ERASER")
		if eraser_tool != null and int(tool) == int(eraser_tool):
			explicit_stylus = true
			return true
		var finger_tool = _get_input_event_const("TOOL_TYPE_FINGER")
		if finger_tool != null and int(tool) == int(finger_tool):
			return false

	var pressure := 0.0
	var tilt := Vector2.ZERO

	if e is InputEventScreenTouch:
		pressure = e.pressure
		tilt = e.tilt
	elif e is InputEventScreenDrag:
		pressure = e.pressure
		tilt = e.tilt
	else:
		return false

	# Handle NaN pressure on some devices
	if treat_nan_pressure_as_finger and is_nan(pressure):
		pressure = 0.0

	if not explicit_stylus and pressure >= finger_pressure_max and tilt.length() <= stylus_tilt_threshold:
		return false
	if tilt.length() > stylus_tilt_threshold:
		return true
	if stylus_use_pressure and pressure > stylus_pressure_threshold:
		return true

	return false

func _get_event_source(e: InputEvent) -> Variant:
	if e.has_method("get_source"):
		return e.get_source()
	return null

func _get_event_tool(e: InputEvent) -> Variant:
	if e.has_method("get_tool"):
		return e.get_tool()
	return null

func _get_input_event_const(name: String) -> Variant:
	if ClassDB.class_has_integer_constant("InputEvent", name):
		return ClassDB.class_get_integer_constant("InputEvent", name)
	return null

func _debug_event_info(e: InputEvent) -> String:
	var source = _get_event_source(e)
	var tool = _get_event_tool(e)
	var pressure := 0.0
	var tilt := Vector2.ZERO
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		pressure = e.pressure
		tilt = e.tilt
	return "src=%s tool=%s pressure=%.4f tilt=%.4f" % [
		str(source), str(tool), pressure, tilt.length()
	]

func _emit_touch_state(e: InputEvent, is_stylus: bool) -> void:
	if not debug_input:
		return
	var source = _get_event_source(e)
	var tool = _get_event_tool(e)
	var pos = Vector2.ZERO
	var rel = Vector2.ZERO
	var pressure := 0.0
	var tilt := Vector2.ZERO
	var velocity = Vector2.ZERO
	var pressed = false
	var index = -1
	var device = "unknown"
	var button_index = -1
	var button_mask = 0
	var shift = false
	var alt = false
	var ctrl = false
	var meta = false
	var pen_inverted = false
	if e is InputEventScreenTouch:
		device = "touch"
		pos = e.position
		pressed = e.pressed
		index = e.index
	elif e is InputEventScreenDrag:
		device = "touch"
		pos = e.position
		rel = e.relative
		velocity = e.velocity
		index = e.index
	elif e is InputEventMouseButton:
		device = "mouse"
		pos = e.position
		button_index = e.button_index
		button_mask = e.button_mask
		pressed = e.pressed
		shift = e.shift_pressed
		alt = e.alt_pressed
		ctrl = e.ctrl_pressed
		meta = e.meta_pressed
	elif e is InputEventMouseMotion:
		device = "mouse"
		pos = e.position
		rel = e.relative
		velocity = e.velocity
		button_mask = e.button_mask
		shift = e.shift_pressed
		alt = e.alt_pressed
		ctrl = e.ctrl_pressed
		meta = e.meta_pressed
	if e.has_method("get_pressure"):
		pressure = e.get_pressure()
	if e.has_method("get_tilt"):
		tilt = e.get_tilt()
	if e.has_method("get_pen_inverted"):
		pen_inverted = e.get_pen_inverted()
	elif e.has_method("is_pen_inverted"):
		pen_inverted = e.is_pen_inverted()
	if treat_nan_pressure_as_finger and is_nan(pressure):
		pressure = 0.0
	var counts = _count_pointer_types()
	var pointer_snapshot: Array = []
	for idx in _pointers.keys():
		var p = _pointers[idx]
		pointer_snapshot.append({
			"index": idx,
			"pos": p.get("pos", Vector2.ZERO),
			"last_pos": p.get("last_pos", Vector2.ZERO),
			"is_stylus": p.get("is_stylus", false),
		})
	var state = {
		"event_class": e.get_class(),
		"device": device,
		"index": index,
		"pressed": pressed,
		"position": pos,
		"relative": rel,
		"velocity": velocity,
		"pressure": pressure,
		"tilt": tilt,
		"tilt_length": tilt.length(),
		"tilt_angle_rad": tilt.angle(),
		"button_index": button_index,
		"button_mask": button_mask,
		"shift": shift,
		"alt": alt,
		"ctrl": ctrl,
		"meta": meta,
		"pen_inverted": pen_inverted,
		"source": source,
		"tool": tool,
		"is_stylus": is_stylus,
		"mode": _mode,
		"active_stylus_index": _active_stylus_index,
		"stylus_count": counts["stylus"],
		"finger_count": counts["finger"],
		"strokes_count": strokes.size(),
		"active_points": _active_stroke.get("points", []).size(),
		"scroll_y": _scroll_y,
		"pointers": pointer_snapshot,
	}
	emit_signal("touch_state_changed", state)

func _count_pointer_types() -> Dictionary:
	var stylus_count = 0
	var finger_count = 0
	for idx in _pointers.keys():
		if _pointers[idx]["is_stylus"]:
			stylus_count += 1
		else:
			finger_count += 1
	return {
		"stylus": stylus_count,
		"finger": finger_count,
	}

# -----------------------------
# Stroke lifecycle
# -----------------------------
func _start_active_stroke() -> void:
	if _active_stylus_index == INVALID_POINTER_ID:
		if debug_input:
			print("[InkCanvas] start stroke blocked: no active stylus")
		return
	if not _pointers.has(_active_stylus_index):
		if debug_input:
			print("[InkCanvas] start stroke blocked: stylus missing")
		return

	# Cancel any existing active stroke (shouldn't happen, but safe)
	_active_stroke = {}

	var start_pos = _pointers[_active_stylus_index]["pos"]
	var doc = _screen_to_doc(start_pos)

	var sid = _new_stroke_id()
	_active_stroke = {
		"id": sid,
		"tool": "pen",
		"color": _color_to_html(pen_color),
		"thickness": pen_thickness,
		"points": [],
		"bbox": Rect2(doc, Vector2.ZERO),
	}

	_add_point_to_stroke(_active_stroke, doc, _pointers[_active_stylus_index], 0.0)
	if debug_input:
		print("[InkCanvas] start stroke id=%s first_point=%s" % [_active_stroke.get("id", ""), str(doc)])

func _continue_active_stroke(e: InputEventScreenDrag) -> void:
	if _active_stroke.is_empty():
		# If stylus down but stroke not started yet, start it
		_start_active_stroke()
		return

	# Only accept points from the active stylus pointer
	if e.index != _active_stylus_index:
		return

	var doc = _screen_to_doc(e.position)
	_add_point_to_stroke(_active_stroke, doc, e, float(Time.get_unix_time_from_system()))
	if debug_input and _active_stroke["points"].size() == 2:
		print("[InkCanvas] touch stroke started id=%s" % _active_stroke.get("id", ""))

	# Extend doc bounds
	_max_doc_y = max(_max_doc_y, doc.y + bottom_padding_px)

func _continue_active_stroke_mouse(pointer_id: int, screen_pos: Vector2, pressure: float) -> void:
	if _active_stroke.is_empty():
		_start_active_stroke()
		return
	if pointer_id != _active_stylus_index:
		return

	var doc = _screen_to_doc(screen_pos)
	_add_point_to_stroke(_active_stroke, doc, {"pressure": pressure}, float(Time.get_unix_time_from_system()))
	if debug_input and _active_stroke["points"].size() == 2:
		print("[InkCanvas] mouse stroke started id=%s" % _active_stroke.get("id", ""))
	_max_doc_y = max(_max_doc_y, doc.y + bottom_padding_px)

func _finish_active_stroke() -> void:
	if _active_stroke.is_empty():
		return

	# Require at least 1 point (single-point dots allowed)
	if _active_stroke["points"].size() < 1:
		_active_stroke = {}
		return

	_active_stroke["points"] = _simplify_axis_aligned_points(_active_stroke["points"])
	_active_stroke["bbox"] = _compute_bbox_for_points(_active_stroke["points"])

	# Commit
	strokes.append(_active_stroke)
	if debug_input:
		print("[InkCanvas] stroke committed id=%s points=%d" % [_active_stroke.get("id", ""), _active_stroke.get("points", []).size()])

	# Undo entry
	var action = {
		"type": "add_stroke",
		"stroke": _active_stroke,
	}
	_undo.push_back(action)
	_redo.clear()

	_set_dirty(true)
	emit_signal("stroke_committed", _active_stroke["id"])
	emit_signal("strokes_changed")

	_active_stroke = {}
	queue_redraw()

func _start_mouse_draw(pos: Vector2) -> void:
	if debug_input:
		print("[InkCanvas] mouse draw start pos=%s" % str(pos))
	_pointers[MOUSE_DRAW_ID] = {
		"pos": pos,
		"last_pos": pos,
		"is_stylus": true,
	}
	_update_mode()
	_begin_mode_if_needed()

func _stop_mouse_draw() -> void:
	if _pointers.has(MOUSE_DRAW_ID):
		if _mode == "draw" and _active_stylus_index == MOUSE_DRAW_ID and _active_stroke.get("points", []).size() == 1:
			var pos = _pointers[MOUSE_DRAW_ID]["pos"]
			var doc = _screen_to_doc(pos)
			_add_point_to_stroke(_active_stroke, doc, {"pressure": 1.0}, float(Time.get_unix_time_from_system()))
		_pointers.erase(MOUSE_DRAW_ID)
	if _mode == "draw" and _active_stylus_index == MOUSE_DRAW_ID:
		_finish_active_stroke()
	_update_mode()

func _start_mouse_erase(pos: Vector2) -> void:
	_pointers[MOUSE_ERASE_ID] = {
		"pos": pos,
		"last_pos": pos,
		"is_stylus": false,
	}
	_update_mode()
	_begin_mode_if_needed()
	# Allow tap-erase on press.
	_erase_at_screen_pos(pos)
	queue_redraw()

func _stop_mouse_erase() -> void:
	if _pointers.has(MOUSE_ERASE_ID):
		_pointers.erase(MOUSE_ERASE_ID)
	_update_mode()

func _start_mouse_scroll(pos: Vector2) -> void:
	_mouse_scroll_active = true
	_pointers[MOUSE_SCROLL_ID_A] = {
		"pos": pos,
		"last_pos": pos,
		"is_stylus": false,
	}
	_pointers[MOUSE_SCROLL_ID_B] = {
		"pos": pos,
		"last_pos": pos,
		"is_stylus": false,
	}
	_update_mode()
	_begin_mode_if_needed()

func _stop_mouse_scroll() -> void:
	_mouse_scroll_active = false
	if _pointers.has(MOUSE_SCROLL_ID_A):
		_pointers.erase(MOUSE_SCROLL_ID_A)
	if _pointers.has(MOUSE_SCROLL_ID_B):
		_pointers.erase(MOUSE_SCROLL_ID_B)
	_update_mode()

func _update_mouse_pointers(pos: Vector2) -> void:
	for idx in _pointers.keys():
		if idx >= 0:
			continue
		_pointers[idx]["last_pos"] = _pointers[idx]["pos"]
		_pointers[idx]["pos"] = pos

func _update_debug_label() -> void:
	if not debug_input:
		if _debug_label:
			_debug_label.visible = false
		return
	if not _debug_label:
		return
	_debug_label.visible = OS.is_debug_build()
	var counts = _count_pointer_types()
	var stylus_count = counts["stylus"]
	var finger_count = counts["finger"]
	var active_pts = 0
	if not _active_stroke.is_empty():
		active_pts = _active_stroke.get("points", []).size()
	_debug_label.text = "mode=%s  stylus=%d  finger=%d  strokes=%d  active_pts=%d  scroll_y=%.1f" % [
		_mode, stylus_count, finger_count, strokes.size(), active_pts, _scroll_y
	]

func _event_position_string(event: InputEvent) -> String:
	if event is InputEventScreenTouch:
		return str(event.position)
	if event is InputEventScreenDrag:
		return str(event.position)
	if event is InputEventMouseButton:
		return str(event.position)
	if event is InputEventMouseMotion:
		return str(event.position)
	return "n/a"

func _poll_android_raw_input() -> void:
	if _raw_input == null:
		_emit_raw_status("singleton_missing")
		return
	var events = _raw_input.poll_events()
	if events == null:
		_emit_raw_status("poll_null")
		return
	var now = Time.get_ticks_msec()
	if events.size() == 0:
		if _raw_input_active and now - _last_raw_event_msec > 500:
			_raw_input_active = false
		var status = "no_events"
		if _raw_input.has_method("get_status"):
			status = "no_events:" + str(_raw_input.get_status())
		_emit_raw_status(status)
		return
	_raw_input_active = true
	_last_raw_event_msec = now
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_handle_raw_event(e)

func _emit_raw_status(status: String) -> void:
	var now = Time.get_ticks_msec()
	if now - _last_raw_status_emit_msec < 1000:
		return
	_last_raw_status_emit_msec = now
	var state = {
		"event_class": "RawStatus",
		"device": "android_raw",
		"status": status,
		"raw_active": _raw_input_active,
	}
	emit_signal("touch_state_changed", state)

func _handle_raw_event(e: Dictionary) -> void:
	var action = int(e.get("action", -1))
	var pointer_id = int(e.get("pointer_id", -1))
	var is_action_index = bool(e.get("is_action_index", true))
	var tool = int(e.get("tool", RAW_TOOL_TYPE_FINGER))
	var raw_pos = Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
	var pos = _raw_to_local(raw_pos)
	var pressure = float(e.get("pressure", 0.0))
	var tilt = float(e.get("tilt", 0.0))
	var is_styl = _raw_is_stylus(tool, pressure, tilt)

	if (action == RAW_ACTION_DOWN or action == RAW_ACTION_POINTER_DOWN) and not is_action_index:
		return
	if (action == RAW_ACTION_UP or action == RAW_ACTION_POINTER_UP) and not is_action_index:
		return

	if action == RAW_ACTION_DOWN or action == RAW_ACTION_POINTER_DOWN:
		_pointers[pointer_id] = {
			"pos": pos,
			"last_pos": pos,
			"is_stylus": is_styl,
		}
		if _mode == "draw" and _active_stylus_index != INVALID_POINTER_ID and not is_styl:
			_pointers.erase(pointer_id)
			_emit_raw_state(e, is_styl, "down_ignored")
			return
		_update_mode()
		_begin_mode_if_needed()
		_emit_raw_state(e, is_styl, "down")
		return

	if action == RAW_ACTION_UP or action == RAW_ACTION_POINTER_UP or action == RAW_ACTION_CANCEL:
		_emit_raw_state(e, is_styl, "up")
		if pointer_id == _active_stylus_index and _mode == "draw":
			if _active_stroke.get("points", []).size() == 1:
				var doc = _screen_to_doc(pos)
				_add_point_to_stroke(_active_stroke, doc, {"pressure": pressure}, float(Time.get_unix_time_from_system()))
			_finish_active_stroke()
		if _pointers.has(pointer_id):
			_pointers.erase(pointer_id)
		_update_mode()
		queue_redraw()
		return

	if action == RAW_ACTION_MOVE:
		if not _pointers.has(pointer_id):
			return
		_pointers[pointer_id]["last_pos"] = _pointers[pointer_id]["pos"]
		_pointers[pointer_id]["pos"] = pos
		_pointers[pointer_id]["is_stylus"] = is_styl
		var old_mode = _mode
		_update_mode()
		if old_mode == "draw" and _mode == "scroll":
			_finish_active_stroke()
		if _mode == "scroll":
			_scroll_by_two_fingers()
			queue_redraw()
			_emit_raw_state(e, is_styl, "move_scroll")
			return
		if _mode == "draw":
			_continue_active_stroke_raw(pointer_id, pos, pressure)
			queue_redraw()
			_emit_raw_state(e, is_styl, "move_draw")
			return
		if _mode == "erase":
			_erase_at_screen_pos(pos)
			queue_redraw()
			_emit_raw_state(e, is_styl, "move_erase")
			return

func _continue_active_stroke_raw(pointer_id: int, screen_pos: Vector2, pressure: float) -> void:
	if _active_stroke.is_empty():
		_start_active_stroke()
		return
	if pointer_id != _active_stylus_index:
		return
	var doc = _screen_to_doc(screen_pos)
	_add_point_to_stroke(_active_stroke, doc, {"pressure": pressure}, float(Time.get_unix_time_from_system()))
	if debug_input and _active_stroke["points"].size() == 2:
		print("[InkCanvas] raw stroke started id=%s" % _active_stroke.get("id", ""))
	_max_doc_y = max(_max_doc_y, doc.y + bottom_padding_px)

func _raw_is_stylus(tool: int, pressure: float, tilt: float) -> bool:
	if tool == RAW_TOOL_TYPE_STYLUS or tool == RAW_TOOL_TYPE_ERASER:
		return true
	if tool == RAW_TOOL_TYPE_FINGER:
		return false
	if tilt > stylus_tilt_threshold:
		return true
	if stylus_use_pressure and pressure > stylus_pressure_threshold:
		return true
	return false

func _emit_raw_state(raw: Dictionary, is_stylus: bool, phase: String) -> void:
	var counts = _count_pointer_types()
	var state = {
		"event_class": "RawMotionEvent",
		"device": "android_raw",
		"phase": phase,
		"index": int(raw.get("pointer_id", -1)),
		"position": _raw_to_local(Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))),
		"raw_position": Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0))),
		"pressure": float(raw.get("pressure", 0.0)),
		"tilt": float(raw.get("tilt", 0.0)),
		"tool": int(raw.get("tool", RAW_TOOL_TYPE_FINGER)),
		"is_stylus": is_stylus,
		"mode": _mode,
		"active_stylus_index": _active_stylus_index,
		"stylus_count": counts["stylus"],
		"finger_count": counts["finger"],
		"strokes_count": strokes.size(),
		"active_points": _active_stroke.get("points", []).size(),
		"scroll_y": _scroll_y,
		"raw": raw,
	}
	emit_signal("touch_state_changed", state)

func _raw_to_local(raw_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * raw_pos

func _is_emulated_mouse(e: InputEvent) -> bool:
	if not e.has_method("is_emulated"):
		return false
	return e.is_emulated()

func _mouse_event_pressure(e: InputEvent) -> float:
	var p := 0.0
	if e.has_method("get_pressure"):
		p = e.get_pressure()
	if treat_nan_pressure_as_finger and is_nan(p):
		p = 0.0
	return p

func _mouse_event_is_stylus(e: InputEvent) -> bool:
	var pressure = _mouse_event_pressure(e)
	var tilt := Vector2.ZERO
	if e.has_method("get_tilt"):
		tilt = e.get_tilt()
	var pen_inverted = false
	if e.has_method("get_pen_inverted"):
		pen_inverted = e.get_pen_inverted()
	elif e.has_method("is_pen_inverted"):
		pen_inverted = e.is_pen_inverted()
	if pen_inverted:
		return true
	if tilt.length() > stylus_tilt_threshold:
		return true
	if pressure > stylus_pressure_threshold:
		return true
	return false


func _color_to_html(c: Color) -> String:
	return "#" + c.to_html(false)

func _add_point_to_stroke(stroke: Dictionary, doc: Vector2, e: Variant, t_unix: float) -> void:
	var p := 0.0
	if "pressure" in e:
		p = float(e.pressure)
		if treat_nan_pressure_as_finger and is_nan(p):
			p = 0.0

	stroke["points"].append({
		"x": doc.x,
		"y": doc.y,
		"p": p,
		"t": t_unix,
	})

	# Update bbox
	var bbox: Rect2 = stroke["bbox"]
	if bbox.size == Vector2.ZERO:
		stroke["bbox"] = Rect2(doc, Vector2(1, 1))
	else:
		var min_x = min(bbox.position.x, doc.x)
		var min_y = min(bbox.position.y, doc.y)
		var max_x = max(bbox.position.x + bbox.size.x, doc.x)
		var max_y = max(bbox.position.y + bbox.size.y, doc.y)
		stroke["bbox"] = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _compute_bbox_for_points(points: Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_x = float(points[0]["x"])
	var min_y = float(points[0]["y"])
	var max_x = min_x
	var max_y = min_y
	for p in points:
		var x = float(p["x"])
		var y = float(p["y"])
		min_x = min(min_x, x)
		min_y = min(min_y, y)
		max_x = max(max_x, x)
		max_y = max(max_y, y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _simplify_axis_aligned_points(points: Array) -> Array:
	if points.size() <= 2:
		return points
	var simplified: Array = []
	simplified.append(points[0])
	var last_dir := Vector2.ZERO

	for i in range(1, points.size()):
		var prev = simplified[simplified.size() - 1]
		var curr = points[i]
		var dx = float(curr["x"]) - float(prev["x"])
		var dy = float(curr["y"]) - float(prev["y"])
		var dir := Vector2.ZERO

		if is_equal_approx(dy, 0.0) and not is_equal_approx(dx, 0.0):
			dir = Vector2(sign(dx), 0)
		elif is_equal_approx(dx, 0.0) and not is_equal_approx(dy, 0.0):
			dir = Vector2(0, sign(dy))
		else:
			# Diagonal or identical point, keep it and reset direction.
			simplified.append(curr)
			last_dir = Vector2.ZERO
			continue

		if last_dir != Vector2.ZERO and dir == last_dir:
			# Same axis direction, replace last point to extend the segment.
			simplified[simplified.size() - 1] = curr
		else:
			# New axis direction, keep the corner.
			simplified.append(curr)
			last_dir = dir

	return simplified

# -----------------------------
# Scrolling
# -----------------------------
func _scroll_by_two_fingers() -> void:
	# Average delta of all finger pointers
	var deltas := []
	for idx in _pointers.keys():
		var p = _pointers[idx]
		if p["is_stylus"]:
			continue
		var dy = float(p["pos"].y - p["last_pos"].y)
		deltas.append(dy)

	if deltas.size() < 2:
		return

	var avg_dy := 0.0
	for dy in deltas:
		avg_dy += dy
	avg_dy /= float(deltas.size())

	_scroll_y = _clamp_scroll(_scroll_y - avg_dy * scroll_speed)

func _clamp_scroll(y: float) -> float:
	var max_scroll = max(scroll_clamp_top, _max_doc_y - size.y)
	return clamp(y, scroll_clamp_top, max_scroll)

# -----------------------------
# Erasing (whole-stroke)
# -----------------------------
func _erase_at_screen_pos(screen_pos: Vector2) -> void:
	# If we are currently drawing, don't erase
	if _mode == "draw":
		return

	var doc = _screen_to_doc(screen_pos)
	var removed_ids := []

	# Find strokes that intersect eraser radius
	# We'll remove at most one per call for MVP to keep it predictable.
	var idx_to_remove := -1
	for i in range(strokes.size() - 1, -1, -1):
		var s: Dictionary = strokes[i]
		if _stroke_hit_test(s, doc, eraser_radius_px):
			idx_to_remove = i
			break

	if idx_to_remove == -1:
		return

	var removed_stroke: Dictionary = strokes[idx_to_remove]
	removed_ids.append(removed_stroke["id"])
	strokes.remove_at(idx_to_remove)

	# Undo entry
	var action = {
		"type": "erase_strokes",
		"strokes": [removed_stroke],
	}
	_undo.push_back(action)
	_redo.clear()

	_set_dirty(true)
	emit_signal("strokes_changed")

func _stroke_hit_test(stroke: Dictionary, doc_pos: Vector2, radius: float) -> bool:
	# Quick bbox reject
	if stroke.has("bbox"):
		var bbox: Rect2 = stroke["bbox"]
		var expanded = bbox.grow(radius)
		if not expanded.has_point(doc_pos):
			return false

	var pts = stroke.get("points", [])
	if pts.size() < 2:
		return false

	var r2 = radius * radius
	for i in range(pts.size() - 1):
		var a = Vector2(float(pts[i]["x"]), float(pts[i]["y"]))
		var b = Vector2(float(pts[i + 1]["x"]), float(pts[i + 1]["y"]))
		if _dist2_point_to_segment(doc_pos, a, b) <= r2:
			return true

	return false

func _dist2_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var ap = p - a
	var ab_len2 = ab.length_squared()
	if ab_len2 <= 0.000001:
		return ap.length_squared()

	var t = clamp(ap.dot(ab) / ab_len2, 0.0, 1.0)
	var proj = a + ab * t
	return (p - proj).length_squared()

# -----------------------------
# Rendering
# -----------------------------
func _draw() -> void:
	# Draw a centered "page" area (fixed width) on black background
	# Background should be black in parent, but harmless here too.
	# draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK, true)

	var page_left = (size.x - page_width_px) * 0.5
	var page_rect = Rect2(Vector2(page_left, 0), Vector2(page_width_px, size.y))

	# Optional: subtle page boundary. Keep it very faint.
	draw_rect(page_rect, Color(1, 1, 1, 0.05), false, 2.0)

	# Clip drawing to the page rect by manual cull (Control doesn't auto-clip draw calls).
	# MVP: just cull by x bounds and y in view.

	# Draw committed strokes
	for s in strokes:
		_draw_stroke(s, page_left)

	# Draw active stroke
	if not _active_stroke.is_empty():
		_draw_stroke(_active_stroke, page_left)

	# Draw eraser preview when erasing
	if _mode == "erase":
		var erase_pos = _get_erase_preview_pos()
		if erase_pos != null:
			draw_circle(erase_pos, eraser_radius_px, ERASER_PREVIEW_COLOR)

func _draw_stroke(stroke: Dictionary, page_left: float) -> void:
	var pts = stroke.get("points", [])
	var thickness = float(stroke.get("thickness", pen_thickness))
	var color = Color.WHITE
	if stroke.has("color"):
		var cstr = str(stroke["color"])
		if not cstr.begins_with("#"):
			cstr = "#" + cstr
		color = Color.html(cstr)
	else:
		color = pen_color

	if pts.size() == 1:
		var x = float(pts[0]["x"])
		var y = float(pts[0]["y"])
		var sx = page_left + x
		var sy = y - _scroll_y
		draw_circle(Vector2(sx, sy), max(1.0, thickness * 0.5), color)
		return
	if pts.size() < 2:
		return

	# Convert points doc->screen and cull quickly
	var screen_pts: PackedVector2Array = PackedVector2Array()
	screen_pts.resize(pts.size())

	for i in range(pts.size()):
		var x = float(pts[i]["x"])
		var y = float(pts[i]["y"])
		var sx = page_left + x
		var sy = y - _scroll_y
		screen_pts[i] = Vector2(sx, sy)

	if stroke_smoothing_enabled:
		screen_pts = _smooth_screen_points(screen_pts, stroke_smoothing_window)

	# Cheap y-cull: if entirely out of view, skip
	var min_y = INF
	var max_y = -INF
	for v in screen_pts:
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)
	if max_y < -200 or min_y > size.y + 200:
		return

	draw_polyline(screen_pts, color, thickness, true)
	if screen_pts.size() >= 2:
		var cap_r = max(1.0, thickness * 0.5)
		draw_circle(screen_pts[0], cap_r, color)
		draw_circle(screen_pts[screen_pts.size() - 1], cap_r, color)
	if debug_input and stroke == _active_stroke and screen_pts.size() > 0:
		draw_circle(screen_pts[screen_pts.size() - 1], 4.0, Color(0, 1, 0, 0.8))

# -----------------------------
# Coordinate transforms
# -----------------------------
func _screen_to_doc(screen_pos: Vector2) -> Vector2:
	# Convert to doc coords with x relative to page.
	var page_left = (size.x - page_width_px) * 0.5
	var x = clamp(screen_pos.x - page_left, side_margin_px, page_width_px - side_margin_px)
	var y = screen_pos.y + _scroll_y
	return Vector2(x, y)

func _smooth_screen_points(points: PackedVector2Array, window: int) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var w = max(3, window)
	if (w % 2) == 0:
		w += 1
	var half = w / 2
	var out = PackedVector2Array()
	out.resize(points.size())
	out[0] = points[0]
	out[points.size() - 1] = points[points.size() - 1]
	for i in range(1, points.size() - 1):
		var sum = Vector2.ZERO
		var count = 0
		for j in range(i - half, i + half + 1):
			if j < 0 or j >= points.size():
				continue
			sum += points[j]
			count += 1
		out[i] = sum / float(count)
	return out

func _get_erase_preview_pos() -> Variant:
	# Prefer the only finger pointer if present.
	for idx in _pointers.keys():
		var p = _pointers[idx]
		if not p.get("is_stylus", false):
			return p.get("pos", null)
	return null

# -----------------------------
# Undo/Redo internals
# -----------------------------
func _apply_undo(action: Dictionary) -> void:
	match action.get("type", ""):
		"add_stroke":
			var sid = action["stroke"]["id"]
			_remove_stroke_by_id(sid)
		"erase_strokes":
			# Restore erased strokes
			for s in action.get("strokes", []):
				strokes.append(s)
		_:
			pass
	_recompute_max_doc_y()

func _apply_redo(action: Dictionary) -> void:
	match action.get("type", ""):
		"add_stroke":
			strokes.append(action["stroke"])
		"erase_strokes":
			for s in action.get("strokes", []):
				_remove_stroke_by_id(s["id"])
		_:
			pass
	_recompute_max_doc_y()

func _remove_stroke_by_id(sid: String) -> void:
	for i in range(strokes.size() - 1, -1, -1):
		if str(strokes[i].get("id", "")) == sid:
			strokes.remove_at(i)
			return

func _recompute_max_doc_y() -> void:
	var maxy = 2000.0
	for s in strokes:
		var bbox: Rect2 = s.get("bbox", Rect2())
		if bbox.size != Vector2.ZERO:
			maxy = max(maxy, bbox.position.y + bbox.size.y + bottom_padding_px)
		else:
			var pts = s.get("points", [])
			for p in pts:
				maxy = max(maxy, float(p["y"]) + bottom_padding_px)
	_max_doc_y = maxy
	_scroll_y = _clamp_scroll(_scroll_y)

# -----------------------------
# Dirty flag
# -----------------------------
func _set_dirty(v: bool) -> void:
	if _dirty == v:
		return
	_dirty = v
	emit_signal("dirty_changed", _dirty)

# -----------------------------
# IDs
# -----------------------------
var _stroke_counter: int = 0
func _new_stroke_id() -> String:
	_stroke_counter += 1
	return "s_%06d" % _stroke_counter
