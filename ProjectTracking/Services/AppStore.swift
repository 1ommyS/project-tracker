import AppKit
import Foundation
import Observation

enum SidebarDestination: String, CaseIterable, Identifiable {
    case today, statuses, projects, overdue, search, archive, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Сегодня"
        case .statuses: "Статусы"
        case .projects: "Проекты"
        case .overdue: "Просрочено"
        case .search: "Поиск"
        case .archive: "Архив"
        case .settings: "Настройки"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .statuses: "tablecells"
        case .projects: "square.stack.3d.up.fill"
        case .overdue: "clock.badge.exclamationmark"
        case .search: "magnifyingglass"
        case .archive: "archivebox.fill"
        case .settings: "gearshape.fill"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "Системная"; case .light: "Светлая"; case .dark: "Тёмная" } }
}

/// Режим плотности интерфейса: «Фокус» — только срочное и компактные списки,
/// «Подробно» — полные карточки, метрики и история.
enum InterfaceMode: String, CaseIterable, Identifiable {
    case focused, detailed
    var id: String { rawValue }
    var title: String { switch self { case .focused: "Фокус"; case .detailed: "Подробно" } }
    var symbol: String { switch self { case .focused: "scope"; case .detailed: "list.bullet" } }
}

enum ProjectsPresentation: String {
    case feed, editor
    var title: String { switch self { case .feed: "Лента"; case .editor: "Редактор" } }
}

