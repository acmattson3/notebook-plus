extends Control
class_name TickButton

@export var value: int = 0
@export var max_value: int = 10
@export var min_value: int = 0
@export var step_size: int = 1

signal value_changed(value)

func _ready():
	%ValueLabel.text = str(value)

func _on_button_up_pressed():
	if value >= max_value:
		value = max_value
		return
	value += step_size
	%ValueLabel.text = str(value)
	value_changed.emit(value)

func _on_button_down_pressed():
	if value <= min_value:
		value = min_value
		return
	value -= step_size
	%ValueLabel.text = str(value)
	value_changed.emit(value)
