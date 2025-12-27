@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "NotebookPlusRawInput"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray(["res://addons/notebookplus_raw_input/bin/notebookplus_raw_input.aar"])
