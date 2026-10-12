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

struct Project: Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var epic: String = ""
    var parentProject: String = ""
    var summary: String
    var tags: [String]
    var state: ProjectState
    var tasks: [ProjectTask]
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var folderURL: URL?

    var breadcrumb: [String] { [epic.nilIfBlank, parentProject.nilIfBlank, title.nilIfBlank].compactMap { $0 } }
    var pathLabel: String { breadcrumb.joined(separator: "  ›  ") }

    var openTasks: [ProjectTask] { tasks.filter { !$0.isDone } }
    var doneTasks: [ProjectTask] { tasks.filter(\.isDone) }
    var taskProgress: Double { tasks.isEmpty ? 0 : Double(doneTasks.count) / Double(tasks.count) }

    var searchableText: String {
        ([title, summary] + tags + tasks.map(\.title)).joined(separator: "\n")
    }
}

/// Задача вместе с проектом, которому она принадлежит, — для лент «Сегодня» и поиска.
struct TaskContext: Identifiable, Hashable {
    let project: Project
    let task: ProjectTask
    var id: UUID { task.id }
}

struct SearchHit: Identifiable, Hashable {
    enum Kind: String { case project = "Проект", task = "Задача" }
    let id: String
    let projectID: UUID
    let kind: Kind
    let title: String
    let excerpt: String
    let date: Date?
}

/// Что открыть в редакторе задачи: новую задачу проекта или существующую.
struct TaskEditorContext: Identifiable {
    let projectID: UUID
    let taskID: UUID?
    var id: String { "\(projectID.uuidString)-\(taskID?.uuidString ?? "new")" }
}

extension Date {
    /// Метка квартала в формате YYQN: октябрь 2026 → «26Q4».
    var quarterLabel: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: self) % 100
        let quarter = (calendar.component(.month, from: self) - 1) / 3 + 1
        return String(format: "%02dQ%d", year, quarter)
    }
}

extension Project {
    /// Квартал создания — основа папки и фильтра.
    var quarter: String { createdAt.quarterLabel }
    /// Завершённые проекты живут в подпапке Completed Projects.
    var isCompleted: Bool { state == .done || state == .archived || isArchived }
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
