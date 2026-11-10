import SwiftUI

// STUB (shell): replaced by the settings agent. Keep this signature.

/// Kotlin ui/settings/SettingsScreen.kt `SettingsScreen`: pushed on the navigation stack (the
/// system back button and edge swipe pop it; `onBack` is for an explicit back control).
///
/// - Parameter onBack: leave Settings (``NavModel/pop()``).
struct SettingsScreen: View {
    let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    var body: some View {
        Text(verbatim: "Settings")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
