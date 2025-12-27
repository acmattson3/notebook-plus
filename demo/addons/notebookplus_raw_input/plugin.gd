@tool
extends EditorPlugin

var _export_plugin := preload("res://addons/notebookplus_raw_input/export_plugin.gd").new()

func _enter_tree() -> void:
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
