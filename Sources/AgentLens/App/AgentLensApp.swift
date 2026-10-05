import SwiftUI

@main
struct AgentLensApp: App {
    var body: some Scene {
        WindowGroup("AgentLens") {
            ContentView()
        }
        .defaultSize(width: 1480, height: 920)
        .windowResizability(.contentSize)
    }
}
