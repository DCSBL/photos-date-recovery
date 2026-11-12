import SwiftUI

@main
struct PhtofxrApp: App {
    @State private var model = AppModel.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.orange)
        }
    }
}

/// Passes the system's Differentiate Without Color on to the date marks; `-phtofxrWithoutColor` forces it for
/// screenshots.
private struct RootView: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private static let forcesWithoutColor = ProcessInfo.processInfo.arguments.contains("-phtofxrWithoutColor")

    var body: some View {
        ContentView()
            .environment(\.marksDatePartsWithoutColor, differentiateWithoutColor || Self.forcesWithoutColor)
    }
}
