import AppKit
import Foundation
import Observation

enum SidebarDestination: String, CaseIterable, Identifiable {
    case today, projects, activity, search, archive, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Сегодня"
        case .projects: "Проекты"
        case .activity: "Активность"
        case .search: "Поиск"
        case .archive: "Архив"
        case .settings: "Настройки"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .projects: "square.stack.3d.up.fill"
        case .activity: "clock.arrow.circlepath"
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

@MainActor @Observable
final class AppStore {
    var projects: [Project] = []
    var destination: SidebarDestination = .today
    var selectedProjectID: UUID?
    var isLoading = true
    var errorMessage: String?
    var searchQuery = ""
    var searchFocusRequest = 0
    var recentProjectsRequest = 0
    var shortcutHelpRequest = 0
    var statusEditorRequest = 0
    var quickTaskRequest = 0
    var quickTaskProjectID: UUID?
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }
    var statusTemplate: String {
        didSet { UserDefaults.standard.set(statusTemplate, forKey: Keys.template) }
    }
    private(set) var vaultURL: URL
    let notifications = NotificationService()

    private var repository: MarkdownRepository
    private let monitor = VaultMonitor()
    private var scopedURL: URL?
    private var selfWriteUntil = Date.distantPast

    init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? "system") ?? .system
        statusTemplate = UserDefaults.standard.string(forKey: Keys.template) ?? "- Что сделано сегодня?\n- Что дальше?\n- Что мешает?"
        let resolved = Self.resolveStoredVault() ?? Self.defaultVaultURL
        vaultURL = resolved
        repository = MarkdownRepository(rootURL: resolved)
        if resolved.startAccessingSecurityScopedResource() { scopedURL = resolved }
    }

    var activeProjects: [Project] { projects.filter { !$0.isArchived && $0.state != .archived && $0.state != .done } }
    var archivedProjects: [Project] { projects.filter { $0.isArchived || $0.state == .archived || $0.state == .done } }
    var selectedProject: Project? { projects.first { $0.id == selectedProjectID } }
    var activity: [ActivityItem] {
        projects.flatMap { project in project.statuses.map { ActivityItem(id: $0.id, projectID: project.id, projectTitle: project.pathLabel, status: $0) } }
            .sorted { $0.status.date > $1.status.date }
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

    func open(_ destination: SidebarDestination) {
        self.destination = destination
    }

    func openStatusEditor() {
        statusEditorRequest &+= 1
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
        await notifications.refreshAuthorization()
        if notifications.authorization == .allowed { await notifications.sync(projects: projects) }
        monitor.start(url: vaultURL) { [weak self] in
            guard let self, Date() > self.selfWriteUntil else { return }
            Task { await self.reload(showSpinner: false) }
        }
    }

    func reload(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        do {
            projects = try await repository.loadProjects()
            if selectedProjectID == nil { selectedProjectID = projects.first?.id }
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
        var project = Project(id: UUID(), title: title, epic: epic, parentProject: parentProject,
                              summary: summary, tags: tags, state: state,
                              tasks: [], notes: "", createdAt: .now, updatedAt: .now,
                              isArchived: false, statuses: [], folderURL: nil)
        do {
            markSelfWrite()
            project = try await repository.saveProject(project)
            projects.insert(project, at: 0)
            selectedProjectID = project.id
            destination = .projects
            return project
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func saveProject(_ project: Project) async {
        var value = project
        value.updatedAt = .now
        do {
            markSelfWrite()
            let saved = try await repository.saveProject(value)
            replace(saved)
            if saved.tasks.contains(where: { $0.dueDate != nil }) {
                await notifications.ensureAccessAndSync(projects: projects)
            } else if notifications.authorization == .allowed {
                await notifications.sync(projects: projects)
            }
        } catch { errorMessage = "Не удалось сохранить проект: \(error.localizedDescription)" }
    }

    func saveStatus(_ value: DailyStatus, projectID: UUID) async {
        guard var project = projects.first(where: { $0.id == projectID }) else { return }
        var status = value
        status.projectTitle = project.pathLabel
        status.projectID = project.id
        status.updatedAt = .now
        do {
            markSelfWrite()
            let saved = try await repository.saveStatus(status, for: project)
            if let index = project.statuses.firstIndex(where: { $0.id == saved.id }) { project.statuses[index] = saved }
            else { project.statuses.append(saved) }
            project.statuses.sort { $0.date > $1.date }
            project.state = saved.state
            project.updatedAt = .now
            project = try await repository.saveProject(project)
            replace(project)
        } catch { errorMessage = "Не удалось сохранить статус: \(error.localizedDescription)" }
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
            if notifications.authorization == .allowed {
                await notifications.sync(projects: projects)
            }
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
            monitor.start(url: url) { [weak self] in Task { await self?.reload(showSpinner: false) } }
        } catch { errorMessage = "Не удалось сохранить доступ к папке: \(error.localizedDescription)" }
    }

    func searchHits(query: String) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var result: [SearchHit] = []
        for project in projects {
            if project.title.range(of: needle, options: options) != nil || project.summary.range(of: needle, options: options) != nil || project.tags.contains(where: { $0.range(of: needle, options: options) != nil }) {
                result.append(SearchHit(id: "project-\(project.id)", projectID: project.id, statusID: nil, kind: .project,
                                        title: project.title, excerpt: excerpt(from: project.summary, matching: needle), date: project.updatedAt))
            }
            if let task = project.tasks.first(where: { $0.title.range(of: needle, options: options) != nil }) {
                result.append(SearchHit(id: "task-\(project.id)-\(task.id)", projectID: project.id, statusID: nil, kind: .project,
                                        title: project.title, excerpt: task.title, date: project.updatedAt))
            }
            if project.notes.range(of: needle, options: options) != nil {
                result.append(SearchHit(id: "note-\(project.id)", projectID: project.id, statusID: nil, kind: .note,
                                        title: project.title, excerpt: excerpt(from: project.notes, matching: needle), date: project.updatedAt))
            }
            for status in project.statuses where status.searchableText.range(of: needle, options: options) != nil {
                result.append(SearchHit(id: "status-\(status.id)", projectID: project.id, statusID: status.id, kind: .status,
                                        title: project.title, excerpt: excerpt(from: status.searchableText, matching: needle), date: status.date))
            }
        }
        return result.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
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
        if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = project }
        else { projects.append(project) }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    private func markSelfWrite() { selfWriteUntil = Date().addingTimeInterval(1.2) }

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
        static let template = "statusTemplate"
    }
}
