# NotebookPlus Raw Input Plugin (Android)

This module builds the Android raw input plugin used by the Godot demo. It captures MotionEvent data so the Godot side can distinguish stylus vs finger and read pressure/tilt.

## How it works
- The plugin hooks the Godot render view (or window decor view) with a touch listener.
- Every MotionEvent pointer is converted into a Dictionary with coordinates, tool type, pressure, tilt, and timing data.
- Events are buffered in memory (max 2048) until Godot polls them.

## Godot API (singleton: `NotebookPlusRawInput`)
- `poll_events()` returns buffered events and clears the buffer.
- `clear_events()` clears the buffer.
- `set_recording_enabled(enabled)` enables recording and clears when disabled.
- `set_active(enabled)` toggles active capture and clears the buffer.
- `is_recording_enabled()` returns the recording flag.
- `get_status()` returns a debug string with hook status.

## Build notes
- Requires JDK 17 (`src/gradle.properties` pins a local path).
- The plugin compiles against the local Godot Android template AAR:
  `demo/android/build/libs/debug/godot-lib.template_debug.aar`.
- Build from `src/`:
  `./gradlew :rawinput:assembleRelease`
- `build_rawinput.ps1` runs the build and copies the AAR to:
  `demo/addons/notebookplus_raw_input/bin/notebookplus_raw_input_v2.aar`.
