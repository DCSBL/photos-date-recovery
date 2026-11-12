import PhtofxrCore
import SwiftUI

/// One photo: what Photos says now, what the filename says, and why the scan put it where it is.
struct AssetDetailView: View {
    let item: Classification

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Thumbnail(id: item.id, side: 240)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Dates") {
                LabeledContent("In Photos now") {
                    dateText(item.asset.creationDate)
                }
                if let proposed = item.proposedDate {
                    LabeledContent("Proposed") {
                        dateText(proposed)
                    }
                    .accessibilityIdentifier("proposedDate")
                }
                if let difference = item.difference {
                    LabeledContent("Difference", value: differenceText(difference))
                }
                LabeledContent("Added to the library") {
                    dateText(item.asset.addedDate)
                }
            }

            Section("Filename") {
                LabeledContent("Name", value: item.asset.filename ?? String(localized: "No filename"))
                if let name = item.filenameDate,
                   let format = FilenameFormat.catalog.first(where: { $0.id == name.formatID }) {
                    LabeledContent("Recognized as", value: format.displayName)
                    if !name.hasTime {
                        Text("The name has no time of day, so the current time is kept.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Why") {
                LabeledContent("Category", value: item.category.title)
                ForEach(item.reasons, id: \.self) { reason in
                    Text(reason.explanation)
                }
            }
        }
        .navigationTitle(item.asset.filename ?? String(localized: "Photo"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dateText(_ date: Date?) -> Text {
        guard let date else { return Text("Unknown") }
        return Text(date.formatted(date: .long, time: .standard))
    }
}
