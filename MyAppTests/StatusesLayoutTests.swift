import SwiftUI
import XCTest
@testable import PROJECT_Tracking

/// Защита ширины блока «Статусы по дням»: редактор статуса обязан
/// укладываться в предложенную ширину — длинная строка переносится,
/// а не растягивает панель шире соседних блоков.
final class StatusesLayoutTests: XCTestCase {
    @MainActor
    private func fittedWidth(of view: some View, proposing width: CGFloat) -> CGFloat {
        let host = NSHostingController(rootView: AnyView(view))
        return host.sizeThatFits(in: NSSize(width: width, height: 600)).width
    }

    @MainActor
    func testMarkdownEditorFitsProposedWidthWithLongUnwrappedLine() {
        let longLine = String(repeating: "очень длинный статус без переносов ", count: 12)
        let editor = MarkdownEditor(text: .constant(longLine), minHeight: 96)
        XCTAssertLessThanOrEqual(
            fittedWidth(of: editor, proposing: 600), 600.5,
            "MarkdownEditor шире предложенной ширины — панель «Статусы по дням» разъезжается"
        )
    }

    @MainActor
    func testMarkdownEditorToolbarFitsNarrowWidth() {
        let editor = MarkdownEditor(text: .constant(""), minHeight: 56)
        XCTAssertLessThanOrEqual(
            fittedWidth(of: editor, proposing: 320), 320.5,
            "тулбар редактора требует больше места, чем есть, и распирает панель"
        )
    }
}
