import SwiftUI

/// Проект открывается для просмотра; переименование — отдельная явная команда.
struct ProjectDetailView: View {
    @Environment(AppStore.self) private var store
    let projectId: UUID
    @State private var showDone = false
    @State private var statusDay = Date.now
    @State private var showingRename = false

    private var project: Project? { store.projects.first { $0.id == projectId } }

    var body: some View {
        if let project {
            ScrollView {
                VStack(alignment: .leading, spacing: PulseMetrics.card) {
                    HStack(alignment: .top) {
                        Text(project.title).font(.title.bold()).textSelection(.enabled)
                        Spacer()
                        Button("Переименовать", systemImage: "pencil") { showingRename = true }
                    }
                    HStack {
                        ProjectStateMenu(project: project)
                        Spacer()
                        QuarterTag(quarter: project.quarter)
                    }
                    DailyStatusesSection(projects: [project], day: $statusDay, showsProjectTitle: false)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Задачи").font(.title3.bold())
                            Spacer()
                            Text("\(project.doneTasks.count)/\(project.tasks.count) выполнено")
                                .foregroundStyle(.secondary)
                        }
                        TaskListSection(project: project, showDone: $showDone)
                    }
                    .padding(PulseMetrics.card)
                    .pulsePanel()
                    ArtifactLinksSection(project: project)
                }
                .padding(PulseMetrics.screen)
                .frame(maxWidth: PulseMetrics.contentWidth, alignment: .leading)
            }
            .sheet(isPresented: $showingRename) { RenameProjectView(project: project) }
            .projectContextMenu(project)
        } else {
            ContentUnavailableView("Проект недоступен", systemImage: "folder",
                                   description: Text("Выберите другой проект в боковой панели."))
        }
    }
}

struct RenameProjectView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var title: String
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    init(project: Project) {
        self.project = project
        _title = State(initialValue: project.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PulseMetrics.card) {
            Text("Переименовать проект").font(.title2.bold())
            TextField("Название проекта", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .disabled(isSaving)
            if let saveError { Text(saveError).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Сохранить") {
                    isSaving = true
                    Task {
                        if await store.renameProject(project, to: title) { dismiss() }
                        else { saveError = store.errorMessage ?? "Не удалось сохранить название." }
                        isSaving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.nilIfBlank == nil || isSaving)
            }
        }
        .padding(PulseMetrics.screen)
        .frame(width: 420)
        .onAppear { titleFocused = true }
        .interactiveDismissDisabled(isSaving)
    }
}
