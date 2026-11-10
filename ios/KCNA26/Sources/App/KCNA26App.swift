import SwiftUI

// Temporary entry point while the screens are ported: it loads the bundled data so the app
// target links and CI exercises the Core sources on iOS. Replaced by the real app shell.
@main
struct KCNA26App: App {
    var body: some Scene {
        WindowGroup {
            BootstrapView()
        }
    }
}

private struct BootstrapView: View {
    @State private var summary = "Loading…"

    var body: some View {
        Text(summary)
            .padding()
            .task {
                summary = await Task.detached(priority: .userInitiated) { () -> String in
                    do {
                        let repo = try Repository.bundled()
                        return "\(repo.sessions.count) sessions on \(repo.days.count) days"
                    } catch {
                        return "Couldn't load the schedule: \(error)"
                    }
                }.value
            }
    }
}
