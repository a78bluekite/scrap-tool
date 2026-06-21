import SwiftUI

@main
struct ScrapApp: App {
    @StateObject private var store = ScrapStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
