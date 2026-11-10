import XCTest
@testable import PROJECT_Tracking

@MainActor
final class RepositoryPerformanceTests: XCTestCase {
    func testRepeatedLoadBenchmark() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TraceBenchmark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MarkdownRepository(rootURL: root)
        let day = Calendar.current.startOfDay(for: .now)
        for index in 0..<40 {
            let folder = root.appendingPathComponent("Projects/26Q4/project-\(index)")
            let statuses = folder.appendingPathComponent("Statuses")
            try FileManager.default.createDirectory(at: statuses, withIntermediateDirectories: true)
            let project = Project(id: UUID(), title: "Проект \(index)", summary: "Описание", tags: [], state: .active,
                                  tasks: (0..<20).map { ProjectTask(title: "Задача \($0)", isDone: false) },
                                  createdAt: day, updatedAt: day, isArchived: false, folderURL: folder)
            try MarkdownCodec.encode(project: project).write(to: folder.appendingPathComponent("Project.md"), atomically: true, encoding: .utf8)
            for offset in 0..<30 {
                let entry = DailyStatus(projectID: project.id, date: day.addingTimeInterval(-Double(offset) * 86400),
                                        status: "### Результат\nРабота по проекту \(index).\n- Пункт\n- [ ] Следующий шаг",
                                        blockers: offset % 3 == 0 ? "Жду ответ" : "")
                try MarkdownCodec.encode(status: entry).write(to: statuses.appendingPathComponent("day-\(offset).md"), atomically: true, encoding: .utf8)
            }
        }
        let coldStart = ContinuousClock.now
        let cold = try await repository.loadProjects()
        let coldTime = coldStart.duration(to: .now)
        var warmTimes: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            let warm = try await repository.loadProjects()
            warmTimes.append(milliseconds(start.duration(to: .now)))
            XCTAssertEqual(warm.sorted { $0.id.uuidString < $1.id.uuidString }, cold.sorted { $0.id.uuidString < $1.id.uuidString })
        }
        let metrics = await repository.lastLoadMetrics
        XCTAssertEqual(metrics.filesRead, 0)
        XCTAssertEqual(metrics.cacheHits, 1240)
        XCTAssertEqual(cold.count, 40)
        XCTAssertEqual(cold.reduce(0) { $0 + $1.statuses.count }, 1200)
        print("TRACE_BENCH files=1240 cold_ms=\(milliseconds(coldTime)) warm_median_ms=\(warmTimes.sorted()[1])")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
