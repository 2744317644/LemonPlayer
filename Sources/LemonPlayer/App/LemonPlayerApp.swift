import SwiftUI

@main
@MainActor
struct LemonPlayerApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
