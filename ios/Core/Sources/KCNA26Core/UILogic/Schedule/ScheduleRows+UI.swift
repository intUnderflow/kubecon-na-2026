import Foundation

/// One pinned section of the SwiftUI schedule list: the Kotlin LazyColumn's flat rows, where a
/// `stickyHeader` (``ScheduleRow/sticky``) stays pinned until the next one, become
/// `Section { rows } header: { header }` inside `LazyVStack(pinnedViews: [.sectionHeaders])`.
/// A sticky heading pins while any row after it (up to the next sticky heading) is visible, so a
/// section holds every row from its heading to the next one: the "Up next" line belongs to the
/// block above it, the empty state and the footer to the last block.
struct ScheduleRowSection: Sendable, Hashable {
    /// The pinned heading (``ScheduleRow/section(key:title:)`` or ``ScheduleRow/slotHead(_:)``);
    /// nil for the rows above the first heading (search box, banner, day heading, ...).
    let header: ScheduleRow?
    /// The rows under the heading, in list order (never sticky).
    let rows: [ScheduleRow]

    /// `ForEach` identity: the heading's key, or ``ScheduleRows/TOP_SECTION_ID``.
    var id: String { header?.key ?? ScheduleRows.TOP_SECTION_ID }
}

extension ScheduleRows {
    /// Identity of the section above the first sticky heading (no row key is "top").
    static let TOP_SECTION_ID = "top"

    /// Splits `rows` (``build(_:_:_:_:_:goingNext:empty:)``) at every sticky row. The rows before
    /// the first sticky one form a header-less section (left out when there are none);
    /// concatenating each section's header and rows gives `rows` back.
    static func sections(_ rows: [ScheduleRow]) -> [ScheduleRowSection] {
        var out: [ScheduleRowSection] = []
        var header: ScheduleRow? = nil
        var current: [ScheduleRow] = []
        var started = false
        for row in rows {
            if row.sticky {
                if started || !current.isEmpty {
                    out.append(ScheduleRowSection(header: header, rows: current))
                }
                header = row
                current = []
                started = true
            } else {
                current.append(row)
            }
        }
        if started || !current.isEmpty {
            out.append(ScheduleRowSection(header: header, rows: current))
        }
        return out
    }
}
