import AppKit
import XCTest
@testable import PROJECT_Tracking

@MainActor
final class MarkdownEditorTests: XCTestCase {
    func testFormattingUsesNativeSelectionAndCanBeUndone() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let textView = NSTextView(frame: window.contentView!.bounds)
        textView.isRichText = false
        textView.allowsUndo = true
        window.contentView = textView
        window.makeFirstResponder(textView)
        textView.string = "Текст 🚀"
        textView.setSelectedRange((textView.string as NSString).range(of: "🚀"))
        let controller = MarkdownEditorController()
        controller.textView = textView
        let undo = try XCTUnwrap(textView.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        controller.apply { MarkdownTextOps.wrap($0, range: $1, marker: "**", placeholder: "") }
        undo.endUndoGrouping()
        XCTAssertEqual(textView.string, "Текст **🚀**")
        XCTAssertEqual((textView.string as NSString).substring(with: textView.selectedRange()), "🚀")
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(textView.string, "Текст 🚀")
        undo.redo()
        XCTAssertEqual(textView.string, "Текст **🚀**")
    }
}
