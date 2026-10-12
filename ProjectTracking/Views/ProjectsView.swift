import SwiftUI

struct ProjectsView: View {
    @Environment(AppStore.self) private var store
    let onUpdate: (Project) -> Void
    @State private var query = ""

    private var filtered: [Project] {
        let active = store.projects.filter { !$0.isArchived && $0.state != .archived }
        guard !query.isEmpty else { return active }
        return active.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        @Bindable var store = store
        GeometryReader { proxy in
            if proxy.size.width >= 790 {
                regularLayout(store: store)
            } else {
                compactLayout(store: store)
            }
        }
        .navigationTitle("Проекты")
    }

    private func regularLayout(store: AppStore) -> some View {
        @Bindable var store = store
        return HSplitView {
            List(filtered, selection: $store.selectedProjectID) { project in
                ProjectListRow(project: project).padding(.vertical, 4).tag(project.id)
            }
            .searchable(text: $query, prompt: "Фильтр проектов")
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .frame(minWidth: 260, idealWidth: 310, maxWidth: 380)

            if let project = store.selectedProject {
                ProjectDetailView(project: project, onUpdate: { onUpdate(project) }).id(project.id)
            } else {
                EmptyState(symbol: "sidebar.right", title: "Выберите проект", message: "Здесь появятся описание, задачи, заметки и история.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func compactLayout(store: AppStore) -> some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Проект", systemImage: "square.stack.3d.up.fill").font(.headline)
                Picker("Проект", selection: $store.selectedProjectID) {
                    Text("Выберите проект").tag(UUID?.none)
                    ForEach(filtered) { Text($0.pathLabel).tag(Optional($0.id)) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
            }
            .padding(12).background(.ultraThinMaterial)
            Divider()
            if let project = store.selectedProject {
                ProjectDetailView(project: project, onUpdate: { onUpdate(project) }).id(project.id)
            } else {
                EmptyState(symbol: "sidebar.right", title: "Выберите проект", message: "Выберите проект в меню сверху.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ProjectListRow: View {
    let project: Project
    private var done: Int { project.tasks.filter(\.isDone).count }
    private var progress: Double { project.tasks.isEmpty ? 0 : Double(done) / Double(project.tasks.count) }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(stateColor.opacity(0.13)).frame(width: 40, height: 40)
                Image(systemName: project.state.symbol).foregroundStyle(stateColor).font(.system(size: 15, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(project.title).font(.headline).lineLimit(1)
                if project.epic.nilIfBlank != nil || project.parentProject.nilIfBlank != nil {
                    Text([project.epic, project.parentProject].compactMap(\.nilIfBlank).joined(separator: " › "))
                        .font(.caption2.weight(.medium)).foregroundStyle(PulseStyle.blue).lineLimit(1)
                }
                Text(project.summary.nilIfBlank ?? "Без описания").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 7) {
                    if !project.tasks.isEmpty {
                        ProgressView(value: progress).tint(PulseStyle.mint).frame(maxWidth: 70)
                        Text("\(done)/\(project.tasks.count)")
                    }
                    Spacer()
                    Text(project.latestStatus?.date.formatted(date: .numeric, time: .omitted) ?? "Нет статусов")
                }.font(.caption2).foregroundStyle(.tertiary)
            }
        }.padding(.vertical, 4)
    }
    private var stateColor: Color {
        switch project.state { case .active: PulseStyle.blue; case .blocked: .red; case .onHold: PulseStyle.amber; case .done: PulseStyle.mint; case .planned: PulseStyle.indigo; case .archived: .secondary }
    }
}

struct ProjectDetailView: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let onUpdate: () -> Void
    @State private var editing = false
    @State private var deleteConfirmation = false
    @State private var notes: String
    @State private var saveTask: Task<Void, Never>?
    @State private var editingStatus: DailyStatus?
    @State private var newTaskTitle = ""
    @State private var newTaskDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @FocusState private var quickTaskFocused: Bool

    init(project: Project, onUpdate: @escaping () -> Void) {
        self.project = project; self.onUpdate = onUpdate; _notes = State(initialValue: project.notes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        projectHeader
                        Spacer(minLength: 16)
                        projectActions
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        projectHeader
                        projectActions.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(22)
                .background(LinearGradient(colors: [PulseStyle.blue.opacity(0.1), PulseStyle.indigo.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
                .pulsePanel(radius: 22)

                VStack(alignment: .leading, spacing: 12) {
                    HStack { Label("Задачи", systemImage: "checklist").font(.title3.bold()); Spacer(); Text("С напоминаниями").font(.caption).foregroundStyle(.secondary) }
                    ForEach(project.tasks) { task in
                        taskRow(task)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { quickTaskField; quickTaskDate; quickTaskButton }
                        VStack(alignment: .leading, spacing: 10) {
                            quickTaskField
                            HStack { quickTaskDate; Spacer(); quickTaskButton }
                        }
                    }.padding(.top, 4)
                }.padding(18).pulsePanel(radius: 16)

                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label("Заметки", systemImage: "note.text").font(.title3.bold()); Spacer(); Text("Автосохранение").font(.caption).foregroundStyle(.secondary) }
                    MarkdownEditor(text: $notes)
                        .frame(minHeight: 220)
                        .onChange(of: notes) { _, newValue in scheduleSave(newValue) }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("История статусов", systemImage: "clock.arrow.circlepath").font(.title3.bold())
                    if project.statuses.isEmpty { Text("История появится после первого обновления.").foregroundStyle(.secondary).padding(.vertical, 24) }
                    ForEach(project.statuses) { status in StatusRow(status: status) { editingStatus = status } }
                }
            }.padding(20).frame(maxWidth: 900, alignment: .leading)
        }
        .softScrollFade()
        .sheet(isPresented: $editing) { ProjectEditorView(project: project) }
        .sheet(item: $editingStatus) { status in
            StatusEditorView(project: project, initialDate: status.date) { value, _ in
                await store.saveStatus(value, projectID: project.id)
                editingStatus = nil
            }
        }
        .confirmationDialog("Удалить «\(project.title)»?", isPresented: $deleteConfirmation) {
            Button("Переместить в Корзину", role: .destructive) { Task { await store.delete(project) } }
        } message: { Text("Папка проекта будет перемещена в системную Корзину и сможет быть восстановлена.") }
        .task(id: store.quickTaskRequest) {
            guard store.quickTaskRequest > 0, store.quickTaskProjectID == project.id else { return }
            quickTaskFocused = true
        }
    }

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            FadeOverflowRow { SectionEyebrow(text: project.pathLabel) }
            ViewThatFits(in: .horizontal) {
                HStack { projectTitle; StateBadge(state: project.state) }
                VStack(alignment: .leading, spacing: 7) { projectTitle; StateBadge(state: project.state) }
            }
            Text(project.summary.nilIfBlank ?? "Описание не добавлено").font(.title3).foregroundStyle(.secondary)
            if !project.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(project.tags, id: \.self) { Text("#\($0)").font(.caption.weight(.medium)).foregroundStyle(PulseStyle.blue).padding(.horizontal, 8).padding(.vertical, 4).background(PulseStyle.blue.opacity(0.1), in: Capsule()) }
                }
            }
        }
    }

    private var projectTitle: some View {
        Text(project.title).font(.system(size: 32, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(2)
    }

    private var projectActions: some View {
        HStack {
            Button("Статус", systemImage: "square.and.pencil", action: onUpdate).buttonStyle(.borderedProminent)
            Menu {
                Button("Редактировать", systemImage: "pencil") { editing = true }
                Button("Архивировать", systemImage: "archivebox") { Task { await store.archive(project) } }
                Divider()
                Button("Удалить", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private var quickTaskField: some View {
        TextField("Быстро добавить задачу…", text: $newTaskTitle).focused($quickTaskFocused)
    }

    private var quickTaskDate: some View {
        DatePicker("Срок", selection: $newTaskDate).labelsHidden().frame(maxWidth: 180)
    }

    private var quickTaskButton: some View {
        Button("Добавить", systemImage: "plus") { addTask() }.buttonStyle(.borderedProminent).disabled(newTaskTitle.nilIfBlank == nil)
    }

    @ViewBuilder
    private func taskRow(_ task: ProjectTask) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                taskLeading(task)
                Spacer(minLength: 12)
                taskDueBadge(task)
            }
            VStack(alignment: .leading, spacing: 8) {
                taskLeading(task)
                taskDueBadge(task).padding(.leading, 30)
            }
        }
    }

    private func taskLeading(_ task: ProjectTask) -> some View {
        HStack(spacing: 10) {
            Button { toggleTask(task) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(task.isDone ? PulseStyle.mint : .secondary)
            }
            .buttonStyle(.plain)
            Text(task.title)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func taskDueBadge(_ task: ProjectTask) -> some View {
        if let due = task.dueDate {
            Label(due.formatted(.dateTime.day().month(.abbreviated).hour().minute()), systemImage: "bell.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(!task.isDone && due < .now ? .red : PulseStyle.blue)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((!task.isDone && due < .now ? Color.red : PulseStyle.blue).opacity(0.1), in: Capsule())
        }
    }

    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            var updated = project; updated.notes = value
            await store.saveProject(updated)
        }
    }

    private func toggleTask(_ task: ProjectTask) {
        var value = project
        guard let index = value.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        value.tasks[index].isDone.toggle()
        Task { await store.saveProject(value) }
    }

    private func addTask() {
        guard let title = newTaskTitle.nilIfBlank else { return }
        var value = project
        value.tasks.append(ProjectTask(title: title, isDone: false, dueDate: newTaskDate))
        newTaskTitle = ""
        Task { await store.saveProject(value) }
    }
}

struct StatusRow: View {
    let status: DailyStatus
    let onEdit: () -> Void
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let text = status.completed.nilIfBlank { section("Выполнено", text) }
                if let text = status.plans.nilIfBlank { section("Планы", text) }
                if let text = status.blockers.nilIfBlank { section("Блокеры", text) }
                if let text = status.notes.nilIfBlank { section("Заметки", text) }
            }.padding(.top, 12)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(status.date.formatted(date: .long, time: .omitted)).font(.headline)
                    Spacer(); StateBadge(state: status.state)
                    Button("Изменить", systemImage: "pencil", action: onEdit).labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(status.date.formatted(date: .long, time: .omitted)).font(.headline)
                    HStack {
                        StateBadge(state: status.state)
                        Spacer()
                        Button("Изменить", systemImage: "pencil", action: onEdit).buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption.bold()).foregroundStyle(.secondary); Text(text) }
    }
}