@MainActor @Observable
final class AppStore {
    var projects: [Project] = [] { didSet { projectsRevision &+= 1 } }
    private(set) var projectsRevision = 0
    @ObservationIgnored private var cachedOverview: (revision: Int, value: ProjectOverview)?
    var overview: ProjectOverview {
        if let cachedOverview, cachedOverview.revision == projectsRevision { return cachedOverview.value }
        let value = ProjectOverview(projects: projects)
        cachedOverview = (projectsRevision, value)
        return value
    }
    var destination: SidebarDestination = .today { didSet { pushNavigation() } }
    var selectedProjectID: UUID? { didSet { pushNavigation() } }
    var projectsPresentation: ProjectsPresentation = .feed { didSet { pushNavigation() } }
    var isLoading = true
    var errorMessage: String?
    var searchQuery = ""
    var searchFocusRequest = 0
    var recentProjectsRequest = 0
    var shortcutHelpRequest = 0
    var quickTaskRequest = 0
    var whatsNewRequest = 0
    var quickTaskProjectID: UUID?
    let quickStatusDraft = QuickStatusDraft()
    @ObservationIgnored var openMainWindow: (() -> Void)?
    private var hasStarted = false
    private var clockMinute = Int(Date.now.timeIntervalSince1970 / 60)
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var cachedAgenda: (revision: Int, minute: Int, zone: String, value: TaskAgendaSnapshot)?
    var taskAgenda: TaskAgendaSnapshot {
        let minute = Int(Date.now.timeIntervalSince1970 / 60)
        _ = clockMinute // invalidates the cached projection while the app stays open
        let zone = Calendar.current.timeZone.identifier
        if let cachedAgenda, cachedAgenda.revision == projectsRevision, cachedAgenda.minute == minute, cachedAgenda.zone == zone {
            return cachedAgenda.value
        }
        let value = TaskAgendaSnapshot(tasks: allOpenTasks, now: .now)
        cachedAgenda = (projectsRevision, minute, zone, value)
        return value
    }
    private var hasLoaded = false
    private var pendingNotificationEvents: [NotificationService.Event] = []
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }
    var palette: AppPalette {
        didSet { UserDefaults.standard.set(palette.rawValue, forKey: Keys.palette) }
    }
    var interfaceMode: InterfaceMode {
        didSet { UserDefaults.standard.set(interfaceMode.rawValue, forKey: Keys.interfaceMode) }
    }
    private(set) var vaultURL: URL
    let notifications: NotificationService

    private var repository: MarkdownRepository
    private let monitor = VaultMonitor()
    private var scopedURL: URL?
    var isArchivingVault = false

    convenience init() {
        self.init(vaultURL: Self.resolveStoredVault() ?? Self.defaultVaultURL)
    }

    init(vaultURL: URL, notificationService: NotificationService? = nil) {
        notifications = notificationService ?? NotificationService()
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? "system") ?? .system
        palette = AppPalette(rawValue: UserDefaults.standard.string(forKey: Keys.palette) ?? "") ?? .blue
        interfaceMode = InterfaceMode(rawValue: UserDefaults.standard.string(forKey: Keys.interfaceMode) ?? "") ?? .detailed
        self.vaultURL = vaultURL
        repository = MarkdownRepository(rootURL: vaultURL)
        if vaultURL.startAccessingSecurityScopedResource() { scopedURL = vaultURL }
        notifications.onEvent = { [weak self] event in self?.handle(event) }
        applyDemoEnvironment()
        pushNavigation()
    }

    /// Демо-переменные окружения — выставляют стартовое состояние приложения
    /// (TRACE_TAB, TRACE_PRESENTATION=editor, TRACE_MODE=focused, TRACE_SELECT=1);
    /// используются для скриншотов и автоматических демонстраций.
    private func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let tab = env["TRACE_TAB"], let destination = SidebarDestination(rawValue: tab) {
            self.destination = destination
        }
        if env["TRACE_PRESENTATION"] == "editor" { projectsPresentation = .editor }
        if env["TRACE_MODE"] == "focused" { interfaceMode = .focused }
    }

    var activeProjects: [Project] { overview.active }
    var archivedProjects: [Project] { overview.archived }
    var selectedProject: Project? { selectedProjectID.flatMap { overview.byID[$0] } }
    var allOpenTasks: [TaskContext] { overview.openTasks }

    var overdueTasks: [TaskContext] { taskAgenda.overdue }
    var urgentTaskCount: Int { taskAgenda.urgentCount }

    func openSearch() {
        destination = .search
        searchFocusRequest &+= 1
    }

    func openRecentProjects() {
        recentProjectsRequest &+= 1
    }

    func openShortcutHelp() {
        shortcutHelpRequest &+= 1
    }

    /// Показать экран «Что нового» (меню Справка).
    func openWhatsNew() {
        whatsNewRequest &+= 1
    }

    /// Автопоказ при смене версии приложения; на самом первом запуске молча
    /// запоминаем версию, чтобы не встречать пользователя экраном релизов.
    private func presentWhatsNewIfVersionChanged() {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let seen = UserDefaults.standard.string(forKey: Keys.lastSeenVersion)
        guard seen != current else { return }
        UserDefaults.standard.set(current, forKey: Keys.lastSeenVersion)
        if seen != nil {
            whatsNewRequest &+= 1
        }
    }

    func open(_ destination: SidebarDestination) {
        if destination == .projects { openProjectsList(); return }
        self.destination = destination
    }

    func openProject(_ id: UUID) {
        navigate(to: NavigationState(destination: .projects, projectID: id, presentation: .editor))
    }

    func openProjectsList() {
        navigate(to: NavigationState(destination: .projects, projectID: nil, presentation: .feed))
    }

    // MARK: - История навигации

    struct NavigationState: Equatable {
        var destination: SidebarDestination
        var projectID: UUID?
        var presentation: ProjectsPresentation
    }

    private var navigationHistory: [NavigationState] = []
    private var navigationIndex = -1
    private var isRestoringNavigation = false

    var canGoBack: Bool { navigationIndex > 0 }
    var canGoForward: Bool { navigationIndex < navigationHistory.count - 1 }

    func goBack() {
        guard navigationIndex > 0 else { return }
        navigationIndex -= 1
        restoreNavigation(navigationHistory[navigationIndex])
    }

    func goForward() {
        guard navigationIndex < navigationHistory.count - 1 else { return }
        navigationIndex += 1
        restoreNavigation(navigationHistory[navigationIndex])
    }

    private func restoreNavigation(_ state: NavigationState) {
        isRestoringNavigation = true
        destination = state.destination
        selectedProjectID = state.projectID
        projectsPresentation = state.presentation
        isRestoringNavigation = false
    }

    private func navigate(to state: NavigationState) {
        restoreNavigation(state)
        pushNavigation()
    }

    private func pushNavigation() {
        guard !isRestoringNavigation else { return }
        let isProject = destination == .projects && projectsPresentation == .editor
        let state = NavigationState(destination: destination, projectID: isProject ? selectedProjectID : nil,
                                    presentation: isProject ? .editor : .feed)
        if navigationIndex >= 0, navigationHistory[navigationIndex] == state { return }
        navigationHistory.removeSubrange(min(navigationIndex + 1, navigationHistory.count)...)
        navigationHistory.append(state)
        if navigationHistory.count > 60 { navigationHistory.removeFirst(navigationHistory.count - 60) }
        navigationIndex = navigationHistory.count - 1
    }

    func openQuickTask() {
        guard let project = selectedProject.flatMap({ $0.isArchived ? nil : $0 }) ?? activeProjects.first else {
            errorMessage = "Сначала создайте проект, чтобы добавить задачу."
            return
        }
        openProject(project.id)
        quickTaskProjectID = project.id
        quickTaskRequest &+= 1
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.clockMinute = Int(Date.now.timeIntervalSince1970 / 60)
            }
        }
        await reload()
        if ProcessInfo.processInfo.environment["TRACE_SELECT"] == "1", selectedProjectID == nil {
            selectedProjectID = projects.first?.id
        }
        observeVault(at: vaultURL)
        presentWhatsNewIfVersionChanged()
        // Запуск только читает разрешение. Запрос — при добавлении напоминания
        // или явном действии в настройках, без открытия Системных настроек.
        await notifications.syncIfAllowed(projects: projects)
    }

    func reload(showSpinner: Bool = true, changedURLs: Set<URL> = []) async {
        if showSpinner { isLoading = true }
        for pending in pendingWrites.values { _ = await pending.value }
        do {
            let oldSchedule = NotificationPlan.inputSignature(projects: projects)
            var revision: Int
            var loaded: [Project]
            var invalidated = changedURLs
            // Wait for a coherent snapshot without blocking the main thread.
            repeat {
                revision = projectsRevision
                loaded = try await repository.loadProjects(changedURLs: invalidated)
                invalidated = []
            } while projectsRevision != revision
            let incoming = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let existingIDs = Set(projects.map(\.id))
            let stable = projects.compactMap { incoming[$0.id] } + loaded.filter { !existingIDs.contains($0.id) }
            if projects != stable { projects = stable }
            if oldSchedule != NotificationPlan.inputSignature(projects: stable), notifications.authorization == .allowed {
                await notifications.syncIfAllowed(projects: stable)
            }
            if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
                self.selectedProjectID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось прочитать хранилище: \(error.localizedDescription)"
        }
        isLoading = false
        hasLoaded = true
        let pendingEvents = pendingNotificationEvents
        pendingNotificationEvents.removeAll()
        for event in pendingEvents { handle(event) }
    }

    func createProject(title: String, epic: String, parentProject: String, summary: String, tags: [String], state: ProjectState) async -> Project? {
        let project = Project(id: UUID(), title: title, epic: epic, parentProject: parentProject,
                              summary: summary, tags: tags, state: state,
                              tasks: [], createdAt: .now, updatedAt: .now,
                              isArchived: false, folderURL: nil)
        do {
            let saved = try await repository.saveProject(project)
            replace(saved)
            openProject(saved.id)
            return saved
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    // Все записи одного проекта сериализуются, включая статусы и перенос папки.
    // Изменения применяются к свежей модели после предыдущей записи, а не к копии из View.
    private var pendingWrites: [UUID: Task<Bool, Never>] = [:]
    private var deletingProjects: Set<UUID> = []

    private enum WriteError: LocalizedError {
        case missingTask, missingArtifact
        var errorDescription: String? {
            switch self {
            case .missingTask: "Задача уже удалена или изменена в хранилище. Откройте её заново."
            case .missingArtifact: "Ссылка уже удалена из проекта. Добавьте её заново."
            }
        }
    }

    @discardableResult
    private func enqueueWrite(for id: UUID,
                              operation: @escaping @MainActor (Project) async throws -> Project) async -> Bool {
        guard !deletingProjects.contains(id) else { return false }
        let previous = pendingWrites[id]
        let task = Task { @MainActor in
            if let previous { _ = await previous.value }
            guard let current = projects.first(where: { $0.id == id }) else {
                errorMessage = "Проект больше не доступен в хранилище."
                return false
            }
            do {
                let saved = try await operation(current)
                replace(saved)
                return true
            } catch {
                errorMessage = "Не удалось сохранить проект: \(error.localizedDescription)"
                return false
            }
        }
        pendingWrites[id] = task
        return await task.value
    }

    @discardableResult
    private func updateProject(_ id: UUID, change: @escaping @MainActor (inout Project) throws -> Void) async -> Bool {
        var tasksChanged = false
        let saved = await enqueueWrite(for: id) { current in
            var value = current
            try change(&value)
            guard value != current else { return current }
            value.updatedAt = .now
            tasksChanged = NotificationPlan.inputSignature(projects: [current]) != NotificationPlan.inputSignature(projects: [value])
            return try await self.repository.saveProject(value)
        }
        if saved, tasksChanged {
            Task { await notifications.syncIfAllowed(projects: projects) }
        }
        return saved
    }

    @discardableResult
    func saveProject(_ project: Project) async -> Bool {
        await updateProject(project.id) { value in
            // Статусы записываются отдельно; полная копия проекта не должна их откатывать.
            let statuses = value.statuses
            let folder = value.folderURL
            value = project
            value.statuses = statuses
            value.folderURL = folder
        }
    }

    func setProjectState(_ project: Project, to state: ProjectState) async {
        await updateProject(project.id) { $0.state = state; $0.isArchived = state == .archived }
    }

    // MARK: - Задачи

    @discardableResult
    func addTask(title: String, dueDate: Date?, to project: Project) async -> Bool {
        guard let title = title.nilIfBlank else { return false }
        let saved = await updateProject(project.id) {
            $0.tasks.append(ProjectTask(title: title, isDone: false, dueDate: dueDate))
        }
        if saved, dueDate != nil { await notifications.authorizeAndSync(projects: projects) }
        return saved
    }

    func toggleTask(_ task: ProjectTask, in project: Project) async {
        await updateProject(project.id) { value in
            guard let index = value.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            value.tasks[index].isDone.toggle()
        }
    }

    @discardableResult
    func updateTask(_ task: ProjectTask, in project: Project) async -> Bool {
        let saved = await updateProject(project.id) { value in
            guard let index = value.tasks.firstIndex(where: { $0.id == task.id }) else { throw WriteError.missingTask }
            value.tasks[index] = task
        }
        if saved, !task.isDone, task.dueDate != nil { await notifications.authorizeAndSync(projects: projects) }
        return saved
    }

    @discardableResult
    func deleteTask(_ task: ProjectTask, in project: Project) async -> Bool {
        await updateProject(project.id) { $0.tasks.removeAll { $0.id == task.id } }
    }

    func duplicateTask(_ task: ProjectTask, in project: Project) async {
        await updateProject(project.id) { value in
            let copy = ProjectTask(title: task.title, isDone: task.isDone, dueDate: task.dueDate)
            let index = value.tasks.firstIndex(where: { $0.id == task.id }).map { $0 + 1 } ?? value.tasks.count
            value.tasks.insert(copy, at: index)
        }
    }

    // MARK: - Артефакты

    @discardableResult
    func saveArtifact(id: UUID? = nil, title: String, url: String, in project: Project) async -> Bool {
        let link: ArtifactLink
        do { link = try ArtifactLink(title: title, url: url) }
        catch { errorMessage = error.localizedDescription; return false }
        return await updateProject(project.id) { value in
            if let id {
                guard let index = value.artifacts.firstIndex(where: { $0.id == id }) else { throw WriteError.missingArtifact }
                value.artifacts[index].title = link.title
                value.artifacts[index].url = link.url
            } else {
                value.artifacts.append(ProjectArtifact(title: link.title, url: link.url))
            }
        }
    }

    func addArtifact(title: String, url: String, to project: Project) async {
        await saveArtifact(title: title, url: url, in: project)
    }

    func removeArtifact(_ artifact: ProjectArtifact, from project: Project) async {
        await updateProject(project.id) { $0.artifacts.removeAll { $0.id == artifact.id } }
    }

    // MARK: - Инлайн-переименование

    /// Правка дневного статуса: text/blockers = nil — не трогаем, пустая строка — очищает.
    @discardableResult
    func setDailyStatus(text: String?, blockers: String?, for project: Project, on date: Date,
                        replacesTasks: Bool = false) async -> Bool {
        await enqueueWrite(for: project.id) { current in
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: date)
            var entry = current.dailyStatus(on: day)
                ?? DailyStatus(projectID: current.id, date: day)
            if let text {
                entry.status = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if replacesTasks { entry.tasks = [] }
            }
            if let blockers { entry.blockers = blockers.trimmingCharacters(in: .whitespacesAndNewlines) }
            entry.updatedAt = .now
            let saved = try await self.repository.saveStatus(entry, for: current)
            var value = current
            value.statuses.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
            value.statuses.append(saved)
            value.statuses.sort { $0.date > $1.date }
            return value
        }
    }

    func prepareQuickStatus() {
        guard !quickStatusDraft.isSaving, quickStatusDraft.text.nilIfBlank == nil else { return }
        if !activeProjects.contains(where: { $0.id == quickStatusDraft.projectID }) {
            quickStatusDraft.projectID = selectedProject.flatMap { $0.isCompleted ? nil : $0.id } ?? activeProjects.first?.id
        }
        quickStatusDraft.day = .now
        quickStatusDraft.error = nil
    }

    @discardableResult
    func saveQuickStatus() async -> Bool {
        guard !quickStatusDraft.isSaving else { return false }
        guard let id = quickStatusDraft.projectID else { quickStatusDraft.error = "Выберите проект."; return false }
        let transfer: StatusTransfer
        do { transfer = try StatusTransfer.parse(quickStatusDraft.text) }
        catch { quickStatusDraft.error = error.localizedDescription; return false }
        let day = quickStatusDraft.day
        quickStatusDraft.isSaving = true
        defer { quickStatusDraft.isSaving = false }
        let saved = await appendDailyStatus(transfer, projectID: id, on: day)
        if saved { quickStatusDraft.text = ""; quickStatusDraft.error = nil }
        else { quickStatusDraft.error = errorMessage ?? "Не удалось добавить статус." }
        return saved
    }

    @discardableResult
    func appendDailyStatus(_ transfer: StatusTransfer, projectID: UUID, on date: Date) async -> Bool {
        await enqueueWrite(for: projectID) { current in
            var entry = current.dailyStatus(on: date)
                ?? DailyStatus(projectID: current.id, date: Calendar.current.startOfDay(for: date))
            entry.status = [entry.editableMarkdown, transfer.status].filter { $0.nilIfBlank != nil }.joined(separator: "\n\n")
            entry.tasks = []
            entry.blockers = [entry.blockers, transfer.blockers].filter { $0.nilIfBlank != nil }.joined(separator: "\n\n")
            entry.updatedAt = .now
            let saved = try await self.repository.saveStatus(entry, for: current)
            var value = current
            value.statuses.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
            value.statuses.append(saved)
            value.statuses.sort { $0.date > $1.date }
            return value
        }
    }

    func toggleStatusTask(_ task: StatusTask, in status: DailyStatus, for project: Project) async {
        await enqueueWrite(for: project.id) { current in
            guard var entry = current.statuses.first(where: { $0.id == status.id }),
                  let index = entry.tasks.firstIndex(where: { $0.id == task.id }) else { return current }
            entry.tasks[index].isDone.toggle()
            entry.updatedAt = .now
            let saved = try await self.repository.saveStatus(entry, for: current)
            var value = current
            if let index = value.statuses.firstIndex(where: { $0.id == saved.id }) { value.statuses[index] = saved }
            return value
        }
    }

    func setProjectStatus(_ project: Project, to status: String) async {
        await updateProject(project.id) { $0.status = status.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @discardableResult
    func renameProject(_ project: Project, to newTitle: String) async -> Bool {
        guard let title = newTitle.nilIfBlank else { return false }
        return await updateProject(project.id) { $0.title = title }
    }

    func renameTask(_ task: ProjectTask, to newTitle: String, in project: Project) async {
        guard let title = newTitle.nilIfBlank, title != task.title else { return }
        await updateProject(project.id) { value in
            guard let index = value.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            value.tasks[index].title = title
        }
    }

    func setTaskDueDate(_ task: ProjectTask, to date: Date?, in project: Project) async {
        let saved = await updateProject(project.id) { value in
            guard let index = value.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            value.tasks[index].dueDate = date
        }
        if saved, date != nil { await notifications.authorizeAndSync(projects: projects) }
    }

    func archive(_ project: Project) async {
        await updateProject(project.id) { $0.isArchived = true; $0.state = .archived }
    }

    func restore(_ project: Project) async {
        await updateProject(project.id) { $0.isArchived = false; $0.state = .active }
    }

    func delete(_ project: Project) async {
        guard deletingProjects.insert(project.id).inserted else { return }
        defer { deletingProjects.remove(project.id) }
        if let pending = pendingWrites[project.id] { _ = await pending.value }
        guard let current = projects.first(where: { $0.id == project.id }) else { return }
        do {
            try await repository.deleteProject(current)
            projects.removeAll { $0.id == project.id }
            pendingWrites.removeValue(forKey: project.id)
            if selectedProjectID == project.id { openProjectsList() }
            await notifications.syncIfAllowed(projects: projects)
        } catch { errorMessage = "Не удалось переместить проект в Корзину: \(error.localizedDescription)" }
    }

    /// Выгрузка хранилища в архив (rar при наличии, иначе zip) —
    /// для безопасной репликации данных между обновлениями.
    func archiveVault() {
        let panel = NSSavePanel()
        panel.title = "Архив хранилища"
        panel.message = "Выгрузить текущее хранилище для репликации"
        let stamp = "trace-vault-" + Date.now.formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = stamp
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let output = url.deletingPathExtension()
        guard !isArchivingVault else { return }
        let script = Bundle.main.url(forResource: "archive-vault", withExtension: "sh")
            ?? URL(fileURLWithPath: "scripts/archive-vault.sh")
        isArchivingVault = true
        Task {
            defer { isArchivingVault = false }
            do {
                for pending in pendingWrites.values { _ = await pending.value }
                try await repository.archiveVault(using: script, output: output)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func chooseVault() async {
        guard !isArchivingVault else { return }
        let panel = NSOpenPanel()
        panel.title = "Выберите папку или Obsidian Vault"
        panel.prompt = "Использовать"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            for pending in pendingWrites.values { _ = await pending.value }
            pendingWrites.removeAll()
            UserDefaults.standard.set(bookmark, forKey: Keys.bookmark)
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
            vaultURL = url
            navigate(to: NavigationState(destination: .today, projectID: nil, presentation: .feed))
            navigationHistory.removeAll()
            navigationIndex = -1
            pushNavigation()
            await repository.setRootURL(url)
            await reload()
            observeVault(at: url)
        } catch { errorMessage = "Не удалось сохранить доступ к папке: \(error.localizedDescription)" }
    }

    func searchHits(query: String) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var result: [SearchHit] = []
        for project in projects {
            if project.title.range(of: needle, options: options) != nil
                || project.summary.range(of: needle, options: options) != nil
                || project.tags.contains(where: { $0.range(of: needle, options: options) != nil }) {
                result.append(SearchHit(id: "project-\(project.id)", projectID: project.id, kind: .project,
                                        title: project.title, excerpt: excerpt(from: project.summary, matching: needle), date: project.updatedAt))
            }
            for task in project.tasks where task.title.range(of: needle, options: options) != nil {
                result.append(SearchHit(id: "task-\(task.id)", projectID: project.id, kind: .task,
                                        title: task.title, excerpt: project.title,
                                        date: task.dueDate ?? project.updatedAt))
            }
        }
        return result.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func handle(_ event: NotificationService.Event) {
        guard hasLoaded else { pendingNotificationEvents.append(event); return }
        switch event {
        case .openProject(let id):
            guard projects.contains(where: { $0.id == id }) else { return }
            openProject(id)
            openMainWindow?()
        case .completeTask(let projectID, let taskID):
            Task { await completeTaskFromNotification(projectID: projectID, taskID: taskID) }
        }
    }

    @discardableResult
    func completeTaskFromNotification(projectID: UUID, taskID: UUID) async -> Bool {
        await updateProject(projectID) { value in
            guard let index = value.tasks.firstIndex(where: { $0.id == taskID }) else { throw WriteError.missingTask }
            value.tasks[index].isDone = true
        }
    }

    private func excerpt(from text: String, matching query: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = flat.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(flat.prefix(140)) }
        let position = flat.distance(from: flat.startIndex, to: range.lowerBound)
        let start = flat.index(flat.startIndex, offsetBy: max(0, position - 45))
        let end = flat.index(start, offsetBy: min(150, flat.distance(from: start, to: flat.endIndex)))
        return (start == flat.startIndex ? "" : "…") + flat[start..<end] + (end == flat.endIndex ? "" : "…")
    }

    private func replace(_ project: Project) {
        // Порядок массива намеренно не меняем: пересортировка при каждом
        // автосохранении дёргает списки и сбивает фокус в поле ввода.
        // Порядок отображения задают экранные вычисления, с диска — reload().
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            if projects[index] != project { projects[index] = project }
        } else {
            projects.append(project)
        }
    }

    private func observeVault(at url: URL) {
        monitor.start(url: url) { [weak self] changed in
            guard let self else { return }
            Task { await self.reload(showSpinner: false, changedURLs: changed) }
        }
    }

    private static var defaultVaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pulseboard/Vault", isDirectory: true)
    }

    private static func resolveStoredVault() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Keys.bookmark) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let theme = "appTheme"
        static let palette = "appPalette"
        static let interfaceMode = "interfaceMode"
        static let lastSeenVersion = "lastSeenVersion"
    }
}
