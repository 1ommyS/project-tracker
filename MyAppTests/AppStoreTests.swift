import XCTest
@testable import PROJECT_Tracking

/// Интеграционные тесты AppStore на временном хранилище.
/// Задачи со сроками не сохраняются через store-методы, чтобы тесты
/// не запрашивали разрешение на уведомления.
@MainActor
final class AppStoreTests: XCTestCase {
    private var store: AppStore!
    private var vaultURL: URL!

    override func setUp() async throws {
        vaultURL = FileManager.default.temporaryDirectory.appendingPathComponent("AppStoreTests-\(UUID().uuidString)")
        store = AppStore(vaultURL: vaultURL)
        await store.reload()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vaultURL)
    }

    @discardableResult
    private func makeProject(_ title: String, epic: String = "") async throws -> Project {
        let created = await store.createProject(title: title, epic: epic, parentProject: "", summary: "", tags: [], state: .active)
        return try XCTUnwrap(created)
    }

    /// Всегда свежая копия из store — как это делают экраны.
    private func current() throws -> Project { try XCTUnwrap(store.projects.first) }

    // MARK: - Создание и персистентность

    func testCreateProjectPersistsAndNavigates() async throws {
        let created = try await makeProject("Диплом", epic: "Учёба")

        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.selectedProjectID, created.id)
        XCTAssertEqual(store.destination, .projects)
        XCTAssertEqual(store.projects.first?.epic, "Учёба")

        await store.reload()
        XCTAssertEqual(store.projects.count, 1, "проект должен пережить перечитывание с диска")
        XCTAssertEqual(store.projects.first?.id, created.id)
    }

    func testDeleteProjectRemovesFromDisk() async throws {
        let project = try await makeProject("Временный")
        try await Task.sleep(for: .milliseconds(50))
        await store.delete(project)

        XCTAssertTrue(store.projects.isEmpty)
        await store.reload()
        XCTAssertTrue(store.projects.isEmpty, "папка проекта должна уйти с диска (в Корзину)")
    }

    // MARK: - CRUD задач

    func testTaskLifecyclePersistsAcrossReload() async throws {
        let project = try await makeProject("Проект с задачами")

        await store.addTask(title: "Первая", dueDate: nil, to: project)
        await store.addTask(title: "Вторая", dueDate: nil, to: try current())
        XCTAssertEqual(try current().openTasks.count, 2)

        // Переключение выполнения
        await store.toggleTask(try current().openTasks[0], in: try current())
        XCTAssertEqual(try current().doneTasks.count, 1)
        XCTAssertEqual(try current().openTasks.first?.title, "Вторая")

        // Редактирование
        var edited = try XCTUnwrap(try current().openTasks.first)
        edited.title = "Вторая (правка)"
        await store.updateTask(edited, in: try current())

        // Удаление выполненной
        let done = try XCTUnwrap(try current().tasks.first(where: \.isDone))
        await store.deleteTask(done, in: try current())

        await store.reload()
        let restored = try current()
        XCTAssertEqual(restored.tasks.map(\.title), ["Вторая (правка)"])
        XCTAssertFalse(restored.tasks[0].isDone)
    }

    // MARK: - Архивация

    func testArchiveAndRestoreFiltering() async throws {
        let project = try await makeProject("Архивный кандидат")
        await store.archive(project)

        XCTAssertTrue(store.activeProjects.isEmpty)
        XCTAssertEqual(store.archivedProjects.count, 1)

        await store.reload()
        XCTAssertEqual(store.archivedProjects.count, 1, "архивное состояние сохраняется на диск")

        let archived = try XCTUnwrap(store.archivedProjects.first)
        await store.restore(archived)
        XCTAssertEqual(store.activeProjects.count, 1)
    }

    // MARK: - Поиск

    func testSearchFindsProjectsAndTasks() async throws {
        let project = try await makeProject("Макет дашборда", epic: "Дизайн")
        await store.addTask(title: "Собрать требования к макету", dueDate: nil, to: project)

        let projectHits = store.searchHits(query: "дашборд")
        XCTAssertEqual(projectHits.count, 1)
        XCTAssertEqual(projectHits[0].kind, .project)
        XCTAssertEqual(projectHits[0].projectID, project.id)

        let taskHits = store.searchHits(query: "требования")
        XCTAssertEqual(taskHits.count, 1)
        XCTAssertEqual(taskHits[0].kind, .task)
        XCTAssertEqual(taskHits[0].title, "Собрать требования к макету")

        XCTAssertTrue(store.searchHits(query: "   ").isEmpty, "пустой запрос не должен давать результатов")
    }

    // MARK: - История навигации

    func testNavigationHistoryBackAndForward() async throws {
        XCTAssertFalse(store.canGoBack)
        XCTAssertFalse(store.canGoForward)

        // createProject сам уводит на «Проекты», openProject — в редактор:
        // today → projects(лента) → projects(редактор).
        let project = try await makeProject("Цель перехода")
        store.openProject(project.id)
        XCTAssertEqual(store.destination, .projects)
        XCTAssertEqual(store.projectsPresentation, .editor)
        XCTAssertTrue(store.canGoBack)

        store.goBack()
        XCTAssertEqual(store.destination, .projects)
        XCTAssertEqual(store.projectsPresentation, .feed, "первый шаг назад — из редактора в ленту")
        XCTAssertTrue(store.canGoBack)
        XCTAssertTrue(store.canGoForward)

        store.goBack()
        XCTAssertEqual(store.destination, .today, "второй шаг назад — на исходный экран")
        XCTAssertFalse(store.canGoBack)
        XCTAssertTrue(store.canGoForward)

        store.goForward()
        store.goForward()
        XCTAssertEqual(store.destination, .projects)
        XCTAssertEqual(store.selectedProjectID, project.id)
        XCTAssertEqual(store.projectsPresentation, .editor)
        XCTAssertFalse(store.canGoForward, "в конце истории вперёд ходить больше некуда")
    }

    func testOpenProjectsListKeepsFeedPresentation() async throws {
        let project = try await makeProject("Проект")
        store.openProject(project.id)
        store.openProjectsList()
        XCTAssertEqual(store.projectsPresentation, .feed)
        XCTAssertEqual(store.destination, .projects)
    }

    // MARK: - Срочные задачи

    func testUrgentTaskCountCountsOverdueAndTodayOnly() async throws {
        let project = try await makeProject("Сроки")
        var withTasks = project
        let calendar = Calendar.current
        withTasks.tasks = [
            ProjectTask(title: "Просрочена", isDone: false, dueDate: calendar.date(byAdding: .day, value: -2, to: .now)),
            ProjectTask(title: "Сегодня", isDone: false, dueDate: .now),
            ProjectTask(title: "Потом", isDone: false, dueDate: calendar.date(byAdding: .day, value: 5, to: .now)),
            ProjectTask(title: "Выполненная просроченная", isDone: true, dueDate: calendar.date(byAdding: .day, value: -1, to: .now)),
            ProjectTask(title: "Без срока", isDone: false, dueDate: nil)
        ]
        store.projects[0] = withTasks

        XCTAssertEqual(store.urgentTaskCount, 2, "просроченные + сегодняшние, без выполненных и будущих")
    }

    // MARK: - Инлайн-переименование

    func testRenameProjectPersistsAndIgnoresEmpty() async throws {
        let project = try await makeProject("Старое имя")
        await store.renameProject(project, to: "Новое имя")

        XCTAssertEqual(store.projects.first?.title, "Новое имя")
        await store.reload()
        XCTAssertEqual(store.projects.first?.title, "Новое имя", "переименование должно пережить перечитывание")

        let current = try XCTUnwrap(store.projects.first)
        await store.renameProject(current, to: "   ")
        XCTAssertEqual(store.projects.first?.title, "Новое имя", "пустое имя не должно применяться")
    }

    func testRenameTaskPersists() async throws {
        let project = try await makeProject("Проект")
        await store.addTask(title: "Старая формулировка", dueDate: nil, to: project)

        let task = try XCTUnwrap(try current().openTasks.first)
        await store.renameTask(task, to: "Новая формулировка", in: try current())

        XCTAssertEqual(try current().openTasks.first?.title, "Новая формулировка")
        await store.reload()
        XCTAssertEqual(try XCTUnwrap(try current().openTasks.first).title, "Новая формулировка")
    }

    // MARK: - Палитра

    func testPaletteSelectionPersists() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "appPalette") }
        store.palette = .purple

        let second = AppStore(vaultURL: vaultURL)
        XCTAssertEqual(second.palette, .purple, "выбор палитры должен читаться из UserDefaults")

        second.palette = .teal
        let third = AppStore(vaultURL: vaultURL)
        XCTAssertEqual(third.palette, .teal)
    }

    func testInterfaceModePersists() {
        defer { UserDefaults.standard.removeObject(forKey: "interfaceMode") }
        XCTAssertEqual(store.interfaceMode, .detailed, "по умолчанию подробный вид")

        store.interfaceMode = .focused
        XCTAssertEqual(AppStore(vaultURL: vaultURL).interfaceMode, .focused)
    }

    func testOverdueTasksCollectOnlyPastDueOpen() async throws {
        let project = try await makeProject("Сроки")
        let calendar = Calendar.current
        var withTasks = project
        withTasks.tasks = [
            ProjectTask(title: "Давно просрочена", isDone: false, dueDate: calendar.date(byAdding: .day, value: -5, to: .now)),
            ProjectTask(title: "Вчера", isDone: false, dueDate: calendar.date(byAdding: .day, value: -1, to: .now)),
            ProjectTask(title: "Завтра", isDone: false, dueDate: calendar.date(byAdding: .day, value: 1, to: .now)),
            ProjectTask(title: "Выполненная просроченная", isDone: true, dueDate: calendar.date(byAdding: .day, value: -3, to: .now)),
            ProjectTask(title: "Без срока", isDone: false, dueDate: nil)
        ]
        store.projects[0] = withTasks

        let overdue = store.overdueTasks
        XCTAssertEqual(overdue.map(\.task.title), ["Давно просрочена", "Вчера"],
                       "только открытые задачи с прошедшим сроком, самые старые сверху")
    }

    func testSetProjectStatusPersistsAndClears() async throws {
        let project = try await makeProject("Проект")
        await store.setProjectStatus(project, to: "Ждём ревью макета")

        XCTAssertEqual(try current().status, "Ждём ревью макета")
        await store.reload()
        XCTAssertEqual(try current().status, "Ждём ревью макета", "статус сохраняется в Project.md")

        let updated = try current()
        await store.setProjectStatus(updated, to: "   ")
        XCTAssertEqual(try current().status, "", "пустой статус очищается")
    }

    func testDailyStatusUpsertPerDay() async throws {
        let project = try await makeProject("Матрица")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!

        await store.setDailyStatus(text: "Пишем главу", blockers: nil, for: project, on: .now)
        await store.setDailyStatus(text: "Правим главу", blockers: nil, for: try current(), on: .now)
        await store.setDailyStatus(text: nil, blockers: "Жду ревью", for: try current(), on: yesterday)

        let today = try current().statuses.first { Calendar.current.isDateInToday($0.date) }
        XCTAssertEqual(today?.status, "Правим главу", "повторная правка того же дня обновляет, а не создаёт запись")
        XCTAssertEqual(try current().statuses.count, 2)

        await store.reload()
        let restored = try current()
        XCTAssertEqual(restored.statuses.count, 2, "дневные статусы читаются с диска")
        XCTAssertEqual(restored.statuses.first { Calendar.current.isDateInToday($0.date) }?.status, "Правим главу")
        XCTAssertEqual(restored.latestBlockers, "Жду ревью")
    }

    func testStatusCheckboxesTypedInlineAndToggled() async throws {
        let project = try await makeProject("Матрица")

        // Пользователь печатает чекбоксы прямо в тексте статуса.
        await store.setDailyStatus(text: "План:\n- [ ] позвонить\n- [x] собрать макет", blockers: nil, for: project, on: .now)
        await store.reload()
        let entry = try XCTUnwrap(try current().statuses.first { Calendar.current.isDateInToday($0.date) })
        XCTAssertEqual(entry.status, "План:")
        XCTAssertEqual(entry.tasks.map(\.title), ["позвонить", "собрать макет"])
        XCTAssertTrue(entry.tasks[1].isDone)

        await store.toggleStatusTask(entry.tasks[0], in: entry, for: try current())
        await store.reload()
        let updated = try XCTUnwrap(try current().statuses.first { Calendar.current.isDateInToday($0.date) })
        XCTAssertTrue(updated.tasks[0].isDone, "переключение чекбокса сохраняется на диск")
    }

    // MARK: - Стабильность порядка

    func testSavingDoesNotReorderMasterArray() async throws {
        _ = try await makeProject("Альфа")
        try await Task.sleep(for: .milliseconds(30))
        _ = try await makeProject("Бета")

        let orderBefore = store.projects.map(\.title)
        XCTAssertEqual(orderBefore, ["Альфа", "Бета"], "порядок создания без пересортировки")

        var older = try XCTUnwrap(store.projects.first { $0.title == "Альфа" })
        older.summary = "обновлённый текст"
        await store.saveProject(older)

        XCTAssertEqual(store.projects.map(\.title), orderBefore,
                       "сохранение не должно перемещать проект в массиве — иначе списки прыгают при вводе")
    }
}
