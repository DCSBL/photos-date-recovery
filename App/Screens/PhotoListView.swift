import PhtofxrCore
import SwiftUI

/// Opens one photo in the detail stack.
struct PhotoRoute: Hashable {
    let id: Classification.ID
}

/// The photos of one import as a list with everything needed to decide: the filename with its date parts
/// marked, the date in Photos, the date it would get, and why. "To review" splits the import into certain and
/// uncertain; swipe a photo to keep or skip it, or open it to pick another date.
struct PhotoListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let section: ResultSection
    let importID: ImportGroup.ID
    /// The import whose list has been built. Big imports (thousands of photos) take a moment to lay out on the
    /// main actor, so they show a spinner first instead of a screen that seems to ignore the tap.
    @State private var shownImport: String?

    /// Up to this many photos the list appears at once; above it the spinner shows first.
    static let instantLimit = 1500

    var body: some View {
        let group = model.group(id: importID, in: section)
        let count = group?.items.count ?? 0
        let key = "\(section.rawValue)/\(importID)"
        Group {
            if let group, shownImport == key || count < Self.instantLimit {
                list(group)
            } else if group != nil {
                // The system spinner keeps turning while the list is built.
                ProgressView {
                    Text("Loading \(count) photos…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("listLoading")
            } else {
                ContentUnavailableView("Nothing here", systemImage: section.systemImage)
            }
        }
        .navigationTitle(title(group))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) {
            guard shownImport != key else { return }
            // Give the spinner a frame on screen before the list is built.
            try? await Task.sleep(for: .milliseconds(50))
            shownImport = key
        }
        .toolbar {
            // Side by side the import list already shows this button.
            if sizeClass == .compact {
                ToolbarItem(placement: .bottomBar) {
                    ReviewButton()
                }
            }
        }
    }

    private func title(_ group: ImportGroup?) -> String {
        guard let date = group?.day?.date(in: model.timeZone) else { return section.title }
        return date.formatted(.dateTime.day().month().year())
    }

    private func list(_ group: ImportGroup) -> some View {
        List {
            if section == .review {
                if !group.certain.isEmpty {
                    Section {
                        rows(group.certain)
                    } header: {
                        PartHeader(category: .certain, items: group.certain)
                    }
                }
                if !group.uncertain.isEmpty {
                    Section {
                        rows(group.uncertain)
                    } header: {
                        PartHeader(category: .uncertain, items: group.uncertain)
                    }
                }
            } else {
                Section {
                    rows(group.items)
                } footer: {
                    if section == .noDateInName || section == .suspicious {
                        Text("Open a photo to pick its date yourself.")
                    }
                }
            }
        }
        .accessibilityIdentifier("photoList")
    }

    private func rows(_ items: [Classification]) -> some View {
        ForEach(items) { item in
            NavigationLink(value: PhotoRoute(id: item.id)) {
                PhotoRow(item: item, isKept: model.isKept(item.id), manualDate: model.manualDates[item.id])
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if item.category.isReviewable || model.manualDates[item.id] != nil {
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

/// "Certain · 480" with keep and skip for that part of the import.
private struct PartHeader: View {
    @Environment(AppModel.self) private var model
    let category: DateCategory
    let items: [Classification]

    var body: some View {
        HStack {
            Text(category.title)
            Spacer()
            Text(items.count, format: .number)
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
        }
    }
}

/// One photo: thumbnail, marked filename, current → new date, and the reason in a few words.
private struct PhotoRow: View {
    let item: Classification
    let isKept: Bool
    let manualDate: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            // At the largest text sizes the name and dates need the whole width.
            if !dynamicTypeSize.isAccessibilitySize {
                Thumbnail(id: item.id, side: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                FilenameText(item: item)
                    .lineLimit(1)
                    .truncationMode(.middle)
                datesLine
                    .font(.subheadline)
                Text(reasonLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isKept {
                Image(systemName: manualDate == nil ? "checkmark.circle.fill" : "calendar.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(keptValue)
        .accessibilityIdentifier("row.\(item.id)")
    }

    @ViewBuilder
    private var datesLine: some View {
        let current = item.asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "no date")
        if let target = manualDate ?? item.proposedDate {
            // Wraps below the current date when the row is narrow or the text is large.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(current).foregroundStyle(.secondary)
                    Text(verbatim: "→").foregroundStyle(.secondary)
                    MarkedDateText(date: target)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(current).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(verbatim: "→").foregroundStyle(.secondary)
                        MarkedDateText(date: target)
                    }
                }
            }
        } else {
            Text(current).foregroundStyle(.secondary)
        }
    }

    private var reasonLine: String {
        if manualDate != nil {
            return String(localized: "Date picked by you")
        }
        let reason = item.reasons.first { $0 != .skippedByUser }
        guard let reason, item.category != .noDateInName else { return item.category.title }
        return "\(item.category.title) · \(reason.shortLabel)"
    }

    private var keptValue: Text {
        guard isKept else { return Text(verbatim: "") }
        return manualDate == nil ? Text("Kept") : Text("Kept with a date you picked")
    }
}
