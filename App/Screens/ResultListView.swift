import PhtofxrCore
import SwiftUI

/// The photos of one result section, grouped by the day they were added (one import, usually), biggest
/// import first. "To review" splits every import into its certain and uncertain proposals.
struct ResultListView: View {
    @Environment(AppModel.self) private var model
    let section: ResultSection
    @Binding var selection: Classification.ID?

    var body: some View {
        let groups = model.groups(in: section)
        List(selection: $selection) {
            ForEach(groups) { group in
                if section == .review {
                    if !group.certain.isEmpty {
                        Section {
                            rows(group.certain)
                        } header: {
                            GroupHeader(group: group, category: .certain, count: group.certain.count, timeZone: model.timeZone)
                        }
                    }
                    if !group.uncertain.isEmpty {
                        Section {
                            rows(group.uncertain)
                        } header: {
                            GroupHeader(group: group, category: .uncertain, count: group.uncertain.count, timeZone: model.timeZone)
                        }
                    }
                } else {
                    Section {
                        rows(group.items)
                    } header: {
                        GroupHeader(group: group, category: nil, count: group.items.count, timeZone: model.timeZone)
                    }
                }
            }
        }
        .navigationTitle(section.title)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: section.systemImage)
            }
        }
        .accessibilityIdentifier("resultList")
    }

    private func rows(_ items: [Classification]) -> some View {
        ForEach(items) { item in
            ResultRow(item: item)
        }
    }
}

private struct GroupHeader: View {
    let group: ImportGroup
    let category: DateCategory?
    let count: Int
    let timeZone: TimeZone

    var body: some View {
        HStack {
            if let date = group.day?.date(in: timeZone) {
                Text("Added \(date.formatted(.dateTime.day().month().year()))")
            } else {
                Text("Added on an unknown day")
            }
            if let category {
                Text(verbatim: "·")
                Text(category.title)
            }
            Spacer()
            Text(count, format: .number)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ResultRow: View {
    let item: Classification
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            // At the largest text sizes the name and dates need the whole width.
            if !dynamicTypeSize.isAccessibilitySize {
                Thumbnail(id: item.id, side: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.asset.filename ?? String(localized: "No filename"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(datesLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("row.\(item.id)")
    }

    private var datesLine: String {
        let current = item.asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "no date")
        guard let proposed = item.proposedDate else { return current }
        return "\(current) → \(proposed.formatted(date: .abbreviated, time: .shortened))"
    }
}
