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
    @State private var status = ""
    @State private var tagsText = ""
    @State private var hydrated = false
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var showDone = false
    @State private var deleteConfirmation = false

    var body: some View {
        if let project {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerPanel(project)
                    infoPanel
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
        .onChange(of: status) { _, _ in markDirty() }
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
            VStack(alignment: .leading, spacing: 5) {
                Text("Статус").font(.caption).foregroundStyle(.secondary)
                TextField("Что сейчас по проекту — одной строкой", text: $status, axis: .vertical)
                    .lineLimit(1...3)
                    .fieldAppearance()
                    .arrowCursorOnExit()
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
        status = project.status
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
        value.status = status
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
