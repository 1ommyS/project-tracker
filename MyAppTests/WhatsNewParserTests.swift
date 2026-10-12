import XCTest
@testable import PROJECT_Tracking

final class WhatsNewParserTests: XCTestCase {
    private let sample = """
    ## 1.2.0 — 2026-10-12

    ### Задачи
    - Инлайн-переименование
    - Сроки поповером

    ### Навигация
    История переходов появилась.

    ## 1.1.0 — 2026-09-01

    - Первый релиз
    """

    func testParsesSectionsHeadersAndItems() {
        let sections = WhatsNewParser.parse(sample)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "1.2.0 — 2026-10-12")
        XCTAssertEqual(sections[0].blocks, [
            .header("Задачи"),
            .item("Инлайн-переименование"),
            .item("Сроки поповером"),
            .header("Навигация"),
            .item("История переходов появилась.")
        ])
        XCTAssertEqual(sections[1].title, "1.1.0 — 2026-09-01")
        XCTAssertEqual(sections[1].blocks, [.item("Первый релиз")])
    }

    func testEmptyMarkdownProducesNoSections() {
        XCTAssertTrue(WhatsNewParser.parse("   \n\n").isEmpty)
    }

    func testBundledMarkdownParses() {
        let sections = WhatsNewParser.parse(WhatsNewParser.bundledMarkdown)
        XCTAssertFalse(sections.isEmpty, "WhatsNew.md должен попадать в бандл и парситься")
        XCTAssertTrue(sections[0].blocks.contains { block in
            if case .header = block { return true }
            return false
        })
    }
}
