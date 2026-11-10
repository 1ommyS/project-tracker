import SwiftUI

// MARK: - Строка задачи

struct TaskRowView: View {
    let task: ProjectTask
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onSetDate: (Date?) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? PulseStyle.mint : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Вернуть задачу в работу" : "Выполнить задачу")
            .padding(.top, 1)

            Button(action: onEdit) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .strikethrough(task.isDone)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help("Редактировать задачу")

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
                await store.addTask(title: title, dueDate: dueDate, to: project)
            }
        }
        .sheet(item: $taskEditor) { context in TaskEditorView(context: context) }
    }

    private func row(_ task: ProjectTask) -> some View {
        TaskRowView(task: task,
                    onToggle: { Task { await store.toggleTask(task, in: project) } },
                    onEdit: { taskEditor = TaskEditorContext(projectID: project.id, taskID: task.id) },
                    onSetDate: { newDate in Task { await store.setTaskDueDate(task, to: newDate, in: project) } })
            .taskContextMenu(task: task, project: project) {
                taskEditor = TaskEditorContext(projectID: project.id, taskID: task.id)
            }
    }
}

// MARK: - Быстрый ввод с распознаванием срока

struct QuickTaskComposer: View {
    @Environment(AppStore.self) private var store
    var onAdd: (String, Date?) async -> Bool
    @State private var text = ""
    @State private var isAdding = false

    var body: some View {
        let parsed = TaskInputParser.parseDetailed(text)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").foregroundStyle(.tint)
                HighlightingTextField(text: $text, highlightRange: parsed.highlightRange,
                                      accent: NSColor(store.palette.color), onSubmit: add)
                    .frame(height: 22)
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text("Новая задача, например: позвонить завтра 18:00")
                                .foregroundStyle(.tertiary).lineLimit(1).allowsHitTesting(false)
                        }
                    }
                Button("Добавить", action: add)
                    .disabled(parsed.title.isEmpty || isAdding)
            }
            Text(parsed.dueDate.map { "Напоминание: " + RuDate.dayMonthTime($0) } ?? "Срок можно указать прямо в тексте")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 18, alignment: .leading)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .disabled(isAdding)
    }

    private func add() {
        let value = TaskInputParser.parseDetailed(text)
        guard !value.title.isEmpty else { return }
        guard !isAdding else { return }
        let submitted = text
        isAdding = true
        Task {
            let saved = await onAdd(value.title, value.dueDate)
            if saved, text == submitted { text = "" }
            isAdding = false
        }
    }
}

// MARK: - Редактор задачи

struct TaskEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let context: TaskEditorContext

    @State private var hydrated = false
    @State private var isSaving = false
    @State private var saveError: String?
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
                                Text(project.title).tag(project.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
                Section("Задача") {
                    TextField("Что нужно сделать?", text: $title, axis: .vertical)
                        .lineLimit(3)
                        .frame(height: 64, alignment: .top)
                        .font(.title3.weight(.medium))
                        if existingTask != nil {
                        Toggle("Выполнена", isOn: $isDone)
                    }
                }
                Section("Срок и напоминание") {
                    Toggle("Напомнить в срок", isOn: $hasDueDate)
                    if hasDueDate {
                        HStack(spacing: 2) {
                            DayChip(title: "Сегодня", isSelected: isSameDay(dueDate, daysAhead: 0), accent: store.palette.color) {
                                applyPreset(daysAhead: 0)
                            }
                            DayChip(title: "Завтра", isSelected: isSameDay(dueDate, daysAhead: 1), accent: store.palette.color) {
                                applyPreset(daysAhead: 1)
                            }
                            DayChip(title: "Через неделю", isSelected: isSameDay(dueDate, daysAhead: 7), accent: store.palette.color) {
                                applyPreset(daysAhead: 7)
                            }
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
            if let saveError { Text(saveError).foregroundStyle(.red).padding(.horizontal, PulseMetrics.screen) }

            HStack {
                if existingTask != nil {
                    Button("Удалить задачу", role: .destructive) {
                        Task {
                            guard let task = existingTask,
                                  let project = store.projects.first(where: { $0.id == context.projectID }) else { return }
                            isSaving = true
                            if await store.deleteTask(task, in: project) { dismiss() }
                            else { saveError = store.errorMessage }
                            isSaving = false
                        }
                    }
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.nilIfBlank == nil || (context.taskID != nil && existingTask == nil)
                              || store.projects.first { $0.id == projectID } == nil)
            }
            .padding(PulseMetrics.screen)
        }
        .frame(minWidth: 440, idealWidth: 560, maxWidth: 680, minHeight: 400, idealHeight: 480, maxHeight: 640)
        .onAppear(perform: hydrate)
        .disabled(isSaving)
        .interactiveDismissDisabled()
    }

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true
        if store.projects.first(where: { $0.id == projectID }) == nil, let fallback = store.activeProjects.first {
            projectID = fallback.id
        }
        guard let taskID = context.taskID else { return }
        guard let project = store.projects.first(where: { $0.id == context.projectID }),
              let task = project.tasks.first(where: { $0.id == taskID }) else {
            saveError = "Задача больше не доступна. Откройте её заново из проекта."
            return
        }
        existingTask = task
        title = task.title
        isDone = task.isDone
        hasDueDate = task.dueDate != nil
        dueDate = task.dueDate ?? TaskEditorView.defaultDue
    }

    private func isSameDay(_ date: Date, daysAhead: Int) -> Bool {
        guard let target = Calendar.current.date(byAdding: .day, value: daysAhead, to: .now) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: target)
    }

    private func applyPreset(daysAhead: Int) {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: daysAhead, to: .now) ?? .now
        var components = calendar.dateComponents([.year, .month, .day], from: target)
        let time = calendar.dateComponents([.hour, .minute], from: dueDate)
        components.hour = time.hour ?? 9
        components.minute = time.minute ?? 0
        dueDate = calendar.date(from: components) ?? dueDate
    }

    private func save() {
        guard let title = title.nilIfBlank else { return }
        let due = hasDueDate ? dueDate : nil
        let targetProjectID = existingTask == nil ? projectID : context.projectID
        guard let project = store.projects.first(where: { $0.id == targetProjectID }) else { return }
        isSaving = true
        Task {
            let saved: Bool
            if var task = existingTask {
                task.title = title
                task.isDone = isDone
                task.dueDate = due
                saved = await store.updateTask(task, in: project)
            } else {
                saved = await store.addTask(title: title, dueDate: due, to: project)
            }
            isSaving = false
            if saved { dismiss() }
            else { saveError = store.errorMessage ?? "Не удалось сохранить задачу." }
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
