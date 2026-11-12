import PhtofxrCore
import SwiftUI

/// Sidebar (scan and results), imports of a section, and the photos of an import with each photo pushed on
/// top. Collapses into one stack on a narrow window (iPhone, folded iPhone Duo) and shows columns side by side
/// when there is room: the layout follows the window, not the device.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: ResultSection?
    @State private var selectedImport: ImportGroup.ID?
    @State private var photoPath: [PhotoRoute] = []
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
                ImportListView(section: section, selection: $selectedImport)
            } else {
                ContentUnavailableView(
                    "Scan your library",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Phtofxr compares the date in each filename with the date in Photos.")
                )
            }
        } detail: {
            NavigationStack(path: $photoPath) {
                Group {
                    if let section, let selectedImport {
                        PhotoListView(section: section, importID: selectedImport)
                    } else {
                        ContentUnavailableView("No import selected", systemImage: "square.stack")
                    }
                }
                .navigationDestination(for: PhotoRoute.self) { route in
                    AssetDetailView(id: route.id)
                }
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
            selectedImport = nil
            photoPath = []
        }
        .onChange(of: selectedImport) {
            photoPath = []
        }
        .onChange(of: scenePhase) {
            // Permission can change in Settings while the app is in the background.
            if scenePhase == .active { model.refreshAccess() }
        }
    }
}
