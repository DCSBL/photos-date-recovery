import PhtofxrCore
import SwiftUI

/// Sidebar (scan and results), list (photos per import) and detail. Collapses into one stack on a narrow
/// window (iPhone, folded iPhone Duo) and shows columns side by side when there is room: the layout follows
/// the window, not the device.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: ResultSection?
    @State private var selectedItem: Classification.ID?
    @State private var showsSettings = false
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(selection: $section)
                .navigationTitle("Phtofxr")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("History", systemImage: "clock.arrow.circlepath") { model.isShowingHistory = true }
                            .accessibilityIdentifier("history")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { showsSettings = true }
                            .accessibilityIdentifier("settings")
                    }
                }
        } content: {
            if let section {
                ResultListView(section: section, selection: $selectedItem)
            } else {
                ContentUnavailableView(
                    "Scan your library",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Phtofxr compares the date in each filename with the date in Photos.")
                )
            }
        } detail: {
            if let selectedItem, let item = model.item(id: selectedItem) {
                AssetDetailView(item: item)
            } else {
                ContentUnavailableView("No photo selected", systemImage: "photo")
            }
        }
        // Where the window is wide enough (unfolded iPhone Duo, iPad) the scan controls stay visible next to the list.
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: Binding(get: { model.isReviewing }, set: { model.isReviewing = $0 })) {
            ApplyReviewView()
        }
        .sheet(isPresented: Binding(get: { model.isShowingHistory }, set: { model.isShowingHistory = $0 })) {
            HistoryView()
        }
        .onChange(of: section) {
            selectedItem = nil
        }
        .onChange(of: scenePhase) {
            // Permission can change in Settings while the app is in the background.
            if scenePhase == .active { model.refreshAccess() }
        }
    }
}
