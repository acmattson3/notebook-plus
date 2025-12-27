# NotebookPlus

NotebookPlus is a digital notebook for sermons and handwritten notes. The long term goal is fast capture with future OCR and AI indexing.

## Scope
NotebookPlus is a Godot 4.5 project targeting Android. The MVP is a notepage editor with an InkCanvas drawing surface and a main menu that lists saved pages. The project now includes an Android raw input plugin (v2 AAR) to capture MotionEvent data for stylus/finger differentiation.

## MVP Features
- Android stylus draw, finger erase, two finger scroll
- Desktop mouse mapping for development
- Vector stroke storage in document coordinates
- Undo and redo for last stroke or erase action
- Autosave about every 30 seconds from Notepage
- Dark mode only, portrait only
- Main menu list with open, delete, duplicate
- Sorting by title, date created, date modified
- Raw Android MotionEvent sampling via v2 plugin (pressure, tilt, tool type)
- Eraser preview circle that follows the finger while erasing
- Optional stroke smoothing and round end caps

## Input Policy
- Stylus draws and finger erases
- Two fingers drag to scroll
- Palm rejection lite: ignore new finger touches while a stylus stroke is active
- Desktop mapping: left drag draws, right drag erases, middle drag or Shift plus left drag scrolls
- Android raw input: MotionEvent tool type/tilt/pressure used to distinguish stylus vs finger

## InkCanvas Behavior
- Control based, renders in `_draw()` with `draw_polyline()`
- Strokes stored in document coordinates with y growing downward
- Rendering converts doc to screen by subtracting `scroll_y`
- Single tap produces a dot as a single point stroke
- Axis aligned simplification runs on commit to compress straight horizontal or vertical segments into endpoints
- Whole stroke eraser uses bbox quick reject and distance to segment hit test
- Debugging: set `debug_input = true` to print event info and show a tiny overlay in debug builds
- Raw input is converted from screen coordinates into InkCanvas local coordinates
- Optional smoothing (`stroke_smoothing_enabled` and `stroke_smoothing_window`) and round end caps

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

## Time Handling
- Timestamps are stored as Unix seconds in the JSON.
- Main menu display uses local time and applies the system timezone bias.
- Display format is `YYYY-MM-DD HH:MM am/pm`.

## Scene Layout
- `MainMenu` is the list view
- `Notepage` is the editor root with a TopBar and InkCanvas
- InkCanvas handles its own scrolling and does not use ScrollContainer

## Main Menu
- `NotepageButtonVBox` is populated from `user://notes`
- Each notepage row is a `NotepageButton` instance
- Long press reveals options for delete and duplicate
- Title sorting defaults to ascending on first click
- Date sorting defaults to descending on first click

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
- `undo()`
- `redo()`
- `clear_all()`
- `load_from_note_data(note: Dictionary)`
- `get_note_data() -> Dictionary`
- `set_scroll_y(y: float)`
- `get_scroll_y() -> float`

Dirty means the canvas has unsaved changes.

## Android Raw Input Plugin
The raw input plugin lives in `src/` and builds an AAR that is packaged into the project as a v2 Android plugin.

Files and locations:
- Android plugin source: `src/rawinput/`
- Addon wrapper: `demo/addons/notebookplus_raw_input/`
- Built AAR (not committed): `demo/addons/notebookplus_raw_input/bin/notebookplus_raw_input.aar`

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

Enable the plugin in Godot:
- Project Settings -> Plugins -> `NotebookPlusRawInput`

The plugin exposes a singleton:
- `Engine.get_singleton("NotebookPlusRawInput")`
- Methods: `poll_events()`, `clear_events()`, `get_status()`

## Manual Test Checklist
- Desktop: left drag draws a stroke
- Desktop: right drag erases a whole stroke
- Desktop: middle drag or Shift plus left drag scrolls
- Desktop: tap produces a dot
- Android: stylus draws, single finger erases
- Android: two finger drag scrolls without drawing
- Android: raw input plugin shows MotionEvent data and distinguishes stylus vs finger
- Undo and redo work for last add or erase
- Main menu sort buttons toggle ascending and descending
- Duplicate creates a new note with updated created and modified times

## Roadmap
- Stroke caching to texture for faster redraw
- Partial stroke eraser
- SVG and PDF export
- Photo import
- SAF folder picker for user accessible storage
- Server or MQTT backup
- Text and OCR pipeline
- Cross reference and backlinking
