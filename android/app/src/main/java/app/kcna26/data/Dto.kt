package app.kcna26.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/*
 * Wire-format mirrors of the asset JSON files. Internal: everything else uses
 * the domain models in Models.kt. Unknown keys are ignored and missing fields
 * fall back to the defaults below (rooms.json OFF has only name/buildingLabel).
 */

@Serializable
internal data class ScheduleFileDto(
    @SerialName("_about") val about: String = "",
    val timeZone: String = "America/Denver",
    val me: String = "Lucy Sweet",
    val anthropicSpeakers: List<String> = emptyList(),
    val days: List<DayDto> = emptyList(),
    val categories: Map<String, CategoryDto> = emptyMap(),
    val fieldNotes: Map<String, String> = emptyMap(),
    val sessions: List<SessionDto> = emptyList(),
)

@Serializable
internal data class DayDto(
    val key: String,
    val date: String,
    val label: String,
    val short: String,
    val subtitle: String = "",
)

@Serializable
internal data class CategoryDto(val label: String, val colorLight: String, val colorDark: String)

@Serializable
internal data class GroupDto(val key: String, val title: String)

@Serializable
internal data class SessionDto(
    val id: String,
    val event: String,
    val day: String,
    val start: String,
    val end: String? = null,
    val endIsEstimate: Boolean = false,
    val room: String,
    val title: String,
    val speakers: List<String> = emptyList(),
    val note: String? = null,
    val category: String,
    val group: GroupDto? = null,
    val isMine: Boolean = false,
    val hasAnthropicSpeaker: Boolean = false,
    val officialUrl: String = "",
    val description: String? = null,
    val slidesUrl: String? = null,
    /** Optional (unconference sessions): the GitHub discussion with the proposal and replies. */
    val discussionUrl: String? = null,
    // colocated.json only (all optional): see its fieldNotes.
    val coloEvent: String? = null,
    val coloEvents: List<String> = emptyList(),
    val format: String? = null,
    val level: String? = null,
    val sponsored: Boolean = false,
    val topic: String? = null,
)

/**
 * colocated.json (its descriptions are in colocated_details.json: [ColocatedDetailsDto]).
 * Its sessions are shaped like schedule.json's; its rooms like rooms.json's.
 */
@Serializable
internal data class ColocatedFileDto(
    @SerialName("_about") val about: String = "",
    val timeZone: String = "America/Denver",
    val anthropicSpeakers: List<String> = emptyList(),
    val fieldNotes: Map<String, String> = emptyMap(),
    val events: List<ColoEventDto> = emptyList(),
    val sessions: List<SessionDto> = emptyList(),
    val rooms: Map<String, RoomDto> = emptyMap(),
)

/** colocated_details.json: "details", the same shape as details.json (read lazily). */
@Serializable
internal data class ColocatedDetailsDto(val details: Map<String, DetailDto> = emptyMap())

@Serializable
internal data class ColoEventDto(
    val key: String,
    val name: String,
    val mainRoom: String,
    val rooms: List<String> = emptyList(),
    val start: String,
    val end: String,
    val halfDay: Boolean = false,
    val talkCount: Int = 0,
    val supersedes: String? = null,
    val infoUrl: String? = null,
    val pageUrl: String? = null,
    val passNote: String? = null,
)

@Serializable
internal data class RoomsFileDto(val rooms: Map<String, RoomDto> = emptyMap())

@Serializable
internal data class RoomDto(
    val name: String,
    val buildingLabel: String? = null,
    val venue: String? = null,
    val venueCode: String? = null,
    val level: Int? = null,
    val lat: Double? = null,
    val lng: Double? = null,
    val x: Double? = null,
    val y: Double? = null,
    val whereText: String? = null,
    val attachNode: String? = null,
    val finalStep: String? = null,
)

@Serializable
internal data class WayfindingFileDto(
    val origin: OriginDto,
    val magneticDeclination: String = "",
    val routing: RoutingDto,
    val entrances: Map<String, EntranceDto>,
    val nodes: Map<String, NodeDto>,
    val edges: List<EdgeDto>,
)

@Serializable
internal data class OriginDto(
    val lat0: Double,
    val lon0: Double,
    val metersPerDegLat: Double,
    val metersPerDegLon: Double,
)

@Serializable
internal data class RoutingDto(
    val algorithm: String = "",
    val roomAttach: String = "",
    val startText: String = "",
    val lowerConcourseMerge: MergeDto,
    val distanceSuffix: String = "",
    val summary: String = "",
    val stepKinds: String = "",
)

@Serializable
internal data class MergeDto(
    val nodes: List<String>,
    val rule: String = "",
    val where: Map<String, String>,
)

@Serializable
internal data class EntranceDto(val name: String, val node: String)

@Serializable
internal data class NodeDto(
    val name: String,
    val x: Double,
    val y: Double,
    val level: Int,
    val building: String,
)

@Serializable
internal data class EdgeDto(val a: String, val b: String, val textAB: String, val textBA: String)

@Serializable
internal data class VenueFileDto(
    val buildings: Map<String, BuildingDto> = emptyMap(),
    val streets: List<StreetDto> = emptyList(),
    val zones: List<ZoneDto> = emptyList(),
)

@Serializable
internal data class BuildingDto(val name: String, val outline: List<List<Double>>)

@Serializable
internal data class StreetDto(val name: String, val from: List<Double>, val to: List<Double>)

@Serializable
internal data class ZoneDto(val name: String, val x0: Double, val x1: Double, val y0: Double, val y1: Double)

@Serializable
internal data class DetailDto(
    val description: String = "",
    val speakers: List<SpeakerDto> = emptyList(),
)

@Serializable
internal data class SpeakerDto(val name: String, val tagline: String = "")

@Serializable
internal data class SummitDetailDto(
    val d: String = "",
    val slides: String? = null,
    val link: String? = null,
    val linkText: String? = null,
)
