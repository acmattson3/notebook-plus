# NotebookPlus

NotebookPlus is a digital notebook for sermons and handwritten notes. The focus is fast capture now, with room for future OCR and indexing.

## How the app works
- Godot front end centered on an InkCanvas control for drawing and scrolling.
- Input model: stylus draws, finger erases, two-finger drag scrolls; desktop mouse mappings exist for development.
- Notes are stored as JSON with vector strokes in document coordinates; autosave runs from the editor.
- InkCanvas can rasterize strokes into a tile cache to speed redraws; the cache can optionally persist on disk.
- Android raw input plugin supplies MotionEvent data to distinguish stylus vs finger and capture pressure/tilt.

## Repo layout
- `demo/` Godot project (scenes, InkCanvas, menus, settings, addon wrapper).
- `src/` Android raw input plugin source and Gradle build.
- `<platform>-export/` and `<platform>_export/` export output directories.
- `build_rawinput.ps1` builds the Android plugin AAR and copies it into the Godot addon.
- `adb_install_run.ps1` installs and launches the Android APK.

## Quick start
- Open `demo/project.godot` in Godot 4.5 and run.
- For Android: run `build_rawinput.ps1`, export the APK via Godot, then install with `adb_install_run.ps1`.
