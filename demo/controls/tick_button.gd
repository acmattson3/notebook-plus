extends Control
class_name TickButton

@export var value: int = 0
@export var max_value: int = 10
@export var min_value: int = 0
@export var step_size: int = 1

@onready var _value_label: Label = %ValueLabel

signal value_changed(value: int)

func _ready() -> void:
	_value_label.text = str(value)

func _on_button_up_pressed() -> void:
	if value >= max_value:
		value = max_value
		return
	value += step_size
	_value_label.text = str(value)
	value_changed.emit(value)

func _on_button_down_pressed() -> void:
	if value <= min_value:
		value = min_value
		return
	value -= step_size
	_value_label.text = str(value)
	value_changed.emit(value)
