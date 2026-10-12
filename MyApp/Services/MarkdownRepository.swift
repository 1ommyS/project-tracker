import Foundation

actor MarkdownRepository {
    private(set) var rootURL: URL
    private let fm = FileManager.default

    init(rootURL: URL) { self.rootURL = rootURL }

    func setRootURL(_ url: URL) { rootURL = url }

    func prepare() throws {
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        let readme = rootURL.appendingPathComponent("README.md")
        if !fm.fileExists(atPath: readme.path) {
            try "# Pulseboard\n\nЛокальное хранилище проектов. Папку можно открыть как Obsidian Vault.\n"
                .write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    func loadProjects() throws -> [Project] {
        try prepare()
        let folders = try fm.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return folders.compactMap { folder in
            let projectFile = folder.appendingPathComponent("Project.md")
            guard let text = try? String(contentsOf: projectFile, encoding: .utf8),
                  var project = try? MarkdownCodec.decodeProject(text, folderURL: folder) else { return nil }
            let statusFolder = folder.appendingPathComponent("Statuses", isDirectory: true)
            let statusFiles = (try? fm.contentsOfDirectory(at: statusFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            project.statuses = statusFiles.filter { $0.pathExtension.lowercased() == "md" }.compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return try? MarkdownCodec.decodeStatus(source, fileURL: url)
            }.sorted { $0.date > $1.date }
            return project
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveProject(_ project: Project) throws -> Project {
        let folder: URL
        if let existing = project.folderURL {
            folder = existing
        } else {
            let base = project.title.fileSlug(fallback: project.id.uuidString.lowercased())
            folder = uniqueFolder(named: base)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("Statuses"), withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Project.md")
        try Data(MarkdownCodec.encode(project: project).utf8).write(to: file, options: .atomic)
        var result = project
        result.folderURL = folder
        return result
    }

    func saveStatus(_ status: DailyStatus, for project: Project) throws -> DailyStatus {
        guard let folder = project.folderURL else { throw RepositoryError.missingProjectFolder }
        let statuses = folder.appendingPathComponent("Statuses", isDirectory: true)
        try fm.createDirectory(at: statuses, withIntermediateDirectories: true)
        let date = Self.dayFormatter.string(from: status.date)
        let url = status.fileURL ?? statuses.appendingPathComponent("\(date)-\(status.id.uuidString.prefix(8)).md")
        try Data(MarkdownCodec.encode(status: status).utf8).write(to: url, options: .atomic)
        var result = status
        result.fileURL = url
        return result
    }

    func deleteProject(_ project: Project) throws {
        guard let url = project.folderURL, fm.fileExists(atPath: url.path) else { return }
        var trashed: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &trashed)
    }

    func rawProjectMarkdown(_ project: Project) throws -> String {
        guard let folder = project.folderURL else { return MarkdownCodec.encode(project: project) }
        return try String(contentsOf: folder.appendingPathComponent("Project.md"), encoding: .utf8)
    }

    private var projectsURL: URL { rootURL.appendingPathComponent("Projects", isDirectory: true) }

    private func uniqueFolder(named name: String) -> URL {
        var candidate = projectsURL.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = projectsURL.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    enum RepositoryError: Error { case missingProjectFolder }
}

final class VaultMonitor: NSObject, NSFilePresenter {
    private(set) var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private var pendingReload: DispatchWorkItem?
    private var onChange: (@MainActor () -> Void)?

    func start(url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()
        presentedItemURL = url
        self.onChange = onChange
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() {
        pendingReload?.cancel()
        if presentedItemURL != nil { NSFileCoordinator.removeFilePresenter(self) }
        presentedItemURL = nil
        onChange = nil
    }

    func presentedItemDidChange() { scheduleReload() }
    func presentedSubitemDidChange(at url: URL) { scheduleReload() }
    func presentedSubitemDidAppear(at url: URL) { scheduleReload() }
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        scheduleReload()
        completionHandler(nil)
    }

    private func scheduleReload() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            pendingReload?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange?() }
            pendingReload = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    deinit { NSFileCoordinator.removeFilePresenter(self) }
}
