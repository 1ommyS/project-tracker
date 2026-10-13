import SwiftUI

/// Инлайн-редактор проекта: поля правятся прямо на месте и сохраняются
/// с задержкой после прекращения ввода, задачи — сразу.
struct ProjectDetailView: View {
    @Environment(AppStore.self) private var store
    let projectId: UUID

    private var project: Project? { store.projects.first { $0.id == projectId } }

    @State private var title = ""
    @State private var epic = ""
    @State private var parentProject = ""
    @State private var summary = ""
    @State private var tagsText = ""
    @State private var hydrated = false
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var showDone = false
    @State private var deleteConfirmation = false
    @State private var statusDay = Date.now
    @State private var artifactTitle = ""
    @State private var artifactURL = ""

    var body: some View {
        if let project {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerPanel(project)
                    infoPanel
                    statusesPanel(project)
                    artifactsPanel(project)
                    tasksPanel(project)
                    Text("Создан \(project.createdAt.formatted(date: .abbreviated, time: .omitted)) · обновлён \(RuDate.relative(project.updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
                .padding(PulseMetrics.screen)
                .frame(maxWidth: 880, alignment: .leading)
            }
            .softScrollFade()
            .confirmationDialog("Удалить «\(project.title)»?", isPresented: $deleteConfirmation) {
                Button("Переместить в Корзину", role: .destructive) { Task { await store.delete(project) } }
            } message: { Text("Папка проекта будет перемещена в системную Корзину и сможет быть восстановлена.") }
            .onAppear { hydrate(from: project) }
            .onDisappear { saveNow() }
            .onChange(of: title) { _, _ in markDirty() }
            .onChange(of: epic) { _, _ in markDirty() }
            .onChange(of: parentProject) { _, _ in markDirty() }
            .onChange(of: summary) { _, _ in markDirty() }
            .onChange(of: tagsText) { _, _ in markDirty() }
        }
    }

    // MARK: - Шапка

