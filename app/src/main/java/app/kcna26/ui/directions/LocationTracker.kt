package app.kcna26.ui.directions

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Fused location at high accuracy, every second (min 1 s, max delivery delay 2 s), only between
 * [start] and [stop] (the screen's onStart/onStop). Both are idempotent. Callbacks arrive on the
 * main thread. Never throws: a missing permission or Play services failure calls [onFailure].
 */
internal class LocationTracker(
    context: Context,
    private val onLocation: (Location) -> Unit,
    private val onAvailability: (Boolean) -> Unit,
    private val onFailure: () -> Unit,
) {
    private val appContext = context.applicationContext
    private val client by lazy { LocationServices.getFusedLocationProviderClient(appContext) }
    private val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, INTERVAL_MS)
        .setMinUpdateIntervalMillis(INTERVAL_MS)
        .setMaxUpdateDelayMillis(MAX_DELAY_MS)
        .build()
    private var started = false

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            if (!started) return
            result.lastLocation?.let(onLocation)
        }

        override fun onLocationAvailability(availability: LocationAvailability) {
            if (!started) return
            onAvailability(availability.isLocationAvailable)
        }
    }

    @SuppressLint("MissingPermission")
    fun start() {
        if (started) return
        if (!hasLocationPermission(appContext)) {
            onFailure()
            return
        }
        started = true
        try {
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
                .addOnFailureListener { e ->
                    Log.w(TAG, "location updates failed", e)
                    if (started) onFailure()
                }
        } catch (e: SecurityException) {
            started = false
            onFailure()
        } catch (e: RuntimeException) {
            Log.w(TAG, "location updates unavailable", e)
            started = false
            onFailure()
        }
    }

    fun stop() {
        if (!started) return
        started = false
        runCatching { client.removeLocationUpdates(callback) }
    }

    companion object {
        private const val TAG = "KcnaLocation"
        const val INTERVAL_MS = 1000L
        const val MAX_DELAY_MS = 2000L

        val PERMISSIONS = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

        /** Fine or approximate location is granted. */
        fun hasLocationPermission(context: Context): Boolean = PERMISSIONS.any {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }

        /** Device-wide location switch. */
        fun isLocationEnabled(context: Context): Boolean {
            val lm = context.getSystemService(LocationManager::class.java) ?: return true
            return runCatching { LocationManagerCompat.isLocationEnabled(lm) }.getOrDefault(true)
        }
    }
}
