import PhtofxrCore
import SwiftUI

/// The photos of one result section, grouped by the day they were added (one import, usually), biggest
/// import first. "To review" splits every import into its certain and uncertain proposals and offers keep and
/// skip per photo (swipe) and per group (header menu); the review button collects what was kept.
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
                            GroupHeader(group: group, category: .certain, items: group.certain, timeZone: model.timeZone)
                        }
                    }
                    if !group.uncertain.isEmpty {
                        Section {
                            rows(group.uncertain)
                        } header: {
                            GroupHeader(group: group, category: .uncertain, items: group.uncertain, timeZone: model.timeZone)
                        }
                    }
                } else {
                    Section {
                        rows(group.items)
                    } header: {
                        GroupHeader(group: group, category: nil, items: group.items, timeZone: model.timeZone)
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
        .toolbar {
            if section == .review {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Keep all certain proposals", systemImage: "checkmark.circle") {
                        model.keep(model.certainIDs)
                    }
                    .accessibilityIdentifier("keepAllCertain")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear choices", systemImage: "circle.dashed") {
                        model.unkeep(model.kept)
                    }
                    .disabled(model.kept.isEmpty)
                    .accessibilityIdentifier("clearChoices")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        model.isReviewing = true
                    } label: {
                        Text("Review \(model.kept.count) changes")
                            .bold()
                    }
                    .disabled(model.kept.isEmpty || model.isWorking)
                    .accessibilityIdentifier("openReview")
                }
            }
        }
        .accessibilityIdentifier("resultList")
    }

    private func rows(_ items: [Classification]) -> some View {
        ForEach(items) { item in
            ResultRow(item: item, isKept: model.isKept(item.id))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if item.category.isReviewable {
                        if model.isKept(item.id) {
                            Button("Undo keep", systemImage: "arrow.uturn.backward") { model.unkeep([item.id]) }
                        } else {
                            Button("Keep", systemImage: "checkmark") { model.keep([item.id]) }
                                .tint(.orange)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if item.category.isReviewable {
                        Button("Don't keep", systemImage: "xmark") { model.skip([item.id]) }
                            .tint(.gray)
                    } else if item.category == .skipped {
                        Button("Propose again", systemImage: "arrow.uturn.backward") { model.unskip([item.id]) }
                            .tint(.orange)
                    }
                }
                .accessibilityActions {
                    if item.category.isReviewable {
                        if model.isKept(item.id) {
                            Button("Undo keep") { model.unkeep([item.id]) }
                        } else {
                            Button("Keep") { model.keep([item.id]) }
                        }
                        Button("Don't keep") { model.skip([item.id]) }
                    } else if item.category == .skipped {
                        Button("Propose again") { model.unskip([item.id]) }
                    }
                }
        }
    }
}

private struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    let group: ImportGroup
    let category: DateCategory?
    let items: [Classification]
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
            Text(items.count, format: .number)
            if category != nil {
                Menu {
                    Button("Keep all \(items.count)", systemImage: "checkmark.circle") {
                        model.keep(items.map(\.id))
                    }
                    .accessibilityIdentifier("keepGroup")
                    Button("Don't keep all \(items.count)", systemImage: "xmark.circle") {
                        model.skip(items.map(\.id))
                    }
                    Button("Clear choices", systemImage: "circle") {
                        model.unkeep(items.map(\.id))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Text("Actions for this group"))
                }
                .accessibilityIdentifier("groupMenu")
            } else if items.first?.category == .skipped {
                Button("Propose all again") {
                    model.unskip(items.map(\.id))
                }
                .font(.footnote)
            }
        }
    }
}

private struct ResultRow: View {
    let item: Classification
    let isKept: Bool
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
            Spacer(minLength: 0)
            if isKept {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isKept ? Text("Kept") : Text(verbatim: ""))
        .accessibilityIdentifier("row.\(item.id)")
    }

    private var datesLine: String {
        let current = item.asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "no date")
        guard let proposed = item.proposedDate else { return current }
        return "\(current) → \(proposed.formatted(date: .abbreviated, time: .shortened))"
    }
}
