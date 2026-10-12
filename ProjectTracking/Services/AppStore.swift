import AppKit
import Foundation
import Observation

enum SidebarDestination: String, CaseIterable, Identifiable {
    case today, projects, overdue, search, archive, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Сегодня"
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
    var projects: [Project] = []
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
    let notifications = NotificationService()

    private var repository: MarkdownRepository
    private let monitor = VaultMonitor()
    private var scopedURL: URL?
    private var selfWriteUntil = Date.distantPast

    convenience init() {
        self.init(vaultURL: Self.resolveStoredVault() ?? Self.defaultVaultURL)
    }

    init(vaultURL: URL) {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? "system") ?? .system
        palette = AppPalette(rawValue: UserDefaults.standard.string(forKey: Keys.palette) ?? "") ?? .blue
        interfaceMode = InterfaceMode(rawValue: UserDefaults.standard.string(forKey: Keys.interfaceMode) ?? "") ?? .detailed
        self.vaultURL = vaultURL
        repository = MarkdownRepository(rootURL: vaultURL)
        if vaultURL.startAccessingSecurityScopedResource() { scopedURL = vaultURL }
        notifications.onEvent = { [weak self] event in self?.handle(event) }
    }

    var activeProjects: [Project] { projects.filter { !$0.isArchived && $0.state != .archived && $0.state != .done } }
    var archivedProjects: [Project] { projects.filter { $0.isArchived || $0.state == .archived || $0.state == .done } }
    var selectedProject: Project? { projects.first { $0.id == selectedProjectID } }

    var allOpenTasks: [TaskContext] {
        activeProjects.flatMap { project in project.openTasks.map { TaskContext(project: project, task: $0) } }
    }

    /// Все просроченные открытые задачи, самые старые сверху.
    var overdueTasks: [TaskContext] {
        allOpenTasks
            .filter { context in context.task.dueDate.map { $0 < .now } ?? false }
            .sorted { ($0.task.dueDate ?? .distantPast) < ($1.task.dueDate ?? .distantPast) }
    }

    /// Просроченные и назначенные на сегодня — для бейджа «Сегодня».
    var urgentTaskCount: Int {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        return allOpenTasks.filter { context in
            guard let due = context.task.dueDate else { return false }
            return due < endOfToday
        }.count
    }

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
        self.destination = destination
    }

    func openProject(_ id: UUID) {
        selectedProjectID = id
        projectsPresentation = .editor
        destination = .projects
    }

    func openProjectsList() {
        projectsPresentation = .feed
        destination = .projects
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

    private func pushNavigation() {
        guard !isRestoringNavigation else { return }
        let state = NavigationState(destination: destination, projectID: selectedProjectID, presentation: projectsPresentation)
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
        selectedProjectID = project.id
        destination = .projects
        quickTaskProjectID = project.id
        quickTaskRequest &+= 1
    }

    func start() async {
        await reload()
        observeVault(at: vaultURL)
        presentWhatsNewIfVersionChanged()
        // Разрешение спрашиваем при первом запуске: без него напоминания
        // о сроках не появятся никогда, а пользователь этого не узнает.
        await notifications.authorizeAndSync(projects: projects)
    }

    func reload(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        do {
            projects = try await repository.loadProjects()
            // Холостое присваивание nil→nil попало бы в историю навигации.
            if selectedProjectID == nil, let first = projects.first?.id {
                selectedProjectID = first
            }
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось прочитать хранилище: \(error.localizedDescription)"
        }
        isLoading = false
        if notifications.authorization == .allowed {
            await notifications.sync(projects: projects)
        }
    }

    func createProject(title: String, epic: String, parentProject: String, summary: String, tags: [String], state: ProjectState) async -> Project? {
        let project = Project(id: UUID(), title: title, epic: epic, parentProject: parentProject,
                              summary: summary, tags: tags, state: state,
                              tasks: [], createdAt: .now, updatedAt: .now,
                              isArchived: false, folderURL: nil)
        do {
            markSelfWrite()
            let saved = try await repository.saveProject(project)
            replace(saved)
            selectedProjectID = saved.id
            destination = .projects
            return saved
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func saveProject(_ project: Project) async {
        var value = project
        value.updatedAt = .now
        let previous = projects.first(where: { $0.id == project.id })
        do {
            markSelfWrite()
            let saved = try await repository.saveProject(value)
            replace(saved)
            let tasksChanged = previous?.tasks != saved.tasks || previous?.isArchived != saved.isArchived
            if tasksChanged {
                if saved.tasks.contains(where: { !$0.isDone && $0.dueDate != nil }) {
                    await notifications.authorizeAndSync(projects: projects)
                } else {
                    await notifications.syncIfAllowed(projects: projects)
                }
            }
        } catch { errorMessage = "Не удалось сохранить проект: \(error.localizedDescription)" }
    }

    // MARK: - Задачи

    func addTask(title: String, dueDate: Date?, to project: Project) async {
        var value = project
        value.tasks.append(ProjectTask(title: title, isDone: false, dueDate: dueDate))
        await saveProject(value)
    }

    func toggleTask(_ task: ProjectTask, in project: Project) async {
        var value = task
        value.isDone.toggle()
        await updateTask(value, in: project)
    }

    func updateTask(_ task: ProjectTask, in project: Project) async {
        var value = project
        guard let index = value.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        value.tasks[index] = task
        await saveProject(value)
    }

    func deleteTask(_ task: ProjectTask, in project: Project) async {
        var value = project
        value.tasks.removeAll { $0.id == task.id }
        await saveProject(value)
    }

    // MARK: - Инлайн-переименование

    func renameProject(_ project: Project, to newTitle: String) async {
        guard let title = newTitle.nilIfBlank, title != project.title else { return }
        var value = project
        value.title = title
        await saveProject(value)
    }

    func renameTask(_ task: ProjectTask, to newTitle: String, in project: Project) async {
        guard let title = newTitle.nilIfBlank, title != task.title else { return }
        var value = task
        value.title = title
        await updateTask(value, in: project)
    }

    func setTaskDueDate(_ task: ProjectTask, to date: Date?, in project: Project) async {
        var value = task
        value.dueDate = date
        await updateTask(value, in: project)
    }

    func archive(_ project: Project) async {
        var value = project
        value.isArchived = true
        value.state = .archived
        await saveProject(value)
    }

    func restore(_ project: Project) async {
        var value = project
        value.isArchived = false
        value.state = .active
        await saveProject(value)
    }

    func delete(_ project: Project) async {
        do {
            markSelfWrite()
            try await repository.deleteProject(project)
            projects.removeAll { $0.id == project.id }
            if selectedProjectID == project.id { selectedProjectID = projects.first?.id }
            await notifications.syncIfAllowed(projects: projects)
        } catch { errorMessage = "Не удалось переместить проект в Корзину: \(error.localizedDescription)" }
    }

    func chooseVault() async {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку или Obsidian Vault"
        panel.prompt = "Использовать"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Keys.bookmark)
            scopedURL?.stopAccessingSecurityScopedResource()
            if url.startAccessingSecurityScopedResource() { scopedURL = url }
            vaultURL = url
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
                                        title: task.title, excerpt: project.pathLabel.isEmpty ? project.title : project.pathLabel,
                                        date: task.dueDate ?? project.updatedAt))
            }
        }
        return result.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func handle(_ event: NotificationService.Event) {
        switch event {
        case .openProject(let id):
            openProject(id)
        case .completeTask(let projectID, let taskID):
            guard let project = projects.first(where: { $0.id == projectID }),
                  let task = project.tasks.first(where: { $0.id == taskID }) else { return }
            Task { await toggleTask(task, in: project) }
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
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    private func markSelfWrite() { selfWriteUntil = Date().addingTimeInterval(1.2) }

    private func observeVault(at url: URL) {
        monitor.start(url: url) { [weak self] in
            guard let self, Date() > self.selfWriteUntil else { return }
            Task { await self.reload(showSpinner: false) }
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
