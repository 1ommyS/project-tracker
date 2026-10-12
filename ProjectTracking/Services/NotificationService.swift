import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum Authorization: String {
        case unknown, allowed, denied
        var title: String {
            switch self { case .unknown: "Не настроены"; case .allowed: "Включены"; case .denied: "Выключены в системе" }
        }
    }

    private(set) var authorization: Authorization = .unknown
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: authorization = .allowed
        case .denied: authorization = .denied
        default: authorization = .unknown
        }
    }

    func requestAccess() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch { }
        await refreshAuthorization()
    }

    func ensureAccessAndSync(projects: [Project]) async {
        await refreshAuthorization()
        if authorization == .unknown { await requestAccess() }
        guard authorization == .allowed else { return }
        await sync(projects: projects)
    }

    func sync(projects: [Project]) async {
        let pending = await center.pendingNotificationRequests()
        let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix("pulseboard.task.") }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)

        for project in projects where !project.isArchived {
            for task in project.tasks where !task.isDone {
                guard let dueDate = task.dueDate, dueDate > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Пора выполнить задачу"
                content.subtitle = project.pathLabel
                content.body = task.title
                content.sound = .default
                content.userInfo = ["projectID": project.id.uuidString]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: task.notificationID, content: content, trigger: trigger))
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
