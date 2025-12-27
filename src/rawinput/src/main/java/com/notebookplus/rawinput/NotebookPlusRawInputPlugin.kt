package com.notebookplus.rawinput

import android.app.Activity
import android.view.MotionEvent
import android.view.View
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.util.ArrayDeque

class NotebookPlusRawInputPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        private const val PLUGIN_NAME = "NotebookPlusRawInput"
        private const val MAX_BUFFER = 2048
    }

    private val lock = Any()
    private val buffer: ArrayDeque<Dictionary> = ArrayDeque(MAX_BUFFER)
    @Volatile private var hookStatus: String = "uninitialized"
    @Volatile private var hookViewName: String = "none"
    @Volatile private var recordingEnabled: Boolean = true

    override fun getPluginName(): String = PLUGIN_NAME

    override fun onMainCreate(activity: Activity?): View? {
        super.onMainCreate(activity)
        hookInputView()
        return null
    }

    override fun onGodotSetupCompleted() {
        super.onGodotSetupCompleted()
        hookInputView()
    }

    override fun onMainResume() {
        super.onMainResume()
        hookInputView()
    }

    private fun hookInputView() {
        val a = godot.getActivity() ?: return
        a.runOnUiThread {
            val renderView = godot.renderView as? View
            val root = a.window?.decorView

            val target: View? = renderView ?: root
            if (target == null) {
                hookStatus = "no_view"
                hookViewName = "none"
                return@runOnUiThread
            }

            target.isClickable = true
            target.isFocusable = true
            target.isFocusableInTouchMode = true
            target.setOnTouchListener { _, ev ->
                record(ev)
                false
            }
            hookStatus = "hooked"
            hookViewName = target.javaClass.name
        }
    }

    private fun record(ev: MotionEvent) {
        if (!recordingEnabled) {
            return
        }
        val actionIndex = ev.actionIndex
        val actionMasked = ev.actionMasked
        val eventTime = ev.eventTime
        val pointerCount = ev.pointerCount

        for (i in 0 until pointerCount) {
            val map = Dictionary()
            map["t_ms"] = eventTime
            map["action"] = actionMasked
            map["action_index"] = actionIndex
            map["is_action_index"] = (i == actionIndex)
            map["pointer_index"] = i
            map["pointer_id"] = ev.getPointerId(i)
            map["tool"] = ev.getToolType(i)
            map["x"] = ev.getX(i).toDouble()
            map["y"] = ev.getY(i).toDouble()
            map["pressure"] = ev.getPressure(i).toDouble()
            map["size"] = ev.getSize(i).toDouble()
            map["touch_major"] = ev.getTouchMajor(i).toDouble()
            map["touch_minor"] = ev.getTouchMinor(i).toDouble()
            map["tool_major"] = ev.getToolMajor(i).toDouble()
            map["tool_minor"] = ev.getToolMinor(i).toDouble()
            map["orientation"] = ev.getOrientation(i).toDouble()
            map["tilt"] = ev.getAxisValue(MotionEvent.AXIS_TILT, i).toDouble()
            map["distance"] = ev.getAxisValue(MotionEvent.AXIS_DISTANCE, i).toDouble()
            map["button_state"] = ev.buttonState
            map["meta_state"] = ev.metaState
            map["edge_flags"] = ev.edgeFlags

            synchronized(lock) {
                if (buffer.size >= MAX_BUFFER) {
                    buffer.removeFirst()
                }
                buffer.addLast(map)
            }
        }
    }

    @UsedByGodot
    fun poll_events(): Array<Any> {
        synchronized(lock) {
            val out = buffer.toTypedArray() as Array<Any>
            buffer.clear()
            return out
        }
    }

    @UsedByGodot
    fun clear_events() {
        synchronized(lock) {
            buffer.clear()
        }
    }

    @UsedByGodot
    fun set_recording_enabled(enabled: Boolean) {
        recordingEnabled = enabled
        if (!enabled) {
            clear_events()
        }
    }

    @UsedByGodot
    fun is_recording_enabled(): Boolean {
        return recordingEnabled
    }

    @UsedByGodot
    fun get_status(): String {
        return "$hookStatus:$hookViewName:rec=$recordingEnabled"
    }
}
