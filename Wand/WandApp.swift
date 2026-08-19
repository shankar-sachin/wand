import SwiftUI

@main
struct WandApp: App {
    @State private var store = DeviceStore()
    @State private var connections = ConnectionManager()
    @AppStorage("wand.appearance") private var appearance = AppearanceMode.system
    @AppStorage("wand.haptics") private var hapticsEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(connections)
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    // Connect before any view asks for it, so the very first press on a
                    // cold launch is as fast as every press after it.
                    Haptics.shared.enabled = hapticsEnabled
                    connections.attach(to: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    connections.scenePhaseChanged(to: phase)
                }
        }
    }
}
