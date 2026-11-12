import PhtofxrCore
import SwiftUI

/// One photo: the filename with its date parts marked, what Photos says now, what it would become and why, and
/// the choice: keep, don't keep, or pick another date.
struct AssetDetailView: View {
    @Environment(AppModel.self) private var model
    let id: Classification.ID
    @State private var picksDate = false

    var body: some View {
        if let item = model.item(id: id) {
            content(item)
        } else {
            ContentUnavailableView("Photo not found", systemImage: "photo")
        }
    }

    private func content(_ item: Classification) -> some View {
        let manual = model.manualDates[item.id]
        return Form {
            Section {
                HStack {
                    Spacer()
                    Thumbnail(id: item.id, side: 200)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                FilenameText(item: item)
                    .font(.title3)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("filename")
                if let name = item.filenameDate,
                   let format = FilenameFormat.catalog.first(where: { $0.id == name.formatID }) {
                    LabeledContent("Recognized as", value: format.displayName)
                    if !name.hasTime {
                        Text("The name has no time of day, so the current time is kept.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Filename")
            } footer: {
                if item.filenameDate?.spans.isEmpty == false {
                    DatePartLegend()
                }
            }

            Section("Dates") {
                if let manual {
                    LabeledContent("Picked by you") {
                        MarkedDateText(date: manual, style: Self.longStyle)
                    }
                    .accessibilityIdentifier("manualDate")
                }
                if let proposed = item.proposedDate {
                    LabeledContent("Proposed") {
                        MarkedDateText(date: proposed, style: Self.longStyle)
                    }
                    .accessibilityIdentifier("proposedDate")
                }
                LabeledContent("In Photos now") {
                    dateText(item.asset.creationDate)
                }
                if let target = manual ?? item.proposedDate, let current = item.asset.creationDate {
                    LabeledContent("Difference", value: differenceText(target.timeIntervalSince(current)))
                }
                LabeledContent("Added to the library") {
                    dateText(item.asset.addedDate)
                }
            }

            choiceSection(item, manual: manual)

            Section("Why") {
                LabeledContent("Category", value: item.category.title)
                ForEach(item.reasons, id: \.self) { reason in
                    Text(reason.explanation)
                }
            }
        }
        .navigationTitle(item.asset.filename ?? String(localized: "Photo"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picksDate) {
            ManualDateSheet(item: item, initial: model.manualDates[item.id])
        }
    }

    @ViewBuilder
    private func choiceSection(_ item: Classification, manual: Date?) -> some View {
        Section {
            if item.category == .changedByApp {
                Text("Phtofxr already changed this date. Revert it under History to change it again.")
                    .foregroundStyle(.secondary)
            } else if item.category == .skipped {
                Button("Propose again", systemImage: "arrow.uturn.backward") {
                    model.unskip([item.id])
                }
            } else if model.isKept(item.id) {
                Group {
                    if manual == nil {
                        Label("Kept: applied after you review and confirm", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Date picked: applied after you review and confirm", systemImage: "calendar.circle.fill")
                    }
                }
                .accessibilityIdentifier("keptLabel")
                Button {
                    model.unkeep([item.id])
                } label: {
                    if manual == nil {
                        Label("Undo keep", systemImage: "arrow.uturn.backward")
                    } else {
                        Label("Remove picked date", systemImage: "arrow.uturn.backward")
                    }
                }
                .accessibilityIdentifier("undoKeep")
            } else if item.category.isReviewable {
                Button("Keep this proposal", systemImage: "checkmark.circle") {
                    model.keep([item.id])
                }
                .accessibilityIdentifier("keepItem")
                Button("Don't keep", systemImage: "xmark.circle") {
                    model.skip([item.id])
                }
                .accessibilityIdentifier("skipItem")
            }
            if model.canPickDate(for: item.id) {
                Button {
                    picksDate = true
                } label: {
                    if manual == nil {
                        Label("Other date…", systemImage: "calendar")
                    } else {
                        Label("Change picked date…", systemImage: "calendar")
                    }
                }
                .accessibilityIdentifier("otherDate")
            }
        } header: {
            Text("Your choice")
        }
    }

    private func dateText(_ date: Date?) -> Text {
        guard let date else { return Text("Unknown") }
        return Text(date.formatted(Self.longStyle))
    }

    static let longStyle = Date.FormatStyle(date: .long, time: .standard)
}