struct MarkdownEditor: View {
    @Binding var text: String
    @State private var preview = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Редактор", systemImage: "pencil.line") { preview = false }.buttonStyle(.borderless).foregroundStyle(preview ? .secondary : .primary)
                Button("Предпросмотр", systemImage: "eye") { preview = true }.buttonStyle(.borderless).foregroundStyle(preview ? .primary : .secondary)
                Spacer()
                if !preview {
                    Button("Жирный") { text += "**текст**" }.keyboardShortcut("b", modifiers: .command)
                    Button("Ссылка") { text += "[[Проект]]" }.keyboardShortcut("l", modifiers: .command)
                }
            }.padding(10)
            Divider()
            if preview {
                ScrollView { Text((try? AttributedString(markdown: text)) ?? AttributedString(text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14) }
            } else {
                TextEditor(text: $text).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden).padding(10)
            }
        }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct NewProjectView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var epic = ""
    @State private var parentProject = ""
    @State private var summary = ""
    @State private var tags = ""
    @State private var state = ProjectState.active
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Новый проект").font(.title.bold())
            Form {
                Section("Иерархия") {
                    TextField("Эпик", text: $epic, prompt: Text("Например: Диплом"))
                    TextField("Проект", text: $parentProject, prompt: Text("Например: macOS-приложение"))
                    TextField("Часть проекта", text: $title, prompt: Text("Например: Markdown-хранилище"))
                    if title.nilIfBlank != nil { LabeledContent("Путь") { Text([epic, parentProject, title].compactMap(\.nilIfBlank).joined(separator: " › ")).foregroundStyle(PulseStyle.blue) } }
                }
                TextField("Короткое описание", text: $summary, axis: .vertical).lineLimit(3...6)
                TextField("Теги через запятую", text: $tags)
                Picker("Состояние", selection: $state) { ForEach(ProjectState.allCases.filter { $0 != .archived }) { Text($0.title).tag($0) } }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Создать") { Task { _ = await store.createProject(title: title, epic: epic, parentProject: parentProject, summary: summary, tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, state: state); dismiss() } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(title.nilIfBlank == nil) }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 580, maxWidth: 700, minHeight: 440, idealHeight: 540, maxHeight: 760)
    }
}

