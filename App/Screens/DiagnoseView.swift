import PhtofxrCore
import SwiftUI

/// Checks the PhotoKit assumptions on the real library (PLAN.md §8): are the filenames and added dates there
/// for every photo, and do the photo's name and its file's name agree (on a sample, because reading file
/// names is slow). Read-only. Mainly useful once, on a new device or iOS version.
struct DiagnoseView: View {
    @Environment(AppModel.self) private var model
    @State private var report: DiagnosticsReport?
    @State private var progress: Double?

    /// Photos whose file names are compared; enough to spot a pattern, quick even in a large library.
    static let sampleSize = 500
    /// Sample rows shown; the counts above cover the whole sample.
    static let shownSamples = 50

    var body: some View {
        List {
            Section {
                if let progress {
                    ProgressView(value: progress) {
                        Text("Checking…")
                    }
                    .accessibilityIdentifier("diagnosticsProgress")
                } else {
                    Button {
                        Task { await run() }
                    } label: {
                        Label("Run diagnostics", systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("runDiagnostics")
                }
            } footer: {
                Text("Checks every photo for a filename and an added date, and compares the photo's name with its file's name on \(Self.sampleSize) photos spread over the library. Takes about as long as a scan. Changes nothing.")
            }

            if let report {
                Section("Library") {
                    LabeledContent("Items") { Text(report.total, format: .number) }
                        .accessibilityIdentifier("diagnostics.total")
                    LabeledContent("Without asset filename") { Text(report.missingAssetFilename, format: .number) }
                    LabeledContent("Without added date") { Text(report.missingAddedDate, format: .number) }
                    LabeledContent("Read in", value: report.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                    if let scan = model.lastScanDuration {
                        LabeledContent("Last scan", value: scan.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                    }
                }

                Section {
                    LabeledContent("Photos compared") { Text(report.sampleSize, format: .number) }
                    LabeledContent("Without resource filename") { Text(report.missingResourceFilename, format: .number) }
                    LabeledContent("Asset and resource name differ") { Text(report.differentFilenames, format: .number) }
                } header: {
                    Text("Sample")
                }

                Section {
                    ForEach(report.samples.prefix(Self.shownSamples)) { sample in
                        SampleRow(sample: sample)
                    }
                } header: {
                    Text("Examples")
                }
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func run() async {
        if model.access == .notDetermined { model.access = await model.library.requestAccess() }
        guard model.access.canScan else { return }
        progress = 0
        report = await model.library.diagnostics(sampleSize: Self.sampleSize) { fraction in
            // A late update must not bring the bar back after the report arrived.
            Task { @MainActor in if progress != nil { progress = fraction } }
        }
        progress = nil
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
