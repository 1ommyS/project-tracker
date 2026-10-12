import XCTest
@testable import Pulseboard

@MainActor
final class MarkdownCodecTests: XCTestCase {
    func testProjectRoundTripPreservesCyrillicAndTasks() throws {
        let dueDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 18, minute: 30)))
        let project = Project(id: UUID(), title: "Модуль статусов", epic: "Диплом", parentProject: "macOS-приложение",
                              summary: "Описание [[Связанный проект]]",
                              tags: ["учёба", "важно"], state: .active,
                              tasks: [ProjectTask(title: "Собрать требования", isDone: true),
                                      ProjectTask(title: "Написать главу", isDone: false, dueDate: dueDate)],
                              notes: "Текст с #тегом", createdAt: .now, updatedAt: .now,
                              isArchived: false, statuses: [], folderURL: nil)
        let markdown = MarkdownCodec.encode(project: project)
        let decoded = try MarkdownCodec.decodeProject(markdown, folderURL: URL(fileURLWithPath: "/tmp/project"))

        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.title, project.title)
        XCTAssertEqual(decoded.epic, "Диплом")
        XCTAssertEqual(decoded.parentProject, "macOS-приложение")
        XCTAssertEqual(decoded.pathLabel, "Диплом  ›  macOS-приложение  ›  Модуль статусов")
        XCTAssertEqual(decoded.tags, project.tags)
        XCTAssertEqual(decoded.tasks.count, 2)
        XCTAssertTrue(decoded.tasks[0].isDone)
        let decodedDueDate = try XCTUnwrap(decoded.tasks[1].dueDate)
        XCTAssertEqual(decodedDueDate.timeIntervalSince1970, dueDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.notes, project.notes)
        XCTAssertTrue(markdown.contains("📅 2026-10-20 ⏰ 18:30"))
    }

    func testStatusRoundTripPreservesSections() throws {
        let url = URL(fileURLWithPath: "/tmp/status.md")
        let status = DailyStatus(id: UUID(), projectID: UUID(), projectTitle: "Проект", date: .now,
                                 state: .blocked, completed: "Готов макет", plans: "Написать код",
                                 blockers: "Жду API", notes: "[[Документ]]", createdAt: .now, updatedAt: .now, fileURL: url)
        let decoded = try MarkdownCodec.decodeStatus(MarkdownCodec.encode(status: status), fileURL: url)

        XCTAssertEqual(decoded.id, status.id)
        XCTAssertEqual(decoded.state, .blocked)
        XCTAssertEqual(decoded.completed, "Готов макет")
        XCTAssertEqual(decoded.blockers, "Жду API")
    }

    func testRepositoryPersistsProjectAndStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PulseboardTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MarkdownRepository(rootURL: root)
        var project = Project(id: UUID(), title: "Тест", summary: "Локальный проект", tags: [], state: .active,
                              tasks: [], notes: "", createdAt: .now, updatedAt: .now, isArchived: false, statuses: [], folderURL: nil)
        project = try await repository.saveProject(project)
        let status = DailyStatus(id: UUID(), projectID: project.id, projectTitle: project.title, date: .now, state: .active,
                                 completed: "Работает", plans: "Проверить", blockers: "", notes: "", createdAt: .now, updatedAt: .now, fileURL: nil)
        _ = try await repository.saveStatus(status, for: project)

        let loaded = try await repository.loadProjects()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].statuses.first?.completed, "Работает")
    }
}
