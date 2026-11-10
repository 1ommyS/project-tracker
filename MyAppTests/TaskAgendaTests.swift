import XCTest
@testable import PROJECT_Tracking

final class TaskAgendaTests: XCTestCase {
    func testPartitionsTasksWithoutDuplicatingOverdueToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12)))
        let tasks = [ProjectTask(title: "Вчера", isDone: false, dueDate: now.addingTimeInterval(-86400)),
                     ProjectTask(title: "Утро", isDone: false, dueDate: now.addingTimeInterval(-3600)),
                     ProjectTask(title: "Вечер", isDone: false, dueDate: now.addingTimeInterval(3600)),
                     ProjectTask(title: "Завтра", isDone: false, dueDate: now.addingTimeInterval(86400)),
                     ProjectTask(title: "Без срока", isDone: false)]
        let project = Project(id: UUID(), title: "Проект", summary: "", tags: [], state: .active, tasks: tasks,
                              createdAt: now, updatedAt: now, isArchived: false, folderURL: nil)
        let overview = ProjectOverview(projects: [project])
        let agenda = TaskAgendaSnapshot(tasks: overview.openTasks, now: now, calendar: calendar)
        XCTAssertEqual(agenda.overdue.map { $0.task.title }, ["Вчера", "Утро"])
        XCTAssertEqual(agenda.beforeToday.map { $0.task.title }, ["Вчера"])
        XCTAssertEqual(agenda.today.map { $0.task.title }, ["Утро", "Вечер"])
        XCTAssertEqual(agenda.upcoming.map { $0.task.title }, ["Завтра"])
        XCTAssertEqual(agenda.unscheduled.count, 1)
        XCTAssertEqual(agenda.urgentCount, 3)
    }
}
