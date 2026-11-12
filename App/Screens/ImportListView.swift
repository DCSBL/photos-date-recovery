import PhtofxrCore
import SwiftUI

/// The imports in one result section: photos added on the same day, biggest import first. "To review" shows
/// how many proposals are certain and uncertain and how many are kept, and keeps a whole import in one go.
struct ImportListView: View {
    @Environment(AppModel.self) private var model
    let section: ResultSection
    @Binding var selection: ImportGroup.ID?

    var body: some View {
        let groups = model.groups(in: section)
        List(selection: $selection) {
            Section {
                ForEach(groups) { group in
                    NavigationLink(value: group.id) {
                        ImportRow(group: group, section: section)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if section == .review, !group.certain.isEmpty {
                            Button("Keep certain", systemImage: "checkmark") {
                                model.keep(group.certain.map(\.id))
                            }
                            .tint(.orange)
                        }
                    }
                    .contextMenu {
                        ImportActions(group: group, section: section)
                    }
                    .accessibilityIdentifier("import.\(group.id)")
                }
            } footer: {
                if section == .review, !groups.isEmpty {
                    Text("Swipe an import to keep all its certain proposals, or tap it to see the photos.")
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: section.systemImage)
            }
        }
        .navigationTitle(section.title)
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
            }
            ToolbarItem(placement: .bottomBar) {
                ReviewButton()
            }
        }
        .accessibilityIdentifier("importList")
    }
}

/// The bottom bar button that opens the review: every kept proposal and picked date, from any section.
struct ReviewButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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

/// Keep, don't keep or clear a whole import (or part of it), from a context menu or a section header.
struct ImportActions: View {
    @Environment(AppModel.self) private var model
    let group: ImportGroup
    let section: ResultSection

    var body: some View {
        if section == .review {
            let certain = group.certain.map(\.id)
            let all = group.items.map(\.id)
            if !certain.isEmpty {
                Button("Keep \(certain.count) certain", systemImage: "checkmark.circle") { model.keep(certain) }
            }
            Button("Keep all \(all.count)", systemImage: "checkmark.circle.fill") { model.keep(all) }
            Button("Don't keep all \(all.count)", systemImage: "xmark.circle") { model.skip(all) }
            Button("Clear choices", systemImage: "circle") { model.unkeep(all) }
        } else if section == .skipped {
            Button("Propose all again", systemImage: "arrow.uturn.backward") { model.unskip(group.items.map(\.id)) }
        }
    }
}

private struct ImportRow: View {
    @Environment(AppModel.self) private var model
    let group: ImportGroup
    let section: ResultSection

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                if let date = group.day?.date(in: model.timeZone) {
                    Text("Added \(date.formatted(.dateTime.day().month().year()))")
                        .font(.headline)
                } else {
                    Text("Added on an unknown day")
                        .font(.headline)
                }
                Spacer()
                Text(group.items.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            if section == .review {
                Text(reviewLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let range = newDatesRange {
                Text("New dates \(range)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reviewLine: String {
        let kept = group.items.reduce(0) { $0 + (model.isKept($1.id) ? 1 : 0) }
        return String(localized: "\(group.certain.count) certain · \(group.uncertain.count) uncertain · \(kept) kept")
    }

    /// "2009 – 2015": the years the proposals point to.
    private var newDatesRange: String? {
        guard section == .review || section == .skipped else { return nil }
        let dates = group.items.compactMap { model.targetDate(of: $0) }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let style = Date.FormatStyle.dateTime.year()
        let from = first.formatted(style)
        let to = last.formatted(style)
        return from == to ? from : "\(from) – \(to)"
    }
}
