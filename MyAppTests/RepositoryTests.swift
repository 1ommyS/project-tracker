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
}
