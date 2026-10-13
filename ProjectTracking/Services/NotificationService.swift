import AppKit
import Foundation
import Observation
import OSLog
import UserNotifications

private let notificationLogger = Logger(subsystem: "app.pulseboard.local", category: "notifications")

@MainActor @Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum Authorization: String {
        case unknown, allowed, denied
        var title: String {
            switch self { case .unknown: "Не настроены"; case .allowed: "Включены"; case .denied: "Выключены в системе" }
        }
    }

    enum Event: Sendable {
        case openProject(UUID)
        case completeTask(projectID: UUID, taskID: UUID)
    }

    private enum Constants {
        static let categoryID = "pulseboard.task"
        static let completeAction = "pulseboard.task.complete"
        static let idPrefix = "pulseboard.task."
    }

    private(set) var authorization: Authorization = .unknown
    /// Диагностическое сообщение для настроек: что пошло не так или когда придёт тестовый баннер.
    private(set) var statusMessage: String?
    private var isActivated = false
    private var lastProjects: [Project] = []
    var onEvent: (@MainActor (Event) -> Void)?

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    // MARK: - Активация

    /// Делегат подключаем лениво: обращение к центру из init приложения
    /// на части сборок macOS приводит к пропаданию уведомлений.
    func activate() {
        guard !isActivated else { return }
        isActivated = true
        center.delegate = self
        let complete = UNNotificationAction(identifier: Constants.completeAction, title: "Выполнено")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Constants.categoryID, actions: [complete], intentIdentifiers: [])
        ])
        // Разрешение могли выдать в Системных настройках, пока приложение
        // было свёрнуто, — при активации окна тихо пересобираем расписание.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.lastProjects.isEmpty else { return }
                await self.syncIfAllowed(projects: self.lastProjects)
            }
        }
        notificationLogger.info("Notification center activated")
    }

    // MARK: - Разрешение

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
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            notificationLogger.info("Authorization finished, granted=\(granted, privacy: .public)")
        } catch {
            notificationLogger.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshAuthorization()
    }

    /// Спрашивает разрешение, если система ещё не спрашивала, и перестраивает напоминания.
    func authorizeAndSync(projects: [Project]) async {
        activate()
        await refreshAuthorization()
        if authorization == .unknown { await requestAccess() }
        guard authorization == .allowed else {
            statusMessage = authorization == .denied
                ? "Уведомления выключены в Системных настройках → Уведомления → Trace."
                : nil
            return
        }
        await sync(projects: projects)
    }

    /// Тихая пересинхронизация без запроса разрешения.
    func syncIfAllowed(projects: [Project]) async {
        activate()
        await refreshAuthorization()
        guard authorization == .allowed else { return }
        await sync(projects: projects)
    }

    // MARK: - Расписание

    func sync(projects: [Project]) async {
        lastProjects = projects
        var requests: [String: UNNotificationRequest] = [:]
        for project in projects where !project.isArchived {
            for task in project.tasks where !task.isDone {
                guard let dueDate = task.dueDate, dueDate > .now else { continue }
                let fireDate = reminderDate(for: dueDate)
                let content = UNMutableNotificationContent()
                content.title = "Пора выполнить задачу"
                content.subtitle = project.pathLabel.isEmpty ? project.title : project.pathLabel
                content.body = task.title
                content.sound = .default
                content.threadIdentifier = project.id.uuidString
                content.categoryIdentifier = Constants.categoryID
                content.userInfo = ["projectID": project.id.uuidString, "taskID": task.id.uuidString]
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
                requests[task.notificationID] = UNNotificationRequest(identifier: task.notificationID, content: content, trigger: trigger)
            }
        }

        // Добавление запроса с существующим идентификатором заменяет его,
        // поэтому сносим только устаревшие — без сброса всего расписания.
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Constants.idPrefix) && requests[$0] == nil }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        var failures = 0
        for request in requests.values.sorted(by: { $0.identifier < $1.identifier }) {
            do {
                try await center.add(request)
            } catch {
                failures += 1
                notificationLogger.error("Schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        statusMessage = failures == 0 ? nil : "Не удалось запланировать \(failures) из \(requests.count) напоминаний."
        notificationLogger.info("Sync done: scheduled=\(requests.count, privacy: .public), removed=\(stale.count, privacy: .public), failed=\(failures, privacy: .public)")
    }

    /// «Весь день» (23:59) напоминаем утром в 9:00, если утро ещё впереди.
    private func reminderDate(for dueDate: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: dueDate)
        guard components.hour == 23, components.minute == 59,
              let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate),
              morning > .now else { return dueDate }
        return morning
    }

    // MARK: - Диагностика

    /// Тестовый баннер через 5 секунд — мгновенная проверка доставки.
    func sendTestNotification() async {
        activate()
        await refreshAuthorization()
        guard authorization == .allowed else {
            statusMessage = "Сначала разрешите уведомления — кнопка выше или Системные настройки."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Проверка напоминаний"
        content.body = "Если вы видите этот баннер — напоминания о задачах работают."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pulseboard.test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        do {
            try await center.add(request)
            statusMessage = "Тестовое напоминание придёт через 5 секунд."
        } catch {
            statusMessage = "Тест не удалось запланировать: \(error.localizedDescription)"
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let projectID = (info["projectID"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        let taskID = (info["taskID"] as? String).flatMap(UUID.init(uuidString:))
        let event: Event
        if response.actionIdentifier == Constants.completeAction, let taskID {
            event = .completeTask(projectID: projectID, taskID: taskID)
        } else {
            event = .openProject(projectID)
        }
        Task { @MainActor [weak self] in self?.onEvent?(event) }
    }
}
