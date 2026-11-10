import XCTest
@testable import PROJECT_Tracking

final class StatusTransferTests: XCTestCase {
    func testModelOutputSplitsSectionsAndPreservesLinksAndCheckboxes() throws {
        let result = try StatusTransfer.parse("## Статус\nГотово **ревью**. [Документ](https://example.com)\n- [ ] следующий шаг\n\n## Блокеры\nЖду ответ")
        XCTAssertTrue(result.status.contains("[Документ](https://example.com)"))
        XCTAssertTrue(result.status.contains("- [ ] следующий шаг"))
        XCTAssertEqual(result.blockers, "Жду ответ")
    }
    func testPlainNoteAndEmptyBlockersAreAccepted() throws {
        XCTAssertEqual(try StatusTransfer.parse("Заметка").status, "Заметка")
        XCTAssertEqual(try StatusTransfer.parse("## Статус\nГотово\n## Блокеры\n").blockers, "")
    }
    func testFencedSectionNameStaysInCode() throws {
        let result = try StatusTransfer.parse("## Статус\n```\n## Блокеры\n```\n## Блокеры\nРеальный блокер")
        XCTAssertEqual(result.status, "```\n## Блокеры\n```")
        XCTAssertEqual(result.blockers, "Реальный блокер")
    }
    func testWrapperAndCRLFAndMalformedSections() throws {
        XCTAssertEqual(try StatusTransfer.parse("```markdown\n## Статус\nТекст\n## Блокеры\n\n```").status, "Текст")
        XCTAssertEqual(try StatusTransfer.parse("## Статус\r\nТекст\r\n## Блокеры\r\nСтоп").blockers, "Стоп")
        XCTAssertThrowsError(try StatusTransfer.parse("Введение\n## Статус\nТекст"))
        XCTAssertThrowsError(try StatusTransfer.parse("## Статус\nТекст\n## Статус\nВторой"))
        XCTAssertThrowsError(try StatusTransfer.parse(""))
    }
    func testPromptContainsSelectedContextAndExactPasteHeadings() {
        let prompt = StatusTransfer.prompt(project: "Мой проект", date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(prompt.contains("Мой проект"))
        XCTAssertTrue(prompt.contains("## Статус"))
        XCTAssertTrue(prompt.contains("## Блокеры"))
    }
}
