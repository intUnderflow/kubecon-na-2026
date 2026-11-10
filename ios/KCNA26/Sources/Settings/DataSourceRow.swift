import SwiftUI

/// Kotlin ui/settings/DataSourceRow.kt `DataSourceRow`: its own small Settings section,
/// "SCHEDULE DATA" (a heading), then "Updated Nov 8, 2:15 PM · Check now", with the source
/// (bundled or GitHub, plus "Checking…" / "Up to date" / when it was downloaded) underneath.
/// Failures are never shown: the row just stays as it was. Texts are Core's
/// ``DataSourceText``; "Check now" is `graph.dataSync.checkInBackground()`, disabled while a
/// check runs. Nothing until the data set is known. Padding around it is the caller's.
struct DataSourceRow: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init() {}

    var body: some View {
        let sync: DataSync = graph.dataSync
        if let active = sync.active {
            let status: SyncStatus = sync.status
            // Wall clock, like SyncStatus.lastCheckedAt (not the app clock, which may be faked).
            let source: String = DataSourceText.source(active.source, status, Date())
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(DataSourceText.HEADING)
                HStack(alignment: .center, spacing: 0) {
                    // Kotlin weight(1f, fill = false): wraps before the separator and button give way.
                    Text(verbatim: DataSourceText.updated(active.updatedAt, active.version))
                        .appTextStyle(type.small)
                        .foregroundStyle(colors.ink)
                    Text(verbatim: DataSourceText.SEPARATOR)
                        .appTextStyle(type.small)
                        .foregroundStyle(colors.muted)
                        .fixedSize()
                        .layoutPriority(1)
                    // Material TextButton: pink, muted while disabled, 8 pt in, 48 pt high.
                    Button {
                        _ = sync.checkInBackground()
                    } label: {
                        Text(verbatim: DataSourceText.CHECK_NOW)
                            .appTextStyle(type.button)
                            .foregroundStyle(status.checking ? colors.muted : colors.you)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(minHeight: CGFloat(Dimens.touchTarget))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(status.checking)
                    .fixedSize()
                    .layoutPriority(1)
                }
                .frame(minHeight: CGFloat(Dimens.touchTarget))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                Text(verbatim: source)
                    .appTextStyle(type.tiny)
                    .foregroundStyle(colors.muted)
                    // Kotlin's polite live region: VoiceOver says the new state when it changes.
                    .onChange(of: source) { _, text in
                        DirectionsAnnouncer.announce(text)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
