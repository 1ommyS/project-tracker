import UserNotifications

nonisolated struct NotificationPermission {
    let authorization: UNAuthorizationStatus
    let alerts: UNNotificationSetting
    let sounds: UNNotificationSetting
}

@MainActor
protocol NotificationClient {
    func activate(delegate: UNUserNotificationCenterDelegate)
    func permission() async -> NotificationPermission
    func requestAccess() async throws -> Bool
    func pending() async -> [UNNotificationRequest]
    func deliveredIDs() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
}

@MainActor
final class SystemNotificationClient: NotificationClient {
    private var center: UNUserNotificationCenter { .current() }

    func activate(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
        let complete = UNNotificationAction(identifier: NotificationPlan.completeAction, title: "Выполнено")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: NotificationPlan.categoryID, actions: [complete], intentIdentifiers: [])
        ])
    }

    func permission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        return NotificationPermission(authorization: settings.authorizationStatus, alerts: settings.alertSetting, sounds: settings.soundSetting)
    }

    func requestAccess() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .badge, .sound]) }
    func pending() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func deliveredIDs() async -> [String] { await center.deliveredNotifications().map { $0.request.identifier } }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}