    private func headerPanel(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FadeOverflowRow { SectionEyebrow(text: project.pathLabel) }
            InlineEditableText(font: .title.bold(),
                               lineLimit: 2,
                               tooltip: "Клик — переименовать проект",
                               placeholder: "Название проекта",
                               text: title) { newTitle in
                title = newTitle
            }
            HStack(spacing: 10) {
                ProjectStateMenu(project: project)
                Spacer()
                projectMenu(project)
            }
        }
        .padding(PulseMetrics.card)
        .background(LinearGradient(colors: [store.palette.color.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
        .pulsePanel(radius: 12)
    }

    private func projectMenu(_ project: Project) -> some View {
        Menu {
            Button("Архивировать", systemImage: "archivebox") { Task { await store.archive(project) } }
            Divider()
            Button("Удалить", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
        } label: {
            Label("Ещё", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Информация

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Информация", systemImage: "info.circle").font(.title3.bold())
                Spacer()
                Text(isDirty ? "Сохранение…" : "Автосохранение")
                    .font(.caption)
                    .foregroundStyle(isDirty ? PulseStyle.amber : .secondary)
            }
            fieldRow("Эпик", text: $epic, prompt: "Например: Диплом")
            fieldRow("Проект", text: $parentProject, prompt: "Например: macOS-приложение")
            VStack(alignment: .leading, spacing: 5) {
                Text("Описание").font(.caption).foregroundStyle(.secondary)
                TextField("Короткое описание", text: $summary, axis: .vertical)
                    .lineLimit(2...5)
                    .fieldAppearance()
                    .arrowCursorOnExit()
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Теги").font(.caption).foregroundStyle(.secondary)
                TextField("через запятую", text: $tagsText)
                    .fieldAppearance()
                    .arrowCursorOnExit()
            }
        }
        .padding(18)
        .pulsePanel(radius: 12)
    }

    private func fieldRow(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text, prompt: Text(prompt))
                .fieldAppearance()
                .arrowCursorOnExit()
        }
    }

    // MARK: - Статусы по дням

    /// Статус за произвольную дату: выбор дня, текст, блокеры, чекбоксы.
    private func statusesPanel(_ project: Project) -> some View {
        let calendar = Calendar.current
        let entry = project.dailyStatus(on: statusDay)
        let quickDays = (0..<4).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now)) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Статусы по дням", systemImage: "calendar")
                    .font(.title3.bold())
                Spacer()
                DatePicker("", selection: $statusDay, displayedComponents: [.date])
                    .labelsHidden()
                    .frame(width: 132)
            }

            HStack(spacing: 6) {
                ForEach(quickDays, id: \.self) { day in
                    let isSelected = calendar.isDate(statusDay, inSameDayAs: day)
                    Button {
                        statusDay = day
                    } label: {
                        Text(RuDate.dayMonthShort(day))
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                    }
                    .buttonStyle(.glass)
                    .tint(isSelected ? store.palette.color : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Статус на \(RuDate.dayMonthShort(statusDay))\(calendar.isDateInToday(statusDay) ? " (сегодня)" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                InlineEditableText(font: .body,
                                   lineLimit: nil,
                                   tooltip: "Клик — править статус на этот день",
                                   placeholder: "Что было сделано, что дальше…",
                                   text: entry?.status ?? "") { newText in
                    Task { await store.setDailyStatus(text: newText, blockers: nil, for: project, on: statusDay) }
                }
                Text("Блокеры").font(.caption).foregroundStyle(.secondary)
                InlineEditableText(font: .body,
                                   color: (entry?.blockers ?? "").isEmpty ? .secondary : .red,
                                   lineLimit: nil,
                                   tooltip: "Клик — правка блокеров на этот день",
                                   placeholder: "—",
                                   text: entry?.blockers ?? "") { newBlockers in
                    Task { await store.setDailyStatus(text: nil, blockers: newBlockers, for: project, on: statusDay) }
                }
                if let entry {
                    ForEach(entry.tasks) { task in
                        Button {
                            Task { await store.toggleStatusTask(task, in: entry, for: project) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? PulseStyle.mint : .secondary)
                                Text(task.title)
                                    .strikethrough(task.isDone)
                                    .foregroundStyle(task.isDone ? .secondary : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(task.isDone ? "Вернуть в работу" : "Отметить выполненной")
                    }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(PulseMetrics.card)
        .pulsePanel(radius: 12)
    }

    // MARK: - Артефакты

    /// Гиперссылки по проекту: фигма, документы, репозитории.
    private func artifactsPanel(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Артефакты", systemImage: "link").font(.title3.bold())
                Spacer()
                Text("\(project.artifacts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ForEach(project.artifacts) { artifact in
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(.tint)
                    if let url = URL(string: artifact.url) {
                        Link(artifact.title, destination: url)
                            .font(.body.weight(.medium))
                            .underline()
                    } else {
                        Text(artifact.title).font(.body.weight(.medium))
                    }
                    Text(artifact.url)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button {
                        Task { await store.removeArtifact(artifact, from: project) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Убрать артефакт")
                }
                .padding(.vertical, 2)
                .contextMenu {
                    if let url = URL(string: artifact.url) {
                        Button("Открыть", systemImage: "safari") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Копировать ссылку", systemImage: "doc.on.doc") {
                        Clipboard.copy(artifact.url)
                    }
                    Divider()
                    Button("Убрать артефакт", systemImage: "trash", role: .destructive) {
                        Task { await store.removeArtifact(artifact, from: project) }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("https://… или obsidian://…", text: $artifactURL)
                    .textFieldStyle(.roundedBorder)
                    .arrowCursorOnExit()
                TextField("Название", text: $artifactTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .arrowCursorOnExit()
                Button("Добавить", systemImage: "plus") {
                    Task {
                        await store.addArtifact(title: artifactTitle, url: artifactURL, to: project)
                        artifactTitle = ""
                        artifactURL = ""
                    }
                }
                .buttonStyle(.glass)
                .disabled(artifactURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(PulseMetrics.card)
        .pulsePanel(radius: 12)
    }

    // MARK: - Задачи

    private func tasksPanel(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Задачи", systemImage: "checklist").font(.title3.bold())
                Spacer()
                if !project.tasks.isEmpty {
                    Text("\(project.doneTasks.count)/\(project.tasks.count) выполнено")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !project.tasks.isEmpty {
                HStack(spacing: 10) {
                    ProgressView(value: project.taskProgress).tint(PulseStyle.mint)
                    Text("\(Int(project.taskProgress * 100))%")
                        .font(.caption.bold()).foregroundStyle(.secondary).fixedSize()
                }
                .animation(.snappy, value: project.taskProgress)
            }

            TaskListSection(project: project, showDone: $showDone)
        }
        .padding(PulseMetrics.card)
        .pulsePanel(radius: 12)
    }

    // MARK: - Сохранение

    private func hydrate(from project: Project) {
        guard !hydrated else { return }
        hydrated = true
        title = project.title
        epic = project.epic
        parentProject = project.parentProject
        summary = project.summary
        tagsText = project.tags.joined(separator: ", ")
        isDirty = false
    }

    private func markDirty() {
        guard hydrated else { return }
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            saveFields()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveFields()
    }

    private func saveFields() {
        guard isDirty, let project, let newTitle = title.nilIfBlank else { return }
        isDirty = false
        var value = project
        value.title = newTitle
        value.epic = epic
        value.parentProject = parentProject
        value.summary = summary
        value.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task { await store.saveProject(value) }
    }
}

private extension View {
    func fieldAppearance() -> some View {
        self
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
