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
        store = AppStore(vaultURL: vaultURL, notificationService: NotificationService(client: FakeNotificationClient()))
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

        let project = try await makeProject("Цель перехода")
        store.openProject(project.id) // повторное открытие не добавляет шаг
        XCTAssertEqual(store.destination, .projects)
        XCTAssertEqual(store.projectsPresentation, .editor)
        XCTAssertTrue(store.canGoBack)

        store.goBack()
        XCTAssertEqual(store.destination, .today, "один переход — один шаг назад")
        XCTAssertFalse(store.canGoBack)
        XCTAssertTrue(store.canGoForward)

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

        let second = AppStore(vaultURL: vaultURL, notificationService: NotificationService(client: FakeNotificationClient()))
        XCTAssertEqual(second.palette, .purple, "выбор палитры должен читаться из UserDefaults")

        second.palette = .teal
        let third = AppStore(vaultURL: vaultURL, notificationService: NotificationService(client: FakeNotificationClient()))
        XCTAssertEqual(third.palette, .teal)
    }

    func testInterfaceModePersists() {
        defer { UserDefaults.standard.removeObject(forKey: "interfaceMode") }
        XCTAssertEqual(store.interfaceMode, .detailed, "по умолчанию подробный вид")

        store.interfaceMode = .focused
        XCTAssertEqual(AppStore(vaultURL: vaultURL, notificationService: NotificationService(client: FakeNotificationClient())).interfaceMode, .focused)
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

    func testArtifactsAddAndRemove() async throws {
        let project = try await makeProject("Ссылки")
        await store.addArtifact(title: "Figma", url: "https://figma.com/file/1", to: project)
        XCTAssertEqual(try current().artifacts.count, 1)
        await store.reload()
        XCTAssertEqual(try current().artifacts.first?.url, "https://figma.com/file/1", "артефакт сохраняется в Project.md")

        await store.addArtifact(title: "", url: "мусор", to: try current())
        XCTAssertEqual(try current().artifacts.count, 1, "невалидный URL не добавляется")

        let artifact = try XCTUnwrap(try current().artifacts.first)
        await store.removeArtifact(artifact, from: try current())
        XCTAssertTrue(try current().artifacts.isEmpty)
    }

    func testDuplicateTaskInsertsAfterOriginal() async throws {
        let project = try await makeProject("Дубли")
        await store.addTask(title: "Оригинал", dueDate: nil, to: project)
        let task = try XCTUnwrap(try current().openTasks.first)

        await store.duplicateTask(task, in: try current())

        let tasks = try current().tasks
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks.map(\.title), ["Оригинал", "Оригинал"], "копия встаёт сразу после оригинала")
        XCTAssertNotEqual(tasks[0].id, tasks[1].id)
        await store.reload()
        XCTAssertEqual(try current().tasks.count, 2, "дубликат сохраняется на диск")
    }

    // MARK: - Стабильность порядка

    func testSavingDoesNotReorderMasterArray() async throws {
        _ = try await makeProject("Альфа")
        try await Task.sleep(for: .milliseconds(30))
        _ = try await makeProject("Бета")

        let orderBefore = store.projects.map(\.title)
        let groupOrderBefore = store.projects.groupedByQuarter().flatMap { $0.projects.map(\.id) }
        XCTAssertEqual(orderBefore, ["Альфа", "Бета"], "порядок создания без пересортировки")

        var older = try XCTUnwrap(store.projects.first { $0.title == "Альфа" })
        older.summary = "обновлённый текст"
        await store.saveProject(older)

        XCTAssertEqual(store.projects.map(\.title), orderBefore,
                       "сохранение не должно перемещать проект в массиве — иначе списки прыгают при вводе")
        XCTAssertEqual(store.projects.groupedByQuarter().flatMap { $0.projects.map(\.id) }, groupOrderBefore,
                       "группировка для навигации тоже должна сохранять порядок при записи")
    }
    func testSwitchingProjectsAddsOneHistoryStep() async throws {
        let first = try await makeProject("Первый")
        let second = try await makeProject("Второй")
        store.open(.today)
        store.openProject(first.id)
        store.openProject(second.id)
        store.goBack()
        XCTAssertEqual(store.selectedProjectID, first.id)
        store.goBack()
        XCTAssertEqual(store.destination, .today)
        store.goForward()
        XCTAssertEqual(store.selectedProjectID, first.id)
        store.open(.archive)
        XCTAssertFalse(store.canGoForward)
    }

    func testStaleProjectCopiesDoNotLoseTasksOrLegacyMetadata() async throws {
        let project = try await makeProject("Старый проект", epic: "Эпик")
        var legacy = project
        legacy.parentProject = "Родитель"
        legacy.summary = "Описание"
        legacy.tags = ["важное"]
        await store.saveProject(legacy)
        await store.addTask(title: "Первая", dueDate: nil, to: project)
        await store.addTask(title: "Вторая", dueDate: nil, to: project)
        await store.renameProject(project, to: "Новое имя")
        await store.reload()
        let value = try current()
        XCTAssertEqual(value.tasks.map(\.title), ["Первая", "Вторая"])
        XCTAssertEqual(value.title, "Новое имя")
        XCTAssertEqual(value.epic, "Эпик")
        XCTAssertEqual(value.parentProject, "Родитель")
        XCTAssertEqual(value.summary, "Описание")
        XCTAssertEqual(value.tags, ["важное"])
    }

    func testConcurrentStatusEditsUseOneFileAndMergeFields() async throws {
        let project = try await makeProject("День")
        async let status = store.setDailyStatus(text: "Результат", blockers: nil, for: project, on: .now)
        async let blockers = store.setDailyStatus(text: nil, blockers: "Жду ответ", for: project, on: .now)
        _ = await (status, blockers)
        await store.reload()
        let value = try current()
        XCTAssertEqual(value.statuses.count, 1)
        XCTAssertEqual(value.statuses.first?.status, "Результат")
        XCTAssertEqual(value.statuses.first?.blockers, "Жду ответ")
    }

    func testStatusEditorReplacesAndClearsCheckboxesImmediately() async throws {
        let project = try await makeProject("Чекбоксы")
        await store.setDailyStatus(text: "План\n- [ ] старое", blockers: "Блокер", for: project, on: .now)
        XCTAssertEqual(try current().statuses.first?.tasks.count, 1)
        await store.setDailyStatus(text: "Готово\n- [x] новое", blockers: "", for: project, on: .now, replacesTasks: true)
        XCTAssertEqual(try current().statuses.first?.tasks.map(\.title), ["новое"])
        XCTAssertEqual(try current().statuses.first?.tasks.first?.isDone, true)
        await store.setDailyStatus(text: "", blockers: "", for: project, on: .now, replacesTasks: true)
        await store.reload()
        XCTAssertEqual(try current().statuses.first?.editableMarkdown, "")
        XCTAssertEqual(try current().statuses.first?.blockers, "")
    }

    func testStatusSurvivesProjectMoveAndLaterEdit() async throws {
        let project = try await makeProject("Перенос")
        await store.setDailyStatus(text: "До переноса", blockers: nil, for: project, on: .now)
        await store.archive(project)
        await store.setDailyStatus(text: "После переноса", blockers: nil, for: project, on: .now)
        await store.restore(project)
        await store.setDailyStatus(text: nil, blockers: "После возврата", for: project, on: .now)
        await store.reload()
        let value = try current()
        XCTAssertEqual(value.statuses.count, 1)
        XCTAssertEqual(value.statuses.first?.status, "После переноса")
        XCTAssertEqual(value.statuses.first?.blockers, "После возврата")
        XCTAssertEqual(value.statuses.first?.fileURL?.deletingLastPathComponent().deletingLastPathComponent(), value.folderURL)
    }

    func testFailedStatusSaveReturnsFalseAndKeepsModel() async throws {
        let project = try await makeProject("Ошибка")
        let folder = try XCTUnwrap(project.folderURL)
        let statuses = folder.appendingPathComponent("Statuses")
        try Data("занято файлом".utf8).write(to: statuses)
        let saved = await store.setDailyStatus(text: "Не потерять", blockers: nil, for: project, on: .now)
        XCTAssertFalse(saved)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(try current().statuses.isEmpty)
    }

    func testEditingDeletedTaskReportsFailure() async throws {
        let project = try await makeProject("Удалённая задача")
        let missing = ProjectTask(title: "Черновик", isDone: false)
        let saved = await store.updateTask(missing, in: project)
        XCTAssertFalse(saved)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(try current().tasks.isEmpty)
    }

    func testAmbiguousMarkdownKeepsPreviouslySavedStatus() async throws {
        let project = try await makeProject("Markdown")
        await store.setDailyStatus(text: "Сохранённый текст", blockers: "Блокер", for: project, on: .now)
        for draft in ["```swift\nlet value = 1", "Текст\n## Блокеры\nПродолжение"] {
            let saved = await store.setDailyStatus(text: draft, blockers: "Новая версия", for: project, on: .now)
            XCTAssertFalse(saved)
            XCTAssertNotNil(store.errorMessage)
        }
        await store.reload()
        XCTAssertEqual(try current().statuses.first?.status, "Сохранённый текст")
        XCTAssertEqual(try current().statuses.first?.blockers, "Блокер")
    }

    func testQuickStatusAppendsWithoutNavigationOrLosingCheckboxes() async throws {
        let project = try await makeProject("Заметка")
        await store.setDailyStatus(text: "Утро\n- [x] первая", blockers: "Старый блокер", for: project, on: .now)
        store.open(.today)
        store.quickStatusDraft.projectID = project.id
        store.quickStatusDraft.text = "## Статус\nВечер\n- [ ] вторая\n## Блокеры\nНовый блокер"
        let saved = await store.saveQuickStatus()
        XCTAssertTrue(saved)
        XCTAssertEqual(store.destination, .today)
        XCTAssertTrue(store.quickStatusDraft.text.isEmpty)
        await store.reload()
        let entry = try XCTUnwrap(try current().dailyStatus(on: .now))
        XCTAssertTrue(entry.status.contains("Утро"))
        XCTAssertTrue(entry.status.contains("Вечер"))
        XCTAssertEqual(entry.tasks.map(\.title), ["первая", "вторая"])
        XCTAssertTrue(entry.tasks[0].isDone)
        XCTAssertEqual(entry.blockers, "Старый блокер\n\nНовый блокер")
    }

    func testInvalidQuickStatusKeepsDraftAndDoesNotWrite() async throws {
        let project = try await makeProject("Черновик")
        store.quickStatusDraft.projectID = project.id
        store.quickStatusDraft.text = "```незакрытый"
        let saved = await store.saveQuickStatus()
        XCTAssertFalse(saved)
        XCTAssertEqual(store.quickStatusDraft.text, "```незакрытый")
        XCTAssertNotNil(store.quickStatusDraft.error)
        XCTAssertTrue(try current().statuses.isEmpty)
    }

    func testEditingArtifactPreservesIdentityAndLegacyMetadata() async throws {
        let project = try await makeProject("Ссылки", epic: "Старое")
        await store.addArtifact(title: "Было", url: "https://example.com/old", to: project)
        let artifact = try XCTUnwrap(try current().artifacts.first)
        let saved = await store.saveArtifact(id: artifact.id, title: "Стало", url: "https://example.com/new", in: project)
        XCTAssertTrue(saved)
        await store.reload()
        XCTAssertEqual(try current().artifacts.count, 1)
        XCTAssertEqual(try current().artifacts[0].id, artifact.id)
        XCTAssertEqual(try current().artifacts[0].title, "Стало")
        XCTAssertEqual(try current().epic, "Старое")
    }

    func testNotificationCompletionIsIdempotentAfterReload() async throws {
        let project = try await makeProject("Уведомление")
        await store.addTask(title: "Задача", dueDate: nil, to: project)
        let taskID = try XCTUnwrap(try current().tasks.first?.id)
        await store.reload()
        XCTAssertEqual(try current().tasks[0].id, taskID)
        let first = await store.completeTaskFromNotification(projectID: project.id, taskID: taskID)
        let second = await store.completeTaskFromNotification(projectID: project.id, taskID: taskID)
        XCTAssertTrue(first && second)
        XCTAssertTrue(try current().tasks[0].isDone)
    }

    func testColdStartNotificationWaitsForVaultLoad() async throws {
        let project = try await makeProject("При запуске")
        let fresh = AppStore(vaultURL: vaultURL, notificationService: NotificationService(client: FakeNotificationClient()))
        fresh.handle(.openProject(project.id))
        await fresh.reload()
        XCTAssertEqual(fresh.selectedProjectID, project.id)
        XCTAssertEqual(fresh.destination, .projects)
    }

    func testCachedOverviewAndAgendaInvalidateWhenTaskChanges() async throws {
        let project = try await makeProject("Сводка")
        XCTAssertEqual(store.overview.totalTasks, 0)
        XCTAssertTrue(store.taskAgenda.unscheduled.isEmpty)
        await store.addTask(title: "Новая", dueDate: nil, to: project)
        XCTAssertEqual(store.overview.totalTasks, 1)
        XCTAssertEqual(store.taskAgenda.unscheduled.count, 1)
        let task = try XCTUnwrap(try current().tasks.first)
        await store.toggleTask(task, in: try current())
        XCTAssertEqual(store.overview.doneTasks, 1)
        XCTAssertTrue(store.taskAgenda.unscheduled.isEmpty)
        store.open(.statuses)
        store.goBack()
        XCTAssertEqual(store.destination, .projects)
    }

}
