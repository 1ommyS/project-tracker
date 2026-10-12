import XCTest
@testable import PROJECT_Tracking

final class TaskInputParserTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTomorrowWithTime() {
        let now = date(2026, 10, 12, 10, 0)
        let parsed = TaskInputParser.parse("Позвонить Ивану завтра 18:30", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Позвонить Ивану")
        XCTAssertEqual(parsed.dueDate, date(2026, 10, 13, 18, 30))
    }

    func testTodayWithoutTime() {
        let now = date(2026, 10, 12, 7, 0)
        let parsed = TaskInputParser.parse("Собрать макет сегодня", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Собрать макет")
        XCTAssertEqual(parsed.dueDate, date(2026, 10, 12, 9, 0))
    }

    func testTodayWithoutTimeWhenMorningPassed() {
        let now = date(2026, 10, 12, 15, 0)
        let parsed = TaskInputParser.parse("Собрать макет сегодня", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Собрать макет")
        XCTAssertEqual(parsed.dueDate, now.addingTimeInterval(3600))
    }

    func testTimeOnlyRollsToTomorrow() {
        let now = date(2026, 10, 12, 15, 0)
        let parsed = TaskInputParser.parse("Созвон в 14", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Созвон")
        XCTAssertEqual(parsed.dueDate, date(2026, 10, 13, 14, 0))
    }

    func testTimeOnlyLaterToday() {
        let now = date(2026, 10, 12, 10, 0)
        let parsed = TaskInputParser.parse("Созвон в 14", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Созвон")
        XCTAssertEqual(parsed.dueDate, date(2026, 10, 12, 14, 0))
    }

    func testNumericDateWithTime() {
        let now = date(2026, 10, 12, 10, 0)
        let parsed = TaskInputParser.parse("Сдать отчёт 25.12 10:00", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Сдать отчёт")
        XCTAssertEqual(parsed.dueDate, date(2026, 12, 25, 10, 0))
    }

    func testNumericDateWithExplicitYear() {
        let now = date(2026, 10, 12, 10, 0)
        let parsed = TaskInputParser.parse("Дедлайн 01.03.2027 в 9:15", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Дедлайн")
        XCTAssertEqual(parsed.dueDate, date(2027, 3, 1, 9, 15))
    }

    func testPlainTitleStaysIntact() {
        let now = date(2026, 10, 12, 10, 0)
        let parsed = TaskInputParser.parse("Макет 2 экрана", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Макет 2 экрана")
        XCTAssertNil(parsed.dueDate)
    }

    func testDayAfterTomorrow() {
        let now = date(2026, 10, 12, 10, 0)
        let parsed = TaskInputParser.parse("Написать послезавтра конспект", now: now, calendar: calendar)
        XCTAssertEqual(parsed.title, "Написать конспект")
        XCTAssertEqual(parsed.dueDate, date(2026, 10, 14, 9, 0))
    }

    // MARK: - Подсветка распознанного срока

    func testHighlightRangeCoversDayAndTimeWithPreposition() {
        let input = "Позвонить завтра в 18:00"
        let parsed = TaskInputParser.parseDetailed(input)
        if let range = parsed.highlightRange {
            XCTAssertEqual(String(input[range]), "завтра в 18:00")
        } else {
            XCTFail("подсветка должна покрывать «завтра в 18:00»")
        }
        XCTAssertEqual(parsed.title, "Позвонить")
    }

    func testHighlightRangeCoversNumericDateAndTime() {
        let input = "Сдать отчёт 25.12 10:00"
        let parsed = TaskInputParser.parseDetailed(input)
        XCTAssertEqual(parsed.highlightRange.map { String(input[$0]) }, "25.12 10:00")
    }

    func testHighlightRangeOnlyTime() {
        let input = "Созвон в 14"
        let parsed = TaskInputParser.parseDetailed(input)
        XCTAssertEqual(parsed.highlightRange.map { String(input[$0]) }, "в 14")
    }

    func testHighlightRangeNilForPlainTitle() {
        let parsed = TaskInputParser.parseDetailed("Макет 2 экрана")
        XCTAssertNil(parsed.highlightRange)
    }
}
