import XCTest
@testable import PROJECT_Tracking

final class MarkdownTextOpsTests: XCTestCase {
    func testWrapSelectedText() {
        let result = MarkdownTextOps.wrap("привет мир", range: NSRange(location: 7, length: 3), marker: "**", placeholder: "жирный")
        XCTAssertEqual(result.text, "привет **мир**")
        XCTAssertEqual(result.selection, NSRange(location: 9, length: 3), "выделение остаётся на внутреннем тексте")
    }

    func testWrapWithoutSelectionInsertsPlaceholder() {
        let result = MarkdownTextOps.wrap("abc", range: NSRange(location: 3, length: 0), marker: "*", placeholder: "курсив")
        XCTAssertEqual(result.text, "abc*курсив*")
        XCTAssertEqual(result.selection, NSRange(location: 4, length: 6), "шаблон выделяется для замены")
    }

    func testWrapOnEmptyText() {
        let result = MarkdownTextOps.wrap("", range: NSRange(location: 0, length: 0), marker: "`", placeholder: "код")
        XCTAssertEqual(result.text, "`код`")
        XCTAssertEqual(result.selection.location, 1)
    }

    func testPrefixLineInsertsAtLineStart() {
        let text = "первая\nвторая строка\nтретья"
        // Курсор в середине второй строки (после «вто»).
        let secondLineOffset = (text as NSString).range(of: "вторая").location + 3
        let result = MarkdownTextOps.prefixLine(text, range: NSRange(location: secondLineOffset, length: 0), prefix: "## ")
        XCTAssertEqual(result.text, "первая\n## вторая строка\nтретья")
        XCTAssertEqual(result.selection.location, secondLineOffset + 3)
    }

    func testPrefixLineFirstLine() {
        let result = MarkdownTextOps.prefixLine("заголовок", range: NSRange(location: 0, length: 0), prefix: "- ")
        XCTAssertEqual(result.text, "- заголовок")
    }

    func testInsertLinkWithoutSelectionSelectsURL() {
        let result = MarkdownTextOps.insertLink("смотри ", range: NSRange(location: 7, length: 0))
        XCTAssertEqual(result.text, "смотри [ссылка](https://)")
        // Выделен https:// — начало после «смотри [ссылка](» = 7+6+1+... проверим содержимое:
        let view = result.text as NSString
        XCTAssertEqual(view.substring(with: result.selection), "https://", "выделяется URL для замены")
    }

    func testInsertLinkWithSelectionKeepsTitleSelected() {
        let result = MarkdownTextOps.insertLink("док: документация тут", range: NSRange(location: 5, length: 12))
        XCTAssertEqual(result.text, "док: [документация](https://) тут")
        let view = result.text as NSString
        XCTAssertEqual(view.substring(with: result.selection), "документация", "название остаётся выделенным")
    }

    func testRangeClamping() {
        XCTAssertEqual(NSRange(location: 100, length: 5).clamped(to: 10), NSRange(location: 10, length: 0))
        XCTAssertEqual(NSRange(location: 2, length: 100).clamped(to: 5), NSRange(location: 2, length: 3))
    }
}
