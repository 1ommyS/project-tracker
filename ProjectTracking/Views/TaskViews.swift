import SwiftUI

// MARK: - Строка задачи

struct TaskRowView: View {
    let task: ProjectTask
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRename: (String) -> Void
    let onSetDate: (Date?) -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? PulseStyle.mint : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            InlineEditableText(font: .body,
                               color: task.isDone ? .secondary : .primary,
                               strikethrough: task.isDone,
                               lineLimit: nil,
                               tooltip: "Клик — переименовать задачу",
                               placeholder: "Задача",
                               text: task.title,
                               onCommit: onRename)

            Spacer(minLength: 8)

            InlineEditableDate(date: task.dueDate, isDone: task.isDone, onCommit: onSetDate)

            Button(action: onEdit) {
                Image(systemName: task.isDone ? "pencil.circle" : "pencil.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Редактировать задачу")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .animation(.snappy, value: task.isDone)
        .contextMenu {
            Button(task.isDone ? "Вернуть в работу" : "Отметить выполненной",
                   systemImage: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill") { onToggle() }
            Button("Редактировать…", systemImage: "pencil") { onEdit() }
            if let onDelete {
                Divider()
                Button("Удалить", systemImage: "trash", role: .destructive) { onDelete() }
            }
        }
    }
}

// MARK: - Блок задач проекта (лента и редактор)

struct TaskListSection: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @Binding var showDone: Bool

    @State private var taskEditor: TaskEditorContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(project.openTasks) { task in
                row(task)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if project.openTasks.isEmpty && !project.doneTasks.isEmpty {
                Label("Все задачи выполнены", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PulseStyle.mint)
                    .padding(.vertical, 6)
            }
            if project.tasks.isEmpty {
                Text("Задач пока нет — добавьте первую в поле ниже.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            }
            if !project.doneTasks.isEmpty {
                DisclosureGroup("Выполнено · \(project.doneTasks.count)", isExpanded: $showDone) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(project.doneTasks) { task in row(task) }
                    }
                    .padding(.top, 4)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            QuickTaskComposer { title, dueDate in
                Task { await store.addTask(title: title, dueDate: dueDate, to: project) }
            }
        }
        .sheet(item: $taskEditor) { context in TaskEditorView(context: context) }
        .animation(.snappy, value: project.tasks.map(\.id))
    }

    private func row(_ task: ProjectTask) -> some View {
        TaskRowView(task: task,
                    onToggle: { Task { await store.toggleTask(task, in: project) } },
                    onEdit: { taskEditor = TaskEditorContext(projectID: project.id, taskID: task.id) },
                    onRename: { newTitle in Task { await store.renameTask(task, to: newTitle, in: project) } },
                    onSetDate: { newDate in Task { await store.setTaskDueDate(task, to: newDate, in: project) } },
                    onDelete: { Task { await store.deleteTask(task, in: project) } })
    }
}

// MARK: - Быстрый ввод с распознаванием срока

struct QuickTaskComposer: View {
    var onAdd: (String, Date?) -> Void
    @State private var text = ""

