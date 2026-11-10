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
    func testEmojiSelectionUsesUTF16() {
        let text = "Привет 👨‍👩‍👧‍👦!"
        let range = (text as NSString).range(of: "👨‍👩‍👧‍👦")
        let wrapped = MarkdownTextOps.wrap(text, range: range, marker: "**", placeholder: "")
        XCTAssertEqual((wrapped.text as NSString).substring(with: wrapped.selection), "👨‍👩‍👧‍👦")
        let unwrapped = MarkdownTextOps.wrap(wrapped.text, range: wrapped.selection, marker: "**", placeholder: "")
        XCTAssertEqual(unwrapped.text, text)
        XCTAssertEqual(unwrapped.selection, range)
        let link = MarkdownTextOps.insertLink(text, range: range)
        XCTAssertEqual((link.text as NSString).substring(with: link.selection), "👨‍👩‍👧‍👦")
    }

    func testPrefixAppliesToEverySelectedLine() {
        let result = MarkdownTextOps.prefixLine("один\nдва\nтри", range: NSRange(location: 0, length: 9), prefix: "- ")
        XCTAssertEqual(result.text, "- один\n- два\nтри")
        XCTAssertEqual((result.text as NSString).substring(with: result.selection), "один\n- два\n")
    }

    func testMissingAndOverflowingRangesAreClamped() {
        XCTAssertEqual(NSRange(location: NSNotFound, length: Int.max).clamped(to: 3), NSRange(location: 3, length: 0))
        XCTAssertEqual(NSRange(location: 1, length: Int.max).clamped(to: 3), NSRange(location: 1, length: 2))
    }

}
