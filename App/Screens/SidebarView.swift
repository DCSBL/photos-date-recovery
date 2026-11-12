import PhtofxrCore
import SwiftUI
import UIKit

/// Before a scan: access and what to scan. After a scan: the result sections with their counts.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Binding var selection: ResultSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                accessRow
                ForEach([MediaKind.photo, .video, .screenshot], id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { model.settings.mediaKinds.contains(kind) },
                        set: { model.setMediaKind(kind, included: $0) }
                    ))
                    .disabled(model.isScanning)
                    .accessibilityIdentifier("kind.\(kind.rawValue)")
                }
                scanButton
            } header: {
                Text("Scan")
            } footer: {
                Text("Scanning only reads names and dates. Nothing changes in your library.")
            }

            if model.hasResults {
                Section {
                    ForEach(ResultSection.allCases) { section in
                        NavigationLink(value: section) {
                            LabeledContent {
                                Text(model.count(of: section), format: .number)
                                    .accessibilityIdentifier("count.\(section.rawValue)")
                            } label: {
                                Label(section.title, systemImage: section.systemImage)
                            }
                        }
                        .accessibilityIdentifier("section.\(section.rawValue)")
                    }
                } header: {
                    Text("Result")
                } footer: {
                    if model.resultsAreStale {
                        Text("Settings changed. Scan again to update the result.")
                    } else if let duration = model.lastScanDuration {
                        Text("Scanned in \(duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))).")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accessRow: some View {
        switch model.access {
        case .notDetermined:
            Text("Phtofxr asks for access to your photos when you start the first scan.")
                .foregroundStyle(.secondary)
        case .full:
            Label("Access to all photos", systemImage: "checkmark.circle")
        case .limited:
            VStack(alignment: .leading, spacing: 8) {
                Label("Access to selected photos only", systemImage: "circle.lefthalf.filled")
                Text("Only the photos you chose are scanned.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Change selection") { model.library.presentLimitedLibraryPicker() }
                    .accessibilityIdentifier("changeSelection")
            }
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Label("No access to your photos", systemImage: "xmark.circle")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    @ViewBuilder
    private var scanButton: some View {
        if case .scanning(let progress) = model.scanState {
            ProgressView(value: progress) {
                Text("Scanning…")
            }
            .accessibilityIdentifier("scanProgress")
        } else {
            Button {
                Task { await model.scan() }
            } label: {
                if model.hasResults {
                    Label("Scan again", systemImage: "arrow.clockwise")
                } else {
                    Label("Scan library", systemImage: "magnifyingglass")
                }
            }
            .disabled(model.settings.mediaKinds.isEmpty || model.access == .denied || model.access == .restricted)
            .accessibilityIdentifier("scan")
        }
    }
}
