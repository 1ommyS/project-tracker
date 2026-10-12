import Foundation

enum ProjectState: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned, active, blocked, onHold = "on-hold", done, archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: "Запланирован"
        case .active: "В работе"
        case .blocked: "Заблокирован"
        case .onHold: "На паузе"
        case .done: "Завершён"
        case .archived: "В архиве"
        }
    }

    var symbol: String {
        switch self {
        case .planned: "circle.dashed"
        case .active: "bolt.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .onHold: "pause.circle.fill"
        case .done: "checkmark.circle.fill"
        case .archived: "archivebox.fill"
        }
    }

    var isActive: Bool { self != .archived && self != .done }
}

struct ProjectTask: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var isDone: Bool
    var dueDate: Date? = nil

    var notificationID: String { "pulseboard.task.\(id.uuidString)" }
}

struct DailyStatus: Identifiable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var projectTitle: String
    var date: Date
    var state: ProjectState
    var completed: String
    var plans: String
    var blockers: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var fileURL: URL?

    var searchableText: String {
        [projectTitle, state.title, completed, plans, blockers, notes].joined(separator: "\n")
    }
}

struct Project: Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var epic: String = ""
    var parentProject: String = ""
    var summary: String
    var tags: [String]
    var state: ProjectState
    var tasks: [ProjectTask]
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var statuses: [DailyStatus]
    var folderURL: URL?

    var latestStatus: DailyStatus? { statuses.max(by: { $0.date < $1.date }) }

    var breadcrumb: [String] { [epic.nilIfBlank, parentProject.nilIfBlank, title.nilIfBlank].compactMap { $0 } }
    var pathLabel: String { breadcrumb.joined(separator: "  ›  ") }

    func isUpdatedToday(calendar: Calendar = .current) -> Bool {
        statuses.contains { calendar.isDateInToday($0.date) }
    }

    var searchableText: String {
        ([title, summary, notes] + tags + tasks.map(\.title) + statuses.map(\.searchableText))
            .joined(separator: "\n")
    }
}

struct SearchHit: Identifiable, Hashable {
    enum Kind: String { case project = "Проект", status = "Статус", note = "Заметка" }
    let id: String
    let projectID: UUID
    let statusID: UUID?
    let kind: Kind
    let title: String
    let excerpt: String
    let date: Date?
}

struct ActivityItem: Identifiable, Hashable {
    let id: UUID
    let projectID: UUID
    let projectTitle: String
    let status: DailyStatus
}

extension String {
    nonisolated var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated func fileSlug(fallback: String = "project") -> String {
        let latin = applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? self
        let allowed = latin.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let compact = String(allowed).split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
        return compact.isEmpty ? fallback : compact
    }
}
