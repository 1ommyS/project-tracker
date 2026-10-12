import XCTest
@testable import PROJECT_Tracking

@MainActor
final class MarkdownCodecTests: XCTestCase {
    func testProjectRoundTripPreservesCyrillicAndTasks() throws {
        let dueDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 18, minute: 30)))
        let project = Project(id: UUID(), title: "Модуль статусов", epic: "Диплом", parentProject: "macOS-приложение",
                              summary: "Описание [[Связанный проект]]",
                              status: "Пишем главу 2, ждём фидбек научрука",
                              tags: ["учёба", "важно"], state: .active,
                              tasks: [ProjectTask(title: "Собрать требования", isDone: true),
                                      ProjectTask(title: "Написать главу", isDone: false, dueDate: dueDate)],
                              createdAt: .now, updatedAt: .now,
                              isArchived: false, folderURL: nil)
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
        XCTAssertEqual(decoded.summary, project.summary)
        XCTAssertEqual(decoded.status, "Пишем главу 2, ждём фидбек научрука")
        XCTAssertTrue(markdown.contains("## Статус"))
        XCTAssertTrue(markdown.contains("📅 2026-10-20 ⏰ 18:30"))
    }

    func testDailyStatusRoundTrip() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let status = DailyStatus(id: UUID(), projectID: UUID(), date: day,
                                 status: "Глава у научрука", blockers: "Жду API",
                                 createdAt: day, updatedAt: day, fileURL: nil)
        let decoded = try MarkdownCodec.decodeStatus(
            MarkdownCodec.encode(status: status),
            fileURL: URL(fileURLWithPath: "/tmp/s.md"))
        XCTAssertEqual(decoded.id, status.id)
        XCTAssertEqual(decoded.projectID, status.projectID)
        XCTAssertEqual(decoded.status, "Глава у научрука")
        XCTAssertEqual(decoded.blockers, "Жду API")
        XCTAssertTrue(Calendar.current.isDate(decoded.date, inSameDayAs: day))
    }

    func testDailyStatusCheckboxesRoundTrip() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let status = DailyStatus(id: UUID(), projectID: UUID(), date: day,
                                 status: "План дня",
                                 blockers: "",
                                 tasks: [StatusTask(id: 0, title: "Позвонить дизайнеру", isDone: true),
                                         StatusTask(id: 1, title: "Отправить макет", isDone: false)])
        let markdown = MarkdownCodec.encode(status: status)
        XCTAssertTrue(markdown.contains("- [x] Позвонить дизайнеру"))
        XCTAssertTrue(markdown.contains("- [ ] Отправить макет"))

        let decoded = try MarkdownCodec.decodeStatus(markdown, fileURL: URL(fileURLWithPath: "/tmp/s.md"))
        XCTAssertEqual(decoded.status, "План дня", "чекбоксы не остаются в тексте статуса")
        XCTAssertEqual(decoded.tasks, status.tasks)
    }

    func testRepositoryPersistsProjectAndTasks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PulseboardTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MarkdownRepository(rootURL: root)
        let due = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        var project = Project(id: UUID(), title: "Тест", summary: "Локальный проект", tags: [], state: .active,
                              tasks: [ProjectTask(title: "Первая задача", isDone: false, dueDate: due),
                                      ProjectTask(title: "Готовая задача", isDone: true, dueDate: nil)],
                              createdAt: .now, updatedAt: .now, isArchived: false, folderURL: nil)
        project = try await repository.saveProject(project)

        let loaded = try await repository.loadProjects()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tasks.count, 2)
        XCTAssertEqual(loaded[0].openTasks.first?.title, "Первая задача")
        XCTAssertEqual(loaded[0].doneTasks.first?.title, "Готовая задача")
    }

    func testDecodeIgnoresLegacySections() throws {
        let id = UUID()
        let markdown = """
        ---
        type: project
        id: \(id.uuidString)
        title: "Старый формат"
        epic: ""
        parent_project: ""
        state: active
        tags: []
        created: \(MarkdownCodec.iso.string(from: .now))
        updated: \(MarkdownCodec.iso.string(from: .now))
        archived: false
        ---
        # Старый формат

        ## Описание
        Описание проекта

        ## Задачи
        - [ ] Одна задача

        ## Заметки
        Эти заметки из старой версии больше не читаются, но файл остаётся валидным.
        """
        let decoded = try MarkdownCodec.decodeProject(markdown, folderURL: URL(fileURLWithPath: "/tmp/legacy"))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.tasks.count, 1)
        XCTAssertEqual(decoded.tasks[0].title, "Одна задача")
        XCTAssertEqual(decoded.status, "", "файлы без секции ## Статус читаются с пустым статусом")
    }
}
