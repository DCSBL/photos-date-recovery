import PhtofxrCore
import SwiftUI

/// Checks the PhotoKit assumptions on the real library (PLAN.md §8): are the filenames there, do the asset
/// and resource names agree, is the added date set, and how long does reading everything take. Read-only.
struct DiagnoseView: View {
    @Environment(AppModel.self) private var model
    @State private var report: DiagnosticsReport?
    @State private var isRunning = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await run() }
                } label: {
                    Label("Run diagnostics", systemImage: "stethoscope")
                }
                .disabled(isRunning)
                .accessibilityIdentifier("runDiagnostics")
                if isRunning {
                    ProgressView()
                }
            } footer: {
                Text("Reads the names and dates of every item in your library. Changes nothing.")
            }

            if let report {
                Section("Library") {
                    LabeledContent("Items") { Text(report.total, format: .number) }
                        .accessibilityIdentifier("diagnostics.total")
                    LabeledContent("Without asset filename") { Text(report.missingAssetFilename, format: .number) }
                    LabeledContent("Without resource filename") { Text(report.missingResourceFilename, format: .number) }
                    LabeledContent("Asset and resource name differ") { Text(report.differentFilenames, format: .number) }
                    LabeledContent("Without added date") { Text(report.missingAddedDate, format: .number) }
                    LabeledContent("Read in", value: report.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                    if let scan = model.lastScanDuration {
                        LabeledContent("Last scan", value: scan.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                    }
                }

                Section("Sample") {
                    ForEach(report.samples) { sample in
                        SampleRow(sample: sample)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func run() async {
        if model.access == .notDetermined { model.access = await model.library.requestAccess() }
        guard model.access.canScan else { return }
        isRunning = true
        report = await model.library.diagnostics(sampleSize: 50)
        isRunning = false
    }
}

private struct SampleRow: View {
    let sample: AssetDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: sample.assetFilename ?? "–")
                .font(.headline)
            ForEach(sample.resourceFilenames, id: \.self) { name in
                Text(verbatim: name)
            }
            Text("Created: \(format(sample.creationDate))")
            Text("Added: \(format(sample.addedDate))")
            Text("Modified: \(format(sample.modificationDate))")
            if let caption = sample.caption, !caption.isEmpty {
                Text("Caption: \(caption)")
            }
        }
        .font(.footnote)
        .textSelection(.enabled)
    }

    private func format(_ date: Date?) -> String {
        date?.formatted(date: .numeric, time: .standard) ?? "–"
    }
}
