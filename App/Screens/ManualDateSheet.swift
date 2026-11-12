import PhtofxrCore
import SwiftUI

/// Pick a date for one photo yourself: from the name, like the photo added just before it, or any date and
/// time. Works for every photo, also without a date in its name. The picked date counts as kept and goes to the
/// review like any proposal; nothing changes before that is confirmed.
struct ManualDateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: Classification
    @State private var date: Date

    init(item: Classification, initial: Date? = nil) {
        self.item = item
        _date = State(initialValue: initial ?? item.proposedDate ?? item.asset.creationDate ?? Date())
    }

    var body: some View {
        let nameDate = model.nameDate(of: item)
        let previous = model.previousPhotoDate(for: item.id)
        NavigationStack {
            Form {
                Section {
                    FilenameText(item: item)
                        .font(.headline)
                    if let current = item.asset.creationDate {
                        LabeledContent("In Photos now") {
                            Text(current.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                if nameDate != nil || previous != nil {
                    Section("Quick picks") {
                        if let nameDate {
                            Button {
                                date = nameDate
                            } label: {
                                LabeledContent("From the name") {
                                    MarkedDateText(date: nameDate)
                                }
                            }
                            .accessibilityIdentifier("pick.name")
                        }
                        if let previous {
                            Button {
                                date = previous.date
                            } label: {
                                LabeledContent {
                                    MarkedDateText(date: previous.date)
                                } label: {
                                    Text("Like the previous photo")
                                    if let filename = previous.filename {
                                        Text(verbatim: filename)
                                    }
                                }
                            }
                            .accessibilityIdentifier("pick.previous")
                        }
                    }
                    .tint(Color.primary)
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("datePicker")
                } footer: {
                    Text("The picked date counts as kept and goes to the review. Nothing changes until you confirm there.")
                }

                Section("New date") {
                    MarkedDateText(date: date, style: AssetDetailView.longStyle)
                        .accessibilityIdentifier("pickedDate")
                }
            }
            .navigationTitle("Change date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") {
                        model.setManualDate(date, for: item.id)
                        dismiss()
                    }
                    .disabled(isUnchanged)
                    .accessibilityIdentifier("saveDate")
                }
            }
            .environment(\.timeZone, model.timeZone)
        }
    }

    /// The date Photos already has is no change.
    private var isUnchanged: Bool {
        guard let current = item.asset.creationDate else { return false }
        return abs(date.timeIntervalSince(current)) < 1
    }
}
