package app.kcna26.ui.directions

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.View

/**
 * The compass behind the map's heading cone: TYPE_ROTATION_VECTOR remapped for the rotation of
 * the display the activity is on *now* (fold/unfold moves the activity between the cover and the
 * inner display, whose panel is mounted rotated), plus the accuracy of TYPE_MAGNETIC_FIELD and of
 * the rotation vector for the figure-8 hint.
 *
 * Lifecycle: call [start] when the screen becomes visible and [stop] when it stops. Both are
 * idempotent, so a recreated activity never double-registers and a stopped one leaks nothing.
 * Callbacks arrive on the main thread.
 *
 * @param onAzimuth magnetic heading of the top of the phone as the user sees the screen, degrees
 *   [0, 360), with the display id and Surface.ROTATION_* it was computed for.
 * @param onAccuracy (Sensor.TYPE_*, SensorManager.SENSOR_STATUS_*) whenever an accuracy changes.
 */
internal class CompassSensor(
    context: Context,
    private val view: View,
    private val onAzimuth: (magneticDeg: Double, displayId: Int, rotation: Int, timeMs: Long) -> Unit,
    private val onAccuracy: (sensorType: Int, accuracy: Int) -> Unit,
) : SensorEventListener, DisplayManager.DisplayListener {

    private val activity: Activity? = context.findActivity()
    private val sensorManager: SensorManager? = context.getSystemService(SensorManager::class.java)
    private val displayManager: DisplayManager? = context.getSystemService(DisplayManager::class.java)
    private val rotationVector: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val magnetometer: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var started = false
    private var lastRvAccuracy = Int.MIN_VALUE
    private var lastMagAccuracy = Int.MIN_VALUE

    /** Id of the display the activity is on (re-read on display and configuration changes). */
    var displayId: Int = Display.DEFAULT_DISPLAY
        private set

    /** Surface.ROTATION_* of that display. */
    var rotation: Int = CompassMath.ROTATION_0
        private set

    fun start() {
        if (started) return
        started = true
        refreshDisplay()
        displayManager?.registerDisplayListener(this, mainHandler)
        val sm = sensorManager ?: return
        rotationVector?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
        // Only for its accuracy (the rotation vector already fuses the magnetometer).
        magnetometer?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
    }

    fun stop() {
        if (!started) return
        started = false
        sensorManager?.unregisterListener(this)
        displayManager?.unregisterDisplayListener(this)
    }

    /** Re-reads the current display and its rotation. Cheap; call on configuration changes too. */
    fun refreshDisplay() {
        val d = currentDisplay() ?: return
        val id = d.displayId
        val rot = d.rotation
        if (id != displayId || rot != rotation) {
            Log.d(TAG, "display changed: id=$id rotation=$rot (${CompassMath.rotationDegrees(rot)}°)")
        }
        displayId = id
        rotation = rot
    }

    private fun currentDisplay(): Display? =
        view.display ?: runCatching { activity?.display }.getOrNull()

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                if (event.accuracy != lastRvAccuracy) {
                    lastRvAccuracy = event.accuracy
                    onAccuracy(Sensor.TYPE_ROTATION_VECTOR, event.accuracy)
                }
                val az = CompassMath.azimuthDeg(event.values, rotation) ?: return
                onAzimuth(az, displayId, rotation, event.timestamp / 1_000_000L)
            }
            Sensor.TYPE_MAGNETIC_FIELD -> if (event.accuracy != lastMagAccuracy) {
                lastMagAccuracy = event.accuracy
                onAccuracy(Sensor.TYPE_MAGNETIC_FIELD, event.accuracy)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        when (sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> lastRvAccuracy = accuracy
            Sensor.TYPE_MAGNETIC_FIELD -> lastMagAccuracy = accuracy
            else -> return
        }
        onAccuracy(sensor.type, accuracy)
    }

    override fun onDisplayAdded(displayId: Int) = refreshDisplay()

    override fun onDisplayRemoved(displayId: Int) = refreshDisplay()

    override fun onDisplayChanged(displayId: Int) = refreshDisplay()

    companion object {
        const val TAG = "KcnaCompass"
    }
}

internal tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
