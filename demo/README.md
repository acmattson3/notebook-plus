# NotebookPlus (Godot Demo)

NotebookPlus is a Godot 4.5 project targeting Android. The MVP is a notepage editor with an InkCanvas drawing surface and a main menu that lists saved pages. An Android raw input plugin provides MotionEvent data for stylus/finger differentiation.

## Scope
- Godot front end with a custom InkCanvas control.
- Android focus, with desktop mouse mappings for development.
- Vector stroke storage with autosave and a simple main menu.
- Optional tile cache for faster redraws.

## MVP Features
- Android stylus draw, finger erase, two finger scroll.
- Desktop mapping: left drag draws, right drag erases, middle drag or Shift+left drag scrolls.
- Vector stroke storage in document coordinates.
- Undo and redo for last stroke or erase action.
- Autosave about every 30 seconds from Notepage.
- Main menu list with open, delete, duplicate.
- Sorting by title, date created, date modified.
- Eraser preview circle that follows the finger while erasing.
- Optional stroke smoothing and round end caps.
- Tile cache rasterization for faster redraws (configurable tile size).
- Settings menu for UI scale and tile size; debug tile overlay toggle.

## Input Policy
- Stylus draws and finger erases.
- Two fingers drag to scroll.
- Palm rejection lite: ignore new finger touches while a stylus stroke is active.
- Android raw input: MotionEvent tool type/tilt/pressure used to distinguish stylus vs finger.

## InkCanvas Behavior
- Control-based, renders in `_draw()`.
- Strokes stored in document coordinates with y growing downward.
- Rendering converts doc to screen by subtracting `scroll_y`.
- Single tap produces a dot as a single-point stroke.
- Axis-aligned simplification runs on commit to compress straight segments into endpoints.
- Whole-stroke eraser uses bbox quick reject and segment distance hit tests.
- Tile cache can rasterize strokes into textures for faster redraws.
- Optional disk-backed tile cache (`user://tile_cache`).
- Optional smoothing (`stroke_smoothing_enabled` / `stroke_smoothing_window`).

## Data Model
Notes are stored as JSON with an id, metadata, page state, and strokes. Bounding boxes are computed at runtime and are not stored.

Autosave target is `user://notes/<id>.json`.

```json
{
  "id": "note_1700000000_89abcdef",
  "title": "Sunday AM",
  "created": 1700000000,
  "modified": 1700000123,
  "page": {
    "width_px": 1600,
    "scroll_y_px": 240
  },
  "strokes": [
    {
      "id": "s_000001",
      "tool": "pen",
      "color": "#ffffff",
      "thickness": 6.0,
      "points": [
        {"x":120, "y":80, "p":0.4, "t":1700000001.1},
        {"x":140, "y":80, "p":0.5, "t":1700000001.2},
        {"x":140, "y":120, "p":0.5, "t":1700000001.3},
        {"x":120, "y":120, "p":0.5, "t":1700000001.4},
        {"x":120, "y":80, "p":0.5, "t":1700000001.5}
      ]
    }
  ]
}
```

## Settings and Cache
- Settings live at `user://settings.json` (tile size and UI scale).
- Tile cache is stored under `user://tile_cache/<note_id>/<tile_size>/` when disk caching is enabled.

## Time Handling
- Timestamps are stored as Unix seconds in the JSON.
- Main menu display uses local time and applies the system timezone bias.
- Display format is `YYYY-MM-DD HH:MM am/pm`.

## Scene Layout
- `MainMenu` is the list view.
- `Notepage` is the editor root with a TopBar and InkCanvas.
- `SettingsMenu` lives in Notepage and disables raw input while visible.
- InkCanvas handles its own scrolling and does not use ScrollContainer.

## Main Menu
- `NotepageButtonVBox` is populated from `user://notes`.
- Each notepage row is a `NotepageButton` instance.
- Long press reveals options for delete and duplicate.
- Title sorting defaults to ascending on first click.
- Date sorting defaults to descending on first click.

## InkCanvas API
Signals
- `dirty_changed(is_dirty: bool)`
- `stroke_committed(stroke_id: String)`
- `strokes_changed()`
- `touch_state_changed(state: Dictionary)`

Functions
- `set_pen_color(c: Color)`
- `set_pen_thickness(t: float)`
- `set_eraser_radius(r: float)`
- `set_cache_note_id(note_id: String)`
- `reset_input_state()`
- `undo()`
- `redo()`
- `clear_all()`
- `load_from_note_data(note: Dictionary)`
- `get_note_data() -> Dictionary`
- `set_scroll_y(y: float)`
- `get_scroll_y() -> float`
- `set_raw_input_active(active: bool)`

Dirty means the canvas has unsaved changes.

## Android Raw Input Plugin (Godot Side)
The raw input plugin lives in `src/` and builds an AAR that is packaged into the project as a v2 Android plugin.

Files and locations:
- Android plugin source: `src/rawinput/`
- Addon wrapper: `demo/addons/notebookplus_raw_input/`
- Built AAR (not committed): `demo/addons/notebookplus_raw_input/bin/notebookplus_raw_input_v2.aar`

Build and install flow:
1) Build plugin AAR and copy into addon:
```
.\build_rawinput.ps1
```
2) Export APK in Godot (Android preset, Gradle build enabled). APK is written to:
- `android-export/NotebookPlus.apk`
3) Install/run on device:
```
.\adb_install_run.ps1
```

Notes:
- `build_rawinput.ps1` and `adb_install_run.ps1` use absolute Windows paths; update them if your repo path differs.
- `demo/android/build/gradle.properties` and `src/gradle.properties` pin a local JDK path; update if your JDK lives elsewhere.

Enable the plugin in Godot:
- Project Settings -> Plugins -> `NotebookPlusRawInput`

The plugin exposes a singleton:
- `Engine.get_singleton("NotebookPlusRawInput")`
- Methods: `poll_events()`, `clear_events()`, `set_recording_enabled()`, `set_active()`, `get_status()`

## Known Bugs
- Raw input carryover: drawing on the MainMenu background, then opening/creating a notepage can inject those strokes into the notepage (sometimes after a delay, now undoable). Repro: draw on MainMenu blank space, tap New Notepage or open an existing note.
- Mitigations attempted: clear raw input buffer on scene swap, short input lockout on InkCanvas, ignore raw events before notepage open timestamp, require a fresh DOWN before accepting raw input, and disable raw input recording while in MainMenu.

## Manual Test Checklist
- Desktop: left drag draws a stroke.
- Desktop: right drag erases a whole stroke.
- Desktop: middle drag or Shift plus left drag scrolls.
- Desktop: tap produces a dot.
- Android: stylus draws, single finger erases.
- Android: two finger drag scrolls without drawing.
- Android: raw input plugin shows MotionEvent data and distinguishes stylus vs finger.
- Undo and redo work for last add or erase.
- Main menu sort buttons toggle ascending and descending.
- Duplicate creates a new note with updated created and modified times.
- Tile size setting updates cache and redraws.
- UI scale setting updates the UI scale factor.

## Roadmap
- Tile cache improvements (disk cache tuning, capsule raster experiments).
- Partial stroke eraser.
- SVG and PDF export.
- Photo import.
- SAF folder picker for user accessible storage.
- Server or MQTT backup.
- Text and OCR pipeline.
- Cross reference and backlinking.
