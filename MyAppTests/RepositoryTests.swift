import XCTest
@testable import PROJECT_Tracking

final class RepositoryTests: XCTestCase {
    private var root: URL!
    private var repository: MarkdownRepository!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RepositoryTests-\(UUID().uuidString)")
        repository = MarkdownRepository(rootURL: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeProject(createdAt: Date, state: ProjectState = .active) -> Project {
        Project(id: UUID(), title: "Квартальный проект", epic: "Учёба", parentProject: "", summary: "",
                tags: [], state: state, tasks: [], createdAt: createdAt, updatedAt: createdAt,
                isArchived: false, folderURL: nil)
    }

    func testDuplicateProjectIDsDeduplicateToNewest() async throws {
        let id = UUID()
        var older = makeProject(createdAt: .now)
        older.id = id
        older.title = "Старая копия"
        older.updatedAt = .now.addingTimeInterval(-3600)

        var newer = older
        newer.title = "Свежая копия"
        newer.updatedAt = .now

        let quarterFolder = root.appendingPathComponent("Projects/26Q4/duplicate-slug", isDirectory: true)
        let flatFolder = root.appendingPathComponent("Projects/duplicate-flat", isDirectory: true)
        for (folder, project) in [(quarterFolder, older), (flatFolder, newer)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try MarkdownCodec.encode(project: project)
                .write(to: folder.appendingPathComponent("Project.md"), atomically: true, encoding: .utf8)
        }

        let loaded = try await repository.loadProjects()
        XCTAssertEqual(loaded.count, 1, "дубль по id не должен удваивать проект")
        XCTAssertEqual(loaded.first?.title, "Свежая копия", "побеждает версия с более свежим updated")
    }

    func testQuarterLabelFormat() {
        let calendar = Calendar.current
        var date = try! XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        XCTAssertEqual(date.quarterLabel, "26Q4")
        date = try! XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        XCTAssertEqual(date.quarterLabel, "26Q1")
        date = try! XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 9, day: 30)))
        XCTAssertEqual(date.quarterLabel, "27Q3")
    }

    func testProjectLivesInQuarterFolder() async throws {
        let createdAt = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let saved = try await repository.saveProject(makeProject(createdAt: createdAt))

        let path = try XCTUnwrap(saved.folderURL).path
        XCTAssertTrue(path.contains("/Projects/26Q4/"), "проект должен лежать в квартальной папке: \(path)")
        XCTAssertFalse(path.contains("Completed"))
    }

    func testCompletionMovesFolderToCompletedProjects() async throws {
        let createdAt = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        var project = try await repository.saveProject(makeProject(createdAt: createdAt))
        let originalSlug = try XCTUnwrap(project.folderURL).lastPathComponent
        XCTAssertTrue(try XCTUnwrap(project.folderURL).path.contains("/Projects/26Q3/"))

        // Перевод в done переносит папку в Completed Projects того же квартала.
        project.state = .done
        project = try await repository.saveProject(project)
        let donePath = try XCTUnwrap(project.folderURL).path
        XCTAssertTrue(donePath.contains("/Projects/26Q3/Completed Projects/"), donePath)

        // Архивное состояние тоже считается завершённым.
        project.state = .archived
        project.isArchived = true
        project = try await repository.saveProject(project)
        XCTAssertTrue(try XCTUnwrap(project.folderURL).path.contains("Completed Projects"))

        // Возврат в активные выносит папку из Completed Projects.
        project.state = .active
        project.isArchived = false
        project = try await repository.saveProject(project)
        let restoredPath = try XCTUnwrap(project.folderURL).path
        XCTAssertTrue(restoredPath.contains("/Projects/26Q3/"))
        XCTAssertFalse(restoredPath.contains("Completed"))

        // Slug сохраняется при переносах.
        XCTAssertEqual(try XCTUnwrap(project.folderURL).lastPathComponent, originalSlug)

        let loaded = try await repository.loadProjects()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, project.id)
    }

    func testLegacyFlatStructureStillLoads() async throws {
        let legacyFolder = root.appendingPathComponent("Projects/legacy-slug", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        let project = makeProject(createdAt: .now)
        try MarkdownCodec.encode(project: project)
            .write(to: legacyFolder.appendingPathComponent("Project.md"), atomically: true, encoding: .utf8)

        let loaded = try await repository.loadProjects()
        XCTAssertEqual(loaded.first?.title, "Квартальный проект")
        XCTAssertEqual(loaded.first?.folderURL?.lastPathComponent, "legacy-slug")

        // Следующее сохранение мягко мигрирует плоский проект в квартальную структуру.
        var updated = try XCTUnwrap(loaded.first)
        updated = try await repository.saveProject(updated)
        XCTAssertTrue(try XCTUnwrap(updated.folderURL).path.contains("/Projects/\(project.quarter)/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFolder.path))
    }
    func testUnchangedLoadsUseCacheAndSingleStatusEditReadsOneFile() async throws {
        let project = try await repository.saveProject(makeProject(createdAt: .now))
        let first = try await repository.saveStatus(DailyStatus(projectID: project.id, date: .now, status: "Первый"), for: project)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        _ = try await repository.saveStatus(DailyStatus(projectID: project.id, date: yesterday, status: "Второй"), for: project)
        _ = try await repository.loadProjects()
        let cold = await repository.lastLoadMetrics
        XCTAssertEqual(cold.filesRead, 3)
        _ = try await repository.loadProjects()
        let warm = await repository.lastLoadMetrics
        XCTAssertEqual(warm.filesRead, 0)
        XCTAssertEqual(warm.cacheHits, 3)
        var edited = first
        edited.status = "Обновлено"
        _ = try await repository.saveStatus(edited, for: project)
        let loaded = try await repository.loadProjects()
        let changed = await repository.lastLoadMetrics
        XCTAssertEqual(changed.filesRead, 1)
        XCTAssertEqual(changed.cacheHits, 2)
        XCTAssertEqual(loaded.first?.dailyStatus(on: .now)?.status, "Обновлено")
    }

    func testExplicitFileEventInvalidatesSameSizeAndTimestampChange() async throws {
        let project = try await repository.saveProject(makeProject(createdAt: .now))
        _ = try await repository.loadProjects()
        let file = try XCTUnwrap(project.folderURL).appendingPathComponent("Project.md")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let source = try String(contentsOf: file, encoding: .utf8)
        try source.replacingOccurrences(of: "Квартальный проект", with: "Квартальный объект").write(to: file, atomically: true, encoding: .utf8)
        if let date = attributes[.modificationDate] { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path) }
        let loaded = try await repository.loadProjects(changedURLs: [file])
        XCTAssertEqual(loaded.first?.title, "Квартальный объект")
    }

    func testCacheDropsDeletedStatusAndDoesNotLeakBetweenVaults() async throws {
        let project = try await repository.saveProject(makeProject(createdAt: .now))
        let entry = try await repository.saveStatus(DailyStatus(projectID: project.id, date: .now, status: "Запись"), for: project)
        _ = try await repository.loadProjects()
        try FileManager.default.removeItem(at: XCTUnwrap(entry.fileURL))
        let loaded = try await repository.loadProjects()
        XCTAssertTrue(loaded[0].statuses.isEmpty)
        let anotherRoot = root.appendingPathComponent("another-vault")
        await repository.setRootURL(anotherRoot)
        let other = try await repository.loadProjects()
        XCTAssertTrue(other.isEmpty)
    }

}
