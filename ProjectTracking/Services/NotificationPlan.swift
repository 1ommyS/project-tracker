import Foundation
import UserNotifications

nonisolated enum NotificationPlan {
    static let categoryID = "pulseboard.task"
    static let completeAction = "pulseboard.task.complete"
    static let idPrefix = "pulseboard.task."

    struct Input: Equatable, Sendable {
        struct TaskInput: Equatable, Sendable {
            let id: UUID
            let title: String
            let done: Bool
            let due: Date?
        }
        let id: UUID
        let title: String
        let completed: Bool
        let tasks: [UUID: TaskInput]
    }

    /// Deliberately excludes status history, Markdown previews, links and metadata.
    static func inputSignature(projects: [Project]) -> [UUID: Input] {
        Dictionary(projects.map { project in
            let tasks = Dictionary(project.tasks.map {
                ($0.id, Input.TaskInput(id: $0.id, title: $0.title, done: $0.isDone, due: $0.dueDate))
            }, uniquingKeysWith: { a, _ in a })
            return (project.id, Input(id: project.id, title: project.title, completed: project.isCompleted, tasks: tasks))
        }, uniquingKeysWith: { a, _ in a })
    }

    static func requests(projects: [Project], now: Date, calendar: Calendar) -> [UNNotificationRequest] {
        projects.filter { !$0.isCompleted }.flatMap { project in
            project.tasks.compactMap { task in
                guard !task.isDone, let due = task.dueDate, due > now else { return nil }
                let parts = calendar.dateComponents([.hour, .minute], from: due)
                let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due)
                let fire: Date
                if parts.hour == 23 && parts.minute == 59, let morning, morning > now { fire = morning }
                else { fire = due }
                let content = UNMutableNotificationContent()
                content.title = "Пора выполнить задачу"
                content.subtitle = project.title
                content.body = task.title
                content.sound = .default
                content.threadIdentifier = project.id.uuidString
                content.categoryIdentifier = categoryID
                content.userInfo = ["projectID": project.id.uuidString, "taskID": task.id.uuidString]
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                components.timeZone = calendar.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                return UNNotificationRequest(identifier: task.notificationID, content: content, trigger: trigger)
            }
        }
    }

    enum Action: Equatable, Sendable {
        case openProject(UUID)
        case completeTask(projectID: UUID, taskID: UUID)
    }

    static func action(identifier: String, userInfo: [AnyHashable: Any]) -> Action? {
        guard let projectID = (userInfo["projectID"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        if identifier == completeAction {
            guard let taskID = (userInfo["taskID"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return .completeTask(projectID: projectID, taskID: taskID)
        }
        guard identifier == UNNotificationDefaultActionIdentifier else { return nil }
        return .openProject(projectID)
    }
}
