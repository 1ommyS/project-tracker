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
            try "# Trace\n\nЛокальное хранилище проектов. Папку можно открыть как Obsidian Vault.\n"
                .write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    func loadProjects() throws -> [Project] {
        try prepare()
        // Структура: Projects/<YYQN>/<slug>, завершённые — Projects/<YYQN>/Completed Projects/<slug>.
        // Плюс поддержка плоской старой структуры Projects/<slug>.
        let scanned = try scanProjects(in: projectsURL, depth: 0)
        // Один и тот же id может оказаться в двух папках (ручные копии в
        // Finder/Obsidian) — оставляем самую свежую версию проекта.
        var newestByID: [UUID: Project] = [:]
        for project in scanned {
            if let existing = newestByID[project.id], existing.updatedAt >= project.updatedAt { continue }
            newestByID[project.id] = project
        }
        return newestByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func scanProjects(in directory: URL, depth: Int) throws -> [Project] {
        let folders = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var result: [Project] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let projectFile = folder.appendingPathComponent("Project.md")
            if fm.fileExists(atPath: projectFile.path),
               let text = try? String(contentsOf: projectFile, encoding: .utf8),
               let project = try? MarkdownCodec.decodeProject(text, folderURL: folder) {
                result.append(project)
            } else if depth < 2 {
                result.append(contentsOf: try scanProjects(in: folder, depth: depth + 1))
            }
        }
        return result
    }

    func saveProject(_ project: Project) throws -> Project {
        let parent = containerFolder(for: project)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        var folder: URL
        if let existing = project.folderURL {
            // Slug не меняем при переименовании — только переносим между папками,
            // когда проект сменил состояние или квартальную принадлежность.
            folder = parent.appendingPathComponent(existing.lastPathComponent, isDirectory: true)
            if existing != folder {
                let target = fm.fileExists(atPath: folder.path)
                    ? uniqueFolder(named: existing.lastPathComponent, in: parent)
                    : folder
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: existing, to: target)
                folder = target
            }
        } else {
            folder = uniqueFolder(named: project.title.fileSlug(fallback: project.id.uuidString.lowercased()), in: parent)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let file = folder.appendingPathComponent("Project.md")
        try Data(MarkdownCodec.encode(project: project).utf8).write(to: file, options: .atomic)
        var result = project
        result.folderURL = folder
        return result
    }

    private func containerFolder(for project: Project) -> URL {
        let quarterRoot = projectsURL.appendingPathComponent(project.quarter, isDirectory: true)
        return project.isCompleted
            ? quarterRoot.appendingPathComponent("Completed Projects", isDirectory: true)
            : quarterRoot
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

    private func uniqueFolder(named name: String, in parent: URL) -> URL {
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    enum RepositoryError: Error { case missingProjectFolder }
}

nonisolated final class VaultMonitor: NSObject, NSFilePresenter {
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
