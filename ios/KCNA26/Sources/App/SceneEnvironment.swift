import SwiftUI

// Per-window (scene) objects the shell provides to the screens, besides the two @Observable
// ones injected with `.environment(_:)`:
//
//     @Environment(AppGraph.self) private var graph     // the process's graph (Kotlin LocalAppGraph)
//     @Environment(NavModel.self) private var nav        // this window's navigation (Kotlin NavViewModel)
//     @Environment(\.detailsScrollCarry) private var carry   // this window's DetailsScrollCarry

private struct DetailsScrollCarryKey: EnvironmentKey {
    static var defaultValue: DetailsScrollCarry? { nil }
}

extension EnvironmentValues {
    /// The window's ``DetailsScrollCarry`` (Kotlin: the activity-scoped holder of
    /// ui/session/DetailsScrollCarry.kt): carries the details scroll position across the swap
    /// between the compact sheet and the wide pane when the window's width class changes. One per
    /// scene, owned by the shell (``RootView``); nil outside it (previews).
    var detailsScrollCarry: DetailsScrollCarry? {
        get { self[DetailsScrollCarryKey.self] }
        set { self[DetailsScrollCarryKey.self] = newValue }
    }
}
