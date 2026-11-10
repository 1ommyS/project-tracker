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
    @MainActor
    func testDailyStatusesFitNarrowDetailColumn() {
        let store = AppStore(vaultURL: FileManager.default.temporaryDirectory, notificationService: NotificationService(client: FakeNotificationClient()))
        let project = Project(id: UUID(), title: "Длинное название проекта для проверки переноса", summary: "",
                              tags: [], state: .active, tasks: [], createdAt: .now, updatedAt: .now,
                              isArchived: false, folderURL: nil)
        let section = DailyStatusesSection(projects: [project], day: .constant(.now)).environment(store)
        XCTAssertLessThanOrEqual(fittedWidth(of: section, proposing: 380), 380.5)
    }

    @MainActor
    func testStatusesControlsFitNarrowDetailColumn() {
        let store = AppStore(vaultURL: FileManager.default.temporaryDirectory, notificationService: NotificationService(client: FakeNotificationClient()))
        store.projects = [Project(id: UUID(), title: "Проект", summary: "", tags: [], state: .active, tasks: [],
                                  createdAt: .now, updatedAt: .now, isArchived: false, folderURL: nil)]
        let view = StatusesView().environment(store)
        XCTAssertLessThanOrEqual(fittedWidth(of: view, proposing: 440), 440.5,
                                 "Панель поиска/фильтров должна переноситься внутри узкой колонки")
    }

}
