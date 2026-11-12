import PhtofxrCore
import SwiftUI

/// The last stop before anything changes: what will change per import, the caption choice, and one explicit
/// button. iOS then asks for permission itself. Nothing is written without both.
struct ApplyReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        let changes = model.plannedChanges
        NavigationStack {
            Form {
                switch model.workState {
                case .applying(let done, let total):
                    Section {
                        ProgressView(value: Double(done), total: Double(max(total, 1))) {
                            Text("Changing dates…")
                        }
                        .accessibilityIdentifier("applyProgress")
                    }
                case .finished(let changed, let failed, _):
                    resultSection(changed: changed, failed: failed)
                case .failed(let message):
                    Section {
                        Label("Nothing was changed", systemImage: "exclamationmark.triangle")
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("applyFailed")
                case .idle, .reverting:
                    reviewSections(changes: changes, addsCaption: $model.addsCaption)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.acknowledgeWork()
                        dismiss()
                    } label: {
                        Text(isDone ? LocalizedStringKey("Done") : LocalizedStringKey("Cancel"))
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("closeReview")
                }
            }
            .interactiveDismissDisabled(model.isWorking)
        }
    }

    private var isDone: Bool {
        switch model.workState {
        case .finished, .failed: true
        default: false
        }
    }

    @ViewBuilder
    private func reviewSections(changes: [PlannedChange], addsCaption: Binding<Bool>) -> some View {
        Section {
            Text("\(changes.count) photos get a new date.")
                .font(.headline)
            Text("Only the date taken changes. The date added stays as it is, so the original import date is never lost.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("Per import") {
            ForEach(ChangePlanner.summary(of: changes, timeZone: model.timeZone)) { summary in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if let date = summary.day?.date(in: model.timeZone) {
                            Text("Added \(date.formatted(.dateTime.day().month().year()))")
                        } else {
                            Text("Added on an unknown day")
                        }
                        Spacer()
                        Text(summary.count, format: .number)
                    }
                    Text("New dates from \(summary.earliest.formatted(date: .abbreviated, time: .omitted)) to \(summary.latest.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }

        Section {
            Toggle("Put the original date in the caption", isOn: addsCaption)
                .accessibilityIdentifier("captionToggle")
        } footer: {
            if let example = changes.first.flatMap(model.captionLine(for:)) {
                Text("For example: \(example)")
            }
        }

        Section {
            Button {
                Task { await model.applyKept() }
            } label: {
                Text("Change \(changes.count) dates")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .disabled(changes.isEmpty || model.isWorking)
            .accessibilityIdentifier("applyChanges")
        } footer: {
            Text("iOS asks for your permission next. Everything can be reverted under History.")
        }
    }

    @ViewBuilder
    private func resultSection(changed: Int, failed: Int) -> some View {
        Section {
            Label("\(changed) dates changed", systemImage: "checkmark.circle.fill")
                .accessibilityIdentifier("applyDone")
            if failed > 0 {
                Label("\(failed) not changed", systemImage: "exclamationmark.triangle")
            }
        } footer: {
            Text("You can revert this batch under History.")
        }
    }
}
