package app.kcna26

import app.kcna26.data.Repository
import app.kcna26.time.FixedClock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.io.File

/**
 * Shared test fixtures (owner: foundation). Unit tests run with app/ as the
 * working directory, so the bundled JSON is read from src/main/assets.
 *
 * ```
 * val repo = TestData.repo                     // parsed once per test JVM
 * val clock = TestData.clockAt("2026-11-11T09:00:00-07:00")
 * val routes = TestData.vectors.routes         // test_vectors.json, typed
 * ```
 */
object TestData {
    /** app/src/main/assets (also works when run from the Gradle root). */
    val assetsDir: File by lazy {
        listOf(File("src/main/assets"), File("app/src/main/assets"))
            .firstOrNull { File(it, Repository.SCHEDULE).isFile }
            ?: error("Can't find src/main/assets from ${File(".").absolutePath}")
    }

    /** The real Repository, loaded from the asset files. */
    val repo: Repository by lazy { Repository.fromDirectory(assetsDir) }

    /** test_vectors.json, typed. */
    val vectors: TestVectors by lazy {
        Repository.json.decodeFromString(TestVectors.serializer(), File(assetsDir, Repository.TEST_VECTORS).readText())
    }

    /** Raw text of an asset file, e.g. `TestData.text("wayfinding.json")`. */
    fun text(name: String): String = File(assetsDir, name).readText()

    /**
     * How many sessions schedule.json holds, read from the file itself so the tests keep passing
     * when a data update adds or removes sessions.
     */
    val scheduleCount: Int by lazy {
        Repository.json.parseToJsonElement(text(Repository.SCHEDULE)).jsonObject.getValue("sessions").jsonArray.size
    }

    /** How many entries details.json holds (see [scheduleCount]). */
    val detailsCount: Int by lazy { Repository.json.parseToJsonElement(text(Repository.DETAILS)).jsonObject.size }

    /** A clock frozen at an ISO time ("2026-11-11T09:00:00-07:00" or Denver local "2026-11-11T09:00"). */
    fun clockAt(iso: String): FixedClock = FixedClock.parse(iso)
}

/** test_vectors.json. Distances ±3 m, bearings ±2°. */
@Serializable
data class TestVectors(
    @SerialName("_about") val about: String = "",
    val compass: List<CompassVector> = emptyList(),
    val arrowRotation: List<ArrowVector> = emptyList(),
    val trueHeading: String = "",
    val routes: List<RouteVector> = emptyList(),
)

@Serializable
data class CompassVector(
    val where: String,
    val lat: Double,
    val lng: Double,
    val room: String,
    val roomLevel: Int,
    val expectDistanceM: Double,
    val expectBearingTrueDeg: Double,
    val myLocationStart: StartVector,
)

/** mode "inside" (node) or "outside" (entrance, node, distanceM, bearingDeg). */
@Serializable
data class StartVector(
    val mode: String,
    val node: String,
    val entrance: String? = null,
    val distanceM: Double? = null,
    val bearingDeg: Double? = null,
)

@Serializable
data class ArrowVector(
    val trueHeadingDeg: Double,
    val bearingDeg: Double,
    val arrowDeg: Double,
    val note: String? = null,
)

/** from: entrance key or room code; to: room code. */
@Serializable
data class RouteVector(
    val from: String,
    val to: String,
    val steps: List<StepVector>,
    val totalM: Double,
    val levelsChanged: Int,
)

/** kind: "start", "walk", "up", "down", "end" (StepKind.wire). */
@Serializable
data class StepVector(val kind: String, val text: String)
