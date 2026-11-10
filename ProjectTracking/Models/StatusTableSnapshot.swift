import Foundation

nonisolated enum StatusRowsFilter: String, CaseIterable, Identifiable {
    case all, blockers, missing
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "Все проекты"; case .blockers: "С блокерами"; case .missing: "Без записи за выбранный день" }
    }
}

nonisolated struct StatusTableCell: Sendable {
    let entry: DailyStatus?
    let summary: String
    var hasBlockers: Bool { entry?.blockers.nilIfBlank != nil }
    var isEmpty: Bool { entry == nil || (entry?.editableMarkdown.nilIfBlank == nil && entry?.blockers.nilIfBlank == nil) }

    init(entry: DailyStatus?) {
        self.entry = entry
        if let entry {
            // A bounded plain-text excerpt avoids building Markdown views in every table cell.
            summary = Self.excerpt(entry.editableMarkdown)
        } else { summary = "" }
    }
    private static func excerpt(_ source: String) -> String {
        let lines = String(source.prefix(600)).components(separatedBy: .newlines).map { line -> String in
            var value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("#") { value = String(value.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces) }
            if value.hasPrefix("- [ ] ") { value = "☐ " + value.dropFirst(6) }
            else if value.lowercased().hasPrefix("- [x] ") { value = "☑ " + value.dropFirst(6) }
            else if value.hasPrefix("- ") { value = "• " + value.dropFirst(2) }
            value = value.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            return value.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        }
        return String(lines.joined(separator: "\n").prefix(500))
    }

}

nonisolated struct StatusTableRow: Identifiable, Sendable {
    var id: UUID { project.id }
    let project: Project
    let cells: [Date: StatusTableCell]
    let searchableText: String
}

nonisolated struct StatusTableSnapshot: Sendable {
    let days: [Date]
    let rows: [StatusTableRow]
    let selectedDay: Date

    init(projects: [Project], endingOn date: Date, dayCount: Int, calendar: Calendar = .current) {
        let last = calendar.startOfDay(for: date)
        let days = (0..<max(1, min(dayCount, 7))).compactMap { calendar.date(byAdding: .day, value: -$0, to: last) }
        self.selectedDay = last
        self.days = days
        self.rows = projects.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { project in
            var entries: [Date: DailyStatus] = [:]
            for entry in project.statuses {
                let day = calendar.startOfDay(for: entry.date)
                if entries[day] == nil { entries[day] = entry }
            }
            let cells = Dictionary(uniqueKeysWithValues: days.map { ($0, StatusTableCell(entry: entries[$0])) })
            let text = ([project.title] + days.compactMap { entries[$0].map { $0.editableMarkdown + "\n" + $0.blockers } }).joined(separator: "\n")
            return StatusTableRow(project: project, cells: cells, searchableText: text)
        }
    }

    func filtered(query: String, filter: StatusRowsFilter, selectedDayOnly: Bool = false) -> [StatusTableRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            let text = selectedDayOnly
                ? row.project.title + "\n" + (row.cells[selectedDay]?.entry?.editableMarkdown ?? "") + "\n" + (row.cells[selectedDay]?.entry?.blockers ?? "")
                : row.searchableText
            guard needle.isEmpty || text.localizedCaseInsensitiveContains(needle) else { return false }
            switch filter {
            case .all: return true
            case .blockers: return selectedDayOnly ? row.cells[selectedDay]?.hasBlockers == true : row.cells.values.contains(where: \.hasBlockers)
            case .missing: return row.cells[selectedDay]?.isEmpty != false
            }
        }
    }
}
