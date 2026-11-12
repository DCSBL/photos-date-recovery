import PhtofxrCore
import SwiftUI

/// History as a sheet from the sidebar.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HistoryList()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            model.acknowledgeWork()
                            dismiss()
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("closeHistory")
                    }
                }
        }
        .interactiveDismissDisabled(model.isWorking)
    }
}

/// Every batch Phtofxr applied, newest first, each revertable on its own. Reverting restores the original date
/// and removes only the caption line Phtofxr added. Also pushed from the review screen after applying.
struct HistoryList: View {
    @Environment(AppModel.self) private var model
    @State private var pendingRevert: BatchSummary?

    var body: some View {
        List {
            switch model.workState {
            case .reverting(let done, let total):
                Section {
                    ProgressView(value: Double(done), total: Double(max(total, 1))) {
                        Text("Reverting…")
                    }
                }
            case .finished(let changed, _, true):
                Section {
                    Label("\(changed) dates reverted", systemImage: "arrow.uturn.backward.circle.fill")
                        .accessibilityIdentifier("revertDone")
                }
            default:
                EmptyView()
            }

            ForEach(model.journalState.batches) { batch in
                Section {
                    LabeledContent("Changed", value: batch.applied.formatted())
                    if batch.reverted > 0 {
                        LabeledContent("Reverted", value: batch.reverted.formatted())
                    }
                    if batch.failed > 0 {
                        LabeledContent("Not changed", value: batch.failed.formatted())
                    }
                    if batch.unresolved > 0 {
                        LabeledContent("Not checked yet", value: batch.unresolved.formatted())
                    }
                    if batch.isRevertable {
                        Button("Revert \(batch.applied) dates", systemImage: "arrow.uturn.backward", role: .destructive) {
                            pendingRevert = batch
                        }
                        .disabled(model.isWorking || model.isScanning)
                        .accessibilityIdentifier("revertBatch")
                    }
                } header: {
                    Text(batch.startedAt.formatted(date: .long, time: .shortened))
                }
            }
        }
        .overlay {
            if model.journalState.batches.isEmpty {
                ContentUnavailableView(
                    "Nothing changed yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Batches you apply appear here and can be reverted.")
                )
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Revert these dates?",
            isPresented: Binding(get: { pendingRevert != nil }, set: { if !$0 { pendingRevert = nil } }),
            titleVisibility: .visible,
            presenting: pendingRevert
        ) { batch in
            Button("Revert \(batch.applied) dates", role: .destructive) {
                Task { await model.revert(batch: batch.id) }
            }
            .accessibilityIdentifier("confirmRevert")
        } message: { _ in
            Text("The photos get their previous date back and Phtofxr's caption line is removed. iOS asks for permission first.")
        }
    }
}