struct ProjectEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var title: String
    @State private var epic: String
    @State private var parentProject: String
    @State private var summary: String
    @State private var tags: String
    @State private var state: ProjectState
    @State private var tasks: [ProjectTask]
    @State private var newTask = ""
    init(project: Project) {
        self.project = project; _title = State(initialValue: project.title); _epic = State(initialValue: project.epic); _parentProject = State(initialValue: project.parentProject); _summary = State(initialValue: project.summary)
        _tags = State(initialValue: project.tags.joined(separator: ", ")); _state = State(initialValue: project.state); _tasks = State(initialValue: project.tasks)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Редактировать проект").font(.title2.bold())
            Form {
                Section("Иерархия") { TextField("Эпик", text: $epic); TextField("Проект", text: $parentProject); TextField("Часть проекта", text: $title) }
                TextField("Описание", text: $summary, axis: .vertical); TextField("Теги", text: $tags)
                Picker("Состояние", selection: $state) { ForEach(ProjectState.allCases.filter { $0 != .archived }) { Text($0.title).tag($0) } }
                Section("Задачи") {
                    ForEach($tasks) { $task in
                        VStack(alignment: .leading) {
                            Toggle(task.title, isOn: $task.isDone)
                            HStack { Toggle("Дедлайн", isOn: Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? (Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) : nil })); if task.dueDate != nil { DatePicker("", selection: Binding(get: { task.dueDate ?? .now }, set: { task.dueDate = $0 })).labelsHidden() } }
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack { TextField("Новая задача", text: $newTask); Button("Добавить") { tasks.append(ProjectTask(title: newTask, isDone: false, dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now))); newTask = "" }.disabled(newTask.nilIfBlank == nil) }
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Сохранить") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(title.nilIfBlank == nil) }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 600, maxWidth: 720, minHeight: 500, idealHeight: 620, maxHeight: 820)
    }
    private func save() {
        var value = project; value.title = title; value.epic = epic; value.parentProject = parentProject; value.summary = summary; value.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }; value.state = state; value.tasks = tasks
        Task { await store.saveProject(value); dismiss() }
    }
}
