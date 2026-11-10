import Foundation

nonisolated struct TaskAgendaSnapshot {
    let overdue: [TaskContext]
    let beforeToday: [TaskContext]
    let today: [TaskContext]
    let upcoming: [TaskContext]
    let unscheduled: [TaskContext]
    var urgentCount: Int { beforeToday.count + today.count }

    init(tasks: [TaskContext], now: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let horizon = calendar.date(byAdding: .day, value: 8, to: start) ?? end
        let ordered = tasks.filter { $0.task.dueDate != nil }.sorted {
            ($0.task.dueDate ?? .distantFuture) < ($1.task.dueDate ?? .distantFuture)
        }
        overdue = ordered.filter { ($0.task.dueDate ?? .distantFuture) < now }
        beforeToday = ordered.filter { ($0.task.dueDate ?? .distantFuture) < start }
        today = ordered.filter { guard let due = $0.task.dueDate else { return false }; return due >= start && due < end }
        upcoming = ordered.filter { guard let due = $0.task.dueDate else { return false }; return due >= end && due < horizon }
        unscheduled = tasks.filter { $0.task.dueDate == nil }.sorted {
            $0.project.title.localizedStandardCompare($1.project.title) == .orderedAscending
        }
    }
}
