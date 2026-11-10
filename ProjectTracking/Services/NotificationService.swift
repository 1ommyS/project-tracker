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

    typealias Event = NotificationPlan.Action
    private(set) var authorization: Authorization = .unknown
    private(set) var statusMessage: String?
    private(set) var scheduleError: String?
    private(set) var pendingCount = 0
    private(set) var nextReminder: Date?
    private(set) var alertsEnabled = false
    private(set) var soundsEnabled = false
    private var isActivated = false
    private var lastProjects: [Project] = []
    private let client: NotificationClient
    private let now: () -> Date
    private let calendar: Calendar
    private var syncTask: Task<Void, Never>?
    private var syncRevision = 0
    private var lastAppliedInput: [UUID: NotificationPlan.Input]?
    private var lastSyncDate = Date.distantPast
    private var lastSyncTimeZone = ""
    private var testTask: Task<Void, Never>?
    var onEvent: (@MainActor (Event) -> Void)?

    override convenience init() { self.init(client: SystemNotificationClient()) }

    init(client: NotificationClient, now: @escaping () -> Date = { .now }, calendar: Calendar = .current) {
        self.client = client
        self.now = now
        self.calendar = calendar
        super.init()
    }

    func activate() {
        guard !isActivated else { return }
        isActivated = true
        client.activate(delegate: self)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncIfAllowed(projects: self.lastProjects)
            }
        }
        notificationLogger.info("Notification center activated")
    }

    func refreshAuthorization() async {
        let permission = await client.permission()
        switch permission.authorization {
        case .authorized, .provisional, .ephemeral: authorization = .allowed
        case .denied: authorization = .denied
        default: authorization = .unknown
        }
        alertsEnabled = permission.alerts == .enabled
        soundsEnabled = permission.sounds == .enabled
    }

    func requestAccess() async {
        activate()
        do { _ = try await client.requestAccess() }
        catch { statusMessage = "Не удалось запросить разрешение: \(error.localizedDescription)" }
        await refreshAuthorization()
    }

    func authorizeAndSync(projects: [Project]) async {
        activate()
        lastProjects = projects
        await refreshAuthorization()
        if authorization == .unknown { await requestAccess() }
        if authorization == .denied { statusMessage = "Уведомления выключены в Системных настройках → Уведомления → Trace Desktop." }
        await sync(projects: projects)
    }

    func syncIfAllowed(projects: [Project]) async { await sync(projects: projects, force: false) }

    /// Superseded queued work is skipped; explicit diagnostics can force a refresh.
    func sync(projects: [Project], force: Bool = true) async {
        activate()
        lastProjects = projects
        syncRevision &+= 1
        let revision = syncRevision
        let previous = syncTask
        let input = NotificationPlan.inputSignature(projects: projects)
        let task = Task { @MainActor in
            if let previous { await previous.value }
            guard revision == syncRevision else { return }
            await refreshAuthorization()
            guard revision == syncRevision else { return }
            guard authorization == .allowed else {
                pendingCount = 0; nextReminder = nil; lastAppliedInput = nil
                return
            }
            if !force, input == lastAppliedInput, now().timeIntervalSince(lastSyncDate) < 30,
               calendar.timeZone.identifier == lastSyncTimeZone { return }
            await performSync(projects: projects, revision: revision)
            if revision == syncRevision, scheduleError == nil {
                lastAppliedInput = input
                lastSyncDate = now()
                lastSyncTimeZone = calendar.timeZone.identifier
            }
        }
        syncTask = task
        await task.value
    }

    private func performSync(projects: [Project], revision: Int) async {
        let requests = NotificationPlan.requests(projects: projects, now: now(), calendar: calendar)
        let ids = Set(requests.map(\.identifier))
        let pending = await client.pending()
        guard revision == syncRevision else { return }
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlan.idPrefix) && !ids.contains($0) }
        client.removePending(stale)
        // Keep delivered overdue reminders actionable; remove completed/deleted ones.
        let openIDs = Set(projects.filter { !$0.isCompleted }.flatMap { $0.openTasks.map(\.notificationID) })
        let delivered = await client.deliveredIDs()
        guard revision == syncRevision else { return }
        client.removeDelivered(delivered.filter { $0.hasPrefix(NotificationPlan.idPrefix) && !openIDs.contains($0) })
        let existing = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        var failures = 0
        for request in requests {
            guard revision == syncRevision else { return }
            if let old = existing[request.identifier], old.content.isEqual(request.content),
               let oldTrigger = old.trigger, let newTrigger = request.trigger, oldTrigger.isEqual(newTrigger) { continue }
            do { try await client.add(request) }
            catch {
                failures += 1
                notificationLogger.error("Schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        scheduleError = failures == 0 ? nil : "Не удалось запланировать \(failures) из \(requests.count) напоминаний."
        await refreshDiagnostics()
        notificationLogger.info("Sync done: scheduled=\(self.pendingCount, privacy: .public), failed=\(failures, privacy: .public)")
    }

    func refreshDiagnostics() async {
        await refreshAuthorization()
        let requests = await client.pending().filter { $0.identifier.hasPrefix(NotificationPlan.idPrefix) }
        pendingCount = requests.count
        nextReminder = requests.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }.min()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func sendTestNotification() async {
        activate()
        await refreshAuthorization()
        guard authorization == .allowed else {
            statusMessage = "Сначала разрешите уведомления в Системных настройках."
            return
        }
        testTask?.cancel()
        client.removeDelivered(["pulseboard.test"])
        let content = UNMutableNotificationContent()
        content.title = "Проверка напоминаний Trace Desktop"
        content.body = "Тест локального уведомления. Напоминания о задачах используют то же разрешение."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pulseboard.test", content: content,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        do {
            try await client.add(request)
            statusMessage = "Тест запланирован через 5 секунд. Проверяю доставку…"
            testTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(7))
                guard !Task.isCancelled, let self else { return }
                await checkTestDelivery()
            }
        } catch { statusMessage = "Тест не удалось запланировать: \(error.localizedDescription)" }
    }

    func checkTestDelivery() async {
        let delivered = await client.deliveredIDs()
        if delivered.contains("pulseboard.test") {
            statusMessage = "macOS доставила тестовое уведомление. Если баннер не появился, проверьте «Фокусирование» и стиль уведомлений Trace Desktop."
        } else {
            statusMessage = "Доставка теста пока не подтверждена. Проверьте Центр уведомлений, «Фокусирование» и настройки Trace Desktop; удалённый баннер уже не виден диагностике."
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse) async {
        guard let event = NotificationPlan.action(identifier: response.actionIdentifier,
                                                   userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { onEvent?(event) }
    }
}
