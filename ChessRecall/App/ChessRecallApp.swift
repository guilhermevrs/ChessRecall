import SwiftUI

@main
struct ChessRecallApp: App {
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MOCK_LICHESS"] == "1" {
            LichessAPIMock.register()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
        }
    }
}