    private var parsed: (title: String, dueDate: Date?) { TaskInputParser.parse(text) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(PulseStyle.blue)
                .font(.title3)
            TextField("Новая задача — например: «Позвонить завтра 18:00»", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(add)
                .arrowCursorOnExit()
            if let date = parsed.dueDate {
                Label(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()), systemImage: "bell.badge.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PulseStyle.blue)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(PulseStyle.blue.opacity(0.1), in: Capsule())
                    .help("Распознанный срок: слова «сегодня», «завтра», дата «25.12» и время «18:30» превращаются в напоминание.")
                    .transition(.opacity.combined(with: .scale))
            }
            if text.nilIfBlank != nil {
                Button("Добавить", systemImage: "plus", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(parsed.title.isEmpty)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.snappy, value: text)
    }

    private func add() {
        let value = parsed
        guard !value.title.isEmpty else { return }
        onAdd(value.title, value.dueDate)
        text = ""
    }
}

// MARK: - Редактор задачи

struct TaskEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let context: TaskEditorContext

    @State private var hydrated = false
    @State private var existingTask: ProjectTask?
    @State private var title = ""
    @State private var isDone = false
    @State private var hasDueDate = false
    @State private var dueDate = TaskEditorView.defaultDue
    @State private var projectID: UUID

    init(context: TaskEditorContext) {
        self.context = context
        _projectID = State(initialValue: context.projectID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingTask == nil ? "Новая задача" : "Редактирование задачи")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(PulseMetrics.screen)
            .padding(.top, 16)

            Divider()

            Form {
                if existingTask == nil {
                    Section("Проект") {
                        Picker("Проект", selection: $projectID) {
                            ForEach(store.activeProjects) { project in
                                Text(project.pathLabel).tag(project.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
                Section("Задача") {
                    TextField("Что нужно сделать?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.title3.weight(.medium))
                        .arrowCursorOnExit()
                    if existingTask != nil {
                        Toggle("Выполнена", isOn: $isDone)
                    }
                }
                Section("Срок и напоминание") {
                    Toggle("Напомнить в срок", isOn: $hasDueDate)
                    if hasDueDate {
                        HStack(spacing: 8) {
                            presetButton("Сегодня", daysAhead: 0)
                            presetButton("Завтра", daysAhead: 1)
                            presetButton("Через неделю", daysAhead: 7)
                        }
                        DatePicker("Дата и время", selection: $dueDate)
                    }
                    if store.notifications.authorization != .allowed {
                        HStack {
                            Text("Уведомления \(store.notifications.authorization.title.lowercased()) — без них напоминание не придёт.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Разрешить") {
                                Task {
                                    await store.notifications.requestAccess()
                                    await store.notifications.syncIfAllowed(projects: store.projects)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                if existingTask != nil {
                    Button("Удалить задачу", role: .destructive) {
                        Task {
                            await store.deleteTask(existingTask!, in: store.projects.first { $0.id == context.projectID }!)
                            dismiss()
                        }
                    }
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.nilIfBlank == nil || (existingTask == nil && store.projects.first { $0.id == projectID } == nil))
            }
            .padding(PulseMetrics.screen)
        }
        .frame(minWidth: 440, idealWidth: 560, maxWidth: 680, minHeight: 400, idealHeight: 480, maxHeight: 640)
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true
        if store.projects.first(where: { $0.id == projectID }) == nil, let fallback = store.activeProjects.first {
            projectID = fallback.id
        }
        guard let taskID = context.taskID,
              let project = store.projects.first(where: { $0.id == context.projectID }),
              let task = project.tasks.first(where: { $0.id == taskID }) else { return }
        existingTask = task
        title = task.title
        isDone = task.isDone
        hasDueDate = task.dueDate != nil
        dueDate = task.dueDate ?? TaskEditorView.defaultDue
    }

    private func presetButton(_ title: String, daysAhead: Int) -> some View {
        Button(title) {
            let calendar = Calendar.current
            let target = calendar.date(byAdding: .day, value: daysAhead, to: .now) ?? .now
            var components = calendar.dateComponents([.year, .month, .day], from: target)
            let time = calendar.dateComponents([.hour, .minute], from: dueDate)
            components.hour = time.hour ?? 9
            components.minute = time.minute ?? 0
            dueDate = calendar.date(from: components) ?? dueDate
        }
        .buttonStyle(.glass)
    }

    private func save() {
        guard let title = title.nilIfBlank else { return }
        let due = hasDueDate ? dueDate : nil
        let targetProjectID = existingTask == nil ? projectID : context.projectID
        guard let project = store.projects.first(where: { $0.id == targetProjectID }) else { return }
        Task {
            if var task = existingTask {
                task.title = title
                task.isDone = isDone
                task.dueDate = due
                await store.updateTask(task, in: project)
            } else {
                await store.addTask(title: title, dueDate: due, to: project)
            }
            dismiss()
        }
    }

    static var defaultDue: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components) ?? .now
    }
}
