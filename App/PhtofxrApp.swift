import SwiftUI

@main
struct PhtofxrApp: App {
    @State private var model = AppModel.forLaunch()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(.orange)
        }
    }
}
