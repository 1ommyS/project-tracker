import XCTest
@testable import PROJECT_Tracking

final class StatusTableTests: XCTestCase {
    private func project(_ title: String, statuses: [DailyStatus] = []) -> Project {
        Project(id: UUID(), title: title, summary: "", tags: [], state: .active, tasks: [],
                createdAt: .now, updatedAt: .now, isArchived: false, statuses: statuses, folderURL: nil)
    }

    func testRowsAreSortedAndDaysDescendingWithCorrectCells() throws {
        let day = Calendar.current.startOfDay(for: .now)
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: day))
        let entry = DailyStatus(projectID: UUID(), date: yesterday, status: "Результат", blockers: "Блокер")
        let model = StatusTableSnapshot(projects: [project("Бета", statuses: [entry]), project("Альфа")], endingOn: day, dayCount: 3)
        XCTAssertEqual(model.rows.map { $0.project.title }, ["Альфа", "Бета"])
        XCTAssertEqual(model.days[0], day)
        XCTAssertEqual(model.days[1], yesterday)
        XCTAssertEqual(model.rows[1].cells[yesterday]?.summary, "Результат")
        XCTAssertNil(model.rows[1].cells[day]?.entry)
        XCTAssertEqual(model.rows[1].cells[yesterday]?.hasBlockers, true)
    }

    func testFiltersRespectPeriodAndListDate() throws {
        let day = Calendar.current.startOfDay(for: .now)
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: day))
        let entry = DailyStatus(projectID: UUID(), date: yesterday, status: "Ревью", blockers: "Жду API")
        let model = StatusTableSnapshot(projects: [project("Первый", statuses: [entry]), project("Второй")], endingOn: day, dayCount: 3)
        XCTAssertEqual(model.filtered(query: "ревью", filter: .all).count, 1)
        XCTAssertEqual(model.filtered(query: "api", filter: .blockers).count, 1)
        XCTAssertTrue(model.filtered(query: "", filter: .blockers, selectedDayOnly: true).isEmpty)
        XCTAssertEqual(model.filtered(query: "", filter: .missing).count, 2)
        XCTAssertEqual(model.filtered(query: "первый", filter: .all, selectedDayOnly: true).count, 1)
    }

    func testDatesUseCalendarDaysAcrossDSTAndSummaryIsBounded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        let entry = DailyStatus(projectID: UUID(), date: day, status: String(repeating: "текст ", count: 1000))
        let model = StatusTableSnapshot(projects: [project("Большой статус", statuses: [entry])], endingOn: day, dayCount: 7, calendar: calendar)
        XCTAssertEqual(model.days.count, 7)
        XCTAssertTrue(model.days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        XCTAssertEqual(model.rows[0].cells[day]?.summary.count, 500)
    }
    func testCellExcerptRemovesMarkupWithoutChangingStoredEntry() {
        let entry = DailyStatus(projectID: UUID(), date: .now, status: "### Результат\n**Готово** [Макет](https://example.com)\n- [ ] дальше")
        let cell = StatusTableCell(entry: entry)
        XCTAssertEqual(cell.summary, "Результат\nГотово Макет\n☐ дальше")
        XCTAssertEqual(cell.entry?.status, entry.status)
    }

}
