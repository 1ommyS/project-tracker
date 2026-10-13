import AppKit
import SwiftUI

// MARK: - Буфер обмена

enum Clipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

// MARK: - Контекстное меню проекта

/// Единое меню проекта: открытие, состояние, архивация, новая задача,
/// показ в Finder, копирование названия и удаление с подтверждением.
struct ProjectContextMenu: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @Binding var confirmDelete: Bool

    var body: some View {
        Button("Открыть в редакторе", systemImage: "square.and.pencil") {
            store.openProject(project.id)
        }
        Divider()
        Picker("Состояние", selection: Binding(
            get: { project.state },
            set: { newState in
                var value = project
                value.state = newState
                Task { await store.saveProject(value) }
            }
        )) {
            ForEach(ProjectState.allCases.filter { $0 != .archived }) { state in
                Label(state.title, systemImage: state.symbol).tag(state)
            }
        }
        if project.isCompleted {
            Button("Вернуть в работу", systemImage: "arrow.uturn.backward.circle") {
                Task { await store.restore(project) }
            }
        } else {
            Button("Архивировать", systemImage: "archivebox") {
                Task { await store.archive(project) }
            }
        }
        Divider()
        Button("Новая задача…", systemImage: "plus.circle") {
            store.quickTaskProjectID = project.id
            store.quickTaskRequest &+= 1
        }
        .disabled(project.isCompleted)
        Button("Показать в Finder", systemImage: "folder") {
            guard let url = project.folderURL, FileManager.default.fileExists(atPath: url.path) else {
                store.errorMessage = "Папка проекта ещё не создана на диске."
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        Button("Копировать название", systemImage: "doc.on.doc") {
            Clipboard.copy(project.title)
        }
        Divider()
        Button("Удалить…", systemImage: "trash", role: .destructive) {
            confirmDelete = true
        }
    }
}

private struct ProjectContextMenuModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var confirmDelete = false

    func body(content: Content) -> some View {
        content
            .contextMenu { ProjectContextMenu(project: project, confirmDelete: $confirmDelete) }
            .confirmationDialog("Удалить «\(project.title)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Переместить в Корзину", role: .destructive) {
                    Task { await store.delete(project) }
                }
            } message: {
                Text("Папка проекта будет перемещена в системную Корзину и сможет быть восстановлена.")
            }
    }
}

extension View {
    /// Двухпальцевый тап/правый клик по любому представлению проекта.
    func projectContextMenu(_ project: Project) -> some View {
        modifier(ProjectContextMenuModifier(project: project))
    }
}

// MARK: - Контекстное меню задачи

/// Меню задачи: выполнение, быстрые сроки, редактор, дублирование,
/// копирование названия, удаление.
struct TaskContextMenu: View {
    @Environment(AppStore.self) private var store
    let task: ProjectTask
    let project: Project
    var onEdit: (() -> Void)? = nil

    var body: some View {
        Button(task.isDone ? "Вернуть в работу" : "Выполнить",
               systemImage: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill") {
            Task { await store.toggleTask(task, in: project) }
        }
        Menu("Срок", systemImage: "bell") {
            Button("Сегодня · весь день") { set(allDay(offset: 0)) }
            Button("Завтра · весь день") { set(allDay(offset: 1)) }
            Button("Через неделю") { set(weekFromNow()) }
            if task.dueDate != nil {
                Divider()
                Button("Убрать срок") { set(nil) }
            }
            if let onEdit {
                Button("Выбрать в календаре…", systemImage: "calendar") { onEdit() }
            }
        }
        if let onEdit {
            Button("Редактировать…", systemImage: "pencil") { onEdit() }
        }
        Button("Дублировать", systemImage: "plus.on.square") {
            Task { await store.duplicateTask(task, in: project) }
        }
        Button("Копировать название", systemImage: "doc.on.doc") {
            Clipboard.copy(task.title)
        }
        Divider()
        Button("Удалить", systemImage: "trash", role: .destructive) {
            Task { await store.deleteTask(task, in: project) }
        }
    }

    private func set(_ date: Date?) {
        Task { await store.setTaskDueDate(task, to: date, in: project) }
    }

    private func allDay(offset: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
    }

    private func weekFromNow() -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    }
}

extension View {
    /// Двухпальцевый тап/правый клик по строке задачи.
    func taskContextMenu(task: ProjectTask, project: Project, onEdit: (() -> Void)? = nil) -> some View {
        contextMenu { TaskContextMenu(task: task, project: project, onEdit: onEdit) }
    }
}
