import SwiftUI

@main
struct DisplayTunerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Display Tuner", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 880, minHeight: 640)
        }
        .defaultSize(width: 1080, height: 820)

        MenuBarExtra("Display Tuner", systemImage: "dial.medium") {
            MenuBarView()
                .environmentObject(model)
        }
    }
}
