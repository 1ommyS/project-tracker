import XCTest
import UserNotifications
@testable import PROJECT_Tracking

@MainActor
final class NotificationTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        return result
    }
    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 11, day: 10, hour: hour, minute: minute))!
    }
    private func project() -> Project {
        Project(id: UUID(), title: "Проект", summary: "", tags: [], state: .active,
                tasks: [ProjectTask(title: "Задача", isDone: false, dueDate: date(hour: 18))],
                createdAt: .now, updatedAt: .now, isArchived: false, folderURL: nil)
    }

    func testPlanExcludesCompletedArchivedDoneAndPastTasks() {
        let active = project()
        var done = project(); done.state = .done
        var archived = project(); archived.isArchived = true
        var taskDone = project(); taskDone.tasks[0].isDone = true
        var past = project(); past.tasks[0].dueDate = date(hour: 7)
        let requests = NotificationPlan.requests(projects: [active, done, archived, taskDone, past], now: date(hour: 8), calendar: calendar)
        XCTAssertEqual(requests.map(\.identifier), [active.tasks[0].notificationID])
        XCTAssertEqual(requests[0].content.userInfo["taskID"] as? String, active.tasks[0].id.uuidString)
    }

    func testAllDayReminderUsesMorningAndFallsBackToDeadlineAfterMorning() throws {
        var value = project(); value.tasks[0].dueDate = date(hour: 23, minute: 59)
        let early = NotificationPlan.requests(projects: [value], now: date(hour: 8), calendar: calendar)
        let morning = try XCTUnwrap(early.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(morning.dateComponents.hour, 9)
        XCTAssertEqual(morning.dateComponents.timeZone, calendar.timeZone)
        let late = NotificationPlan.requests(projects: [value], now: date(hour: 10), calendar: calendar)
        let deadline = try XCTUnwrap(late.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(deadline.dateComponents.hour, 23)
        XCTAssertEqual(deadline.dateComponents.minute, 59)
    }

    func testOnlyKnownActionsAreHandledAndDismissDoesNotOpenProject() {
        let project = UUID(), task = UUID()
        let info = ["projectID": project.uuidString, "taskID": task.uuidString]
        XCTAssertEqual(NotificationPlan.action(identifier: UNNotificationDefaultActionIdentifier, userInfo: info), .openProject(project))
        XCTAssertEqual(NotificationPlan.action(identifier: NotificationPlan.completeAction, userInfo: info), .completeTask(projectID: project, taskID: task))
        XCTAssertNil(NotificationPlan.action(identifier: UNNotificationDismissActionIdentifier, userInfo: info))
        XCTAssertNil(NotificationPlan.action(identifier: NotificationPlan.completeAction, userInfo: ["projectID": project.uuidString]))
    }

    func testSyncRemovesCancelledRemindersAndKeepsTestNotification() async throws {
        let client = FakeNotificationClient()
        let service = NotificationService(client: client, now: { self.date(hour: 8) }, calendar: calendar)
        var value = project()
        await service.sync(projects: [value])
        XCTAssertNotNil(client.requests[value.tasks[0].notificationID])
        await service.sendTestNotification()
        client.delivered = [value.tasks[0].notificationID]
        value.tasks[0].isDone = true
        await service.sync(projects: [value])
        XCTAssertNil(client.requests[value.tasks[0].notificationID])
        XCTAssertNotNil(client.requests["pulseboard.test"])
        XCTAssertTrue(client.delivered.isEmpty)
        XCTAssertEqual(service.pendingCount, 0)
    }

    func testDeniedAuthorizationNeverPromptsDuringSync() async {
        let client = FakeNotificationClient(); client.allowed = false
        let service = NotificationService(client: client)
        await service.syncIfAllowed(projects: [project()])
        XCTAssertEqual(service.authorization, .denied)
        XCTAssertEqual(client.permissionRequests, 0)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testSchedulingFailureIsVisibleAndTestDeliveryIsActuallyChecked() async {
        let client = FakeNotificationClient(); client.failAdd = true
        let service = NotificationService(client: client, now: { self.date(hour: 8) }, calendar: calendar)
        await service.sync(projects: [project()])
        XCTAssertNotNil(service.scheduleError)
        XCTAssertEqual(service.pendingCount, 0)
        client.failAdd = false
        await service.sendTestNotification()
        client.delivered = ["pulseboard.test"]
        await service.checkTestDelivery()
        XCTAssertTrue(service.statusMessage?.contains("macOS доставила") == true)
    }

    func testConcurrentSyncEndsWithLatestSnapshot() async {
        let client = FakeNotificationClient()
        let service = NotificationService(client: client, now: { self.date(hour: 8) }, calendar: calendar)
        let before = project()
        var after = before; after.tasks[0].isDone = true
        let first = Task { await service.sync(projects: [before]) }
        await Task.yield()
        await service.sync(projects: [after])
        await first.value
        XCTAssertNil(client.requests[before.tasks[0].notificationID])
    }
    func testStatusOnlyChangesSkipRedundantOSRequests() async {
        let client = FakeNotificationClient()
        let service = NotificationService(client: client, now: { self.date(hour: 8) }, calendar: calendar)
        var value = project()
        await service.syncIfAllowed(projects: [value])
        let before = client.pendingReads
        value.statuses = [DailyStatus(projectID: value.id, date: .now, status: "Изменение только текста")]
        await service.syncIfAllowed(projects: [value])
        XCTAssertEqual(client.pendingReads, before)
        await service.sync(projects: [value])
        XCTAssertGreaterThan(client.pendingReads, before, "явное перепланирование всегда проверяет OS")
    }

}

@MainActor
final class FakeNotificationClient: NotificationClient {
    var allowed = true
    var failAdd = false
    var permissionRequests = 0
    var pendingReads = 0
    var requests: [String: UNNotificationRequest] = [:]
    var delivered: [String] = []
    func activate(delegate: UNUserNotificationCenterDelegate) {}
    func permission() async -> NotificationPermission {
        NotificationPermission(authorization: allowed ? .authorized : .denied, alerts: .enabled, sounds: .enabled)
    }
    func requestAccess() async throws -> Bool { permissionRequests += 1; return allowed }
    func pending() async -> [UNNotificationRequest] { pendingReads += 1; await Task.yield(); return Array(requests.values) }
    func deliveredIDs() async -> [String] { delivered }
    func add(_ request: UNNotificationRequest) async throws {
        await Task.yield()
        if failAdd { throw NSError(domain: "test", code: 1) }
        requests[request.identifier] = request
    }
    func removePending(_ ids: [String]) { for id in ids { requests.removeValue(forKey: id) } }
    func removeDelivered(_ ids: [String]) { delivered.removeAll { ids.contains($0) } }
}
