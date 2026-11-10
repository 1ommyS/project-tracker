import Foundation

actor MarkdownRepository {
    private(set) var rootURL: URL
    private let fm = FileManager.default

    init(rootURL: URL) { self.rootURL = rootURL }

    func setRootURL(_ url: URL) {
        rootURL = url
        projectCache.removeAll()
        statusCache.removeAll()
    }

    private struct Fingerprint: Equatable {
        let modified: Date?
        let size: Int?
        init(_ url: URL) throws {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            modified = values.contentModificationDate
            size = values.fileSize
        }
    }
    private struct Cached<Value> { let fingerprint: Fingerprint; let value: Value }
    private var projectCache: [URL: Cached<Project>] = [:]
    private var statusCache: [URL: Cached<DailyStatus>] = [:]
    private var visitedFiles: Set<URL> = []
    private(set) var lastLoadMetrics = RepositoryLoadMetrics()

    private func invalidate(_ changed: Set<URL>) {
        for url in changed {
            if url.standardizedFileURL == rootURL.standardizedFileURL { continue }
            let path = url.standardizedFileURL.path
            projectCache = projectCache.filter { $0.key.path != path && !$0.key.path.hasPrefix(path + "/") }
            statusCache = statusCache.filter { $0.key.path != path && !$0.key.path.hasPrefix(path + "/") }
        }
    }

    private func readProject(at url: URL, folder: URL) throws -> Project {
        let key = url.standardizedFileURL
        visitedFiles.insert(key)
        let fingerprint = try Fingerprint(key)
        if let cached = projectCache[key], cached.fingerprint == fingerprint {
            lastLoadMetrics.cacheHits += 1
            return cached.value
        }
        let source = try String(contentsOf: key, encoding: .utf8)
        lastLoadMetrics.filesRead += 1
        let value = try MarkdownCodec.decodeProject(source, folderURL: folder)
        projectCache[key] = Cached(fingerprint: fingerprint, value: value)
        return value
    }

    private func readStatus(at url: URL) throws -> DailyStatus {
        let key = url.standardizedFileURL
        visitedFiles.insert(key)
        let fingerprint = try Fingerprint(key)
        if let cached = statusCache[key], cached.fingerprint == fingerprint {
            lastLoadMetrics.cacheHits += 1
            return cached.value
        }
        let source = try String(contentsOf: key, encoding: .utf8)
        lastLoadMetrics.filesRead += 1
        let value = try MarkdownCodec.decodeStatus(source, fileURL: url)
        statusCache[key] = Cached(fingerprint: fingerprint, value: value)
        return value
    }

    func prepare() throws {
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        let readme = rootURL.appendingPathComponent("README.md")
        if !fm.fileExists(atPath: readme.path) {
            try "# Trace Desktop\n\nЛокальное хранилище проектов. Папку можно открыть как Obsidian Vault.\n"
                .write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    func loadProjects(changedURLs: Set<URL> = []) throws -> [Project] {
        try prepare()
        invalidate(changedURLs)
        lastLoadMetrics = RepositoryLoadMetrics()
        visitedFiles.removeAll(keepingCapacity: true)
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
        projectCache = projectCache.filter { visitedFiles.contains($0.key) }
        statusCache = statusCache.filter { visitedFiles.contains($0.key) }
        return newestByID.values.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
    }

    private func scanProjects(in directory: URL, depth: Int) throws -> [Project] {
        let folders = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var result: [Project] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let projectFile = folder.appendingPathComponent("Project.md")
            if fm.fileExists(atPath: projectFile.path),
               var project = try? readProject(at: projectFile, folder: folder) {
                project.statuses = loadStatuses(in: folder).sorted { $0.date > $1.date }
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
                invalidate([existing])
                folder = target
            }
        } else {
            folder = uniqueFolder(named: project.title.fileSlug(fallback: project.id.uuidString.lowercased()), in: parent)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let file = folder.appendingPathComponent("Project.md")
        try Data(MarkdownCodec.encode(project: project).utf8).write(to: file, options: .atomic)
        projectCache.removeValue(forKey: file.standardizedFileURL)
        var result = project
        result.folderURL = folder
        // Статусы переехали вместе с папкой, их прежние абсолютные URL устарели.
        for index in result.statuses.indices {
            if let file = result.statuses[index].fileURL {
                result.statuses[index].fileURL = folder.appendingPathComponent("Statuses")
                    .appendingPathComponent(file.lastPathComponent)
            }
        }
        return result
    }

    private func containerFolder(for project: Project) -> URL {
        let quarterRoot = projectsURL.appendingPathComponent(project.quarter, isDirectory: true)
        return project.isCompleted
            ? quarterRoot.appendingPathComponent("Completed Projects", isDirectory: true)
            : quarterRoot
    }

    private func loadStatuses(in folder: URL) -> [DailyStatus] {
        let statusFolder = folder.appendingPathComponent("Statuses", isDirectory: true)
        let files = (try? fm.contentsOfDirectory(at: statusFolder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension.lowercased() == "md" }.compactMap { url in
            try? readStatus(at: url)
        }
    }

    func saveStatus(_ status: DailyStatus, for project: Project) throws -> DailyStatus {
        try MarkdownCodec.validate(status: status)
        guard let folder = project.folderURL else { throw RepositoryError.missingProjectFolder }
        let statusesFolder = folder.appendingPathComponent("Statuses", isDirectory: true)
        try fm.createDirectory(at: statusesFolder, withIntermediateDirectories: true)
        let day = Self.dayFormatter.string(from: status.date)
        let filename = status.fileURL?.lastPathComponent ?? "\(day)-\(status.id.uuidString.prefix(8)).md"
        let url = statusesFolder.appendingPathComponent(filename)
        let source = MarkdownCodec.encode(status: status)
        let result = try MarkdownCodec.decodeStatus(source, fileURL: url)
        try Data(source.utf8).write(to: url, options: .atomic)
        statusCache.removeValue(forKey: url.standardizedFileURL)
        return result
    }

    func deleteProject(_ project: Project) throws {
        guard let url = project.folderURL, fm.fileExists(atPath: url.path) else { return }
        var trashed: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &trashed)
        invalidate([url])
    }

    func rawProjectMarkdown(_ project: Project) throws -> String {
        guard let folder = project.folderURL else { return MarkdownCodec.encode(project: project) }
        return try String(contentsOf: folder.appendingPathComponent("Project.md"), encoding: .utf8)
    }

    /// Runs on the repository executor, keeping AppKit's main thread responsive.
    func archiveVault(using script: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, rootURL.path, output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RepositoryError.archiveFailed(process.terminationStatus) }
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    enum RepositoryError: LocalizedError {
        case missingProjectFolder, archiveFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .missingProjectFolder: "Папка проекта недоступна."
            case .archiveFailed(let code): "Не удалось создать архив (код \(code))."
            }
        }
    }
}

nonisolated struct RepositoryLoadMetrics: Sendable {
    var filesRead = 0
    var cacheHits = 0
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
    private var onChange: (@MainActor (Set<URL>) -> Void)?
    private var changedURLs: Set<URL> = []

    func start(url: URL, onChange: @escaping @MainActor (Set<URL>) -> Void) {
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
        changedURLs.removeAll()
    }

    func presentedItemDidChange() { scheduleReload(url: presentedItemURL) }
    func presentedSubitemDidChange(at url: URL) { scheduleReload(url: url) }
    func presentedSubitemDidAppear(at url: URL) { scheduleReload(url: url) }
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        scheduleReload(url: presentedItemURL)
        completionHandler(nil)
    }

    private func scheduleReload(url: URL?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let url { changedURLs.insert(url) }
            pendingReload?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let urls = self.changedURLs
                self.changedURLs.removeAll()
                self.onChange?(urls)
            }
            pendingReload = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    deinit { NSFileCoordinator.removeFilePresenter(self) }
}
