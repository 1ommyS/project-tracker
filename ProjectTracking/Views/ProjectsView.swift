import SwiftUI

struct ProjectsView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var stateFilter: ProjectState?
    @State private var quarterFilter: String?

    /// Динамический список кварталов, реально присутствующих у активных проектов.
    private var quarters: [String] {
        Array(Set(store.activeProjects.map(\.quarter))).sorted(by: >)
    }

    private var filtered: [Project] {
        var result = query.isEmpty ? store.activeProjects : store.activeProjects.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
        if let stateFilter { result = result.filter { $0.state == stateFilter } }
        if let quarterFilter { result = result.filter { $0.quarter == quarterFilter } }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var openTaskCount: Int { store.allOpenTasks.count }

    var body: some View {
        VStack(spacing: 0) {
            if store.projectsPresentation == .feed {
                header
                Divider()
            }
            ZStack {
                switch store.projectsPresentation {
                case .feed: feed.transition(.opacity)
                case .editor: editor.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: store.projectsPresentation)
        }
        .navigationTitle(store.projectsPresentation == .editor ? store.selectedProject?.title ?? "Проект" : "Проекты")
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Все проекты по кварталам")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                Text("\(store.activeProjects.count) \(RuGrammar.plural(store.activeProjects.count, one: "проект", few: "проекта", many: "проектов")) · \(openTaskCount) \(RuGrammar.plural(openTaskCount, one: "открытая задача", few: "открытые задачи", many: "открытых задач"))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            headerControls
        }
        .padding(.horizontal, PulseMetrics.screen)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .pageWidth()
    }

    private var headerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { filters; searchField }
            VStack(alignment: .leading, spacing: 12) { filters; searchField }
        }
    }

    private var filters: some View {
        HStack {
            Picker("Состояние", selection: $stateFilter) {
                Text("Все").tag(ProjectState?.none)
                ForEach(ProjectState.allCases.filter { $0 != .archived }) { state in
                    Text(state.title).tag(Optional(state))
                }
            }
            .pickerStyle(.menu)
            Picker("Квартал", selection: $quarterFilter) {
                Text("Все кварталы").tag(String?.none)
                ForEach(quarters, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .pickerStyle(.menu)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск по проектам и задачам", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Label("Очистить поиск", systemImage: "xmark.circle.fill") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Лента

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if filtered.isEmpty {
                    EmptyState(symbol: store.activeProjects.isEmpty ? "square.stack.3d.up.slash" : "line.3.horizontal.decrease.circle",
                               title: store.activeProjects.isEmpty ? "Нет активных проектов" : "Ничего не найдено",
                               message: store.activeProjects.isEmpty ? "Создайте проект кнопкой + в панели инструментов." : "Измените запрос или фильтр состояния.")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ForEach(filtered.groupedByQuarter(), id: \.quarter) { group in
                        LazyVStack(alignment: .leading, spacing: store.interfaceMode == .focused ? 2 : 10) {
                            QuarterGroupLabel(quarter: group.quarter, count: group.projects.count)
                                .padding(.horizontal, 4)
                            switch store.interfaceMode {
                            case .detailed:
                                ForEach(group.projects) { project in
                                    ProjectFeedCard(project: project)
                                }
                            case .focused:
                                ForEach(group.projects) { project in
                                    FocusedProjectRow(project: project)
                                }
                            }
                        }
                        .padding(.top, 4)
                        .animation(.snappy, value: store.interfaceMode)
                    }
                }
            }
            .padding(.horizontal, PulseMetrics.screen)
            .padding(.bottom, PulseMetrics.screen)
            .frame(maxWidth: PulseMetrics.contentWidth, alignment: .leading)
        }
        .softScrollFade()
    }

    // MARK: - Редактор

    @ViewBuilder
    private var editor: some View {
        if let project = store.selectedProject {
            ProjectDetailView(projectId: project.id).id(project.id)
        } else {
            ContentUnavailableView("Выберите проект", systemImage: "sidebar.left",
                                   description: Text("Откройте проект в боковой панели или в списке проектов."))
        }
    }
}

// MARK: - Компактная строка проекта (фокусный вид)

private struct FocusedProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        HStack {
            Button { store.openProject(project.id) } label: {
                HStack {
                    Label(project.title, systemImage: project.state.symbol)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("\(project.openTasks.count)").foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ProjectStateMenu(project: project, minWidth: 0)
        }
        .padding(.horizontal, PulseMetrics.card)
        .projectContextMenu(project)
    }
}

// MARK: - Карточка проекта в ленте

struct ProjectFeedCard: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var showDone = false
    @State private var deleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: project.state.symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(project.state.color(palette: store.palette))
                    .frame(width: 26)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button(project.title) { store.openProject(project.id) }
                            .font(.title3.bold())
                            .buttonStyle(.plain)
                            .help("Открыть проект")
                        QuarterTag(quarter: project.quarter)
                        Spacer(minLength: 8)
                        ProjectStateMenu(project: project, minWidth: 0)
                    }

                }
                Spacer(minLength: 8)
                Menu {
                    Button("Открыть проект", systemImage: "square.and.pencil") { store.openProject(project.id) }
                    Button("Архивировать", systemImage: "archivebox") { Task { await store.archive(project) } }
                    Divider()
                    Button("Удалить", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if !project.tasks.isEmpty {
                HStack(spacing: 10) {
                    ProgressView(value: project.taskProgress)
                        .tint(PulseStyle.mint)
                        .animation(.snappy, value: project.taskProgress)
                    Text("\(project.doneTasks.count)/\(project.tasks.count) выполнено")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
                }
            }

            Divider()

            TaskListSection(project: project, showDone: $showDone)
        }
        .padding(PulseMetrics.card)
        .pulsePanel(radius: 12)
        .projectContextMenu(project)
        .confirmationDialog("Удалить «\(project.title)»?", isPresented: $deleteConfirmation) {
            Button("Переместить в Корзину", role: .destructive) { Task { await store.delete(project) } }
        } message: { Text("Папка проекта будет перемещена в системную Корзину и сможет быть восстановлена.") }
    }
}

// MARK: - Новый проект

struct NewProjectView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Новый проект").font(.title2.bold())
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
                Button("Создать") {
                    isSaving = true
                    Task {
                        let created = await store.createProject(
                            title: title, epic: "", parentProject: "", summary: "", tags: [], state: .active
                        )
                        isSaving = false
                        if created != nil { dismiss() }
                        else { saveError = store.errorMessage ?? "Не удалось создать проект." }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.nilIfBlank == nil || isSaving)
            }
        }
        .padding(PulseMetrics.screen)
        .frame(width: 420)
        .onAppear { titleFocused = true }
        .interactiveDismissDisabled(isSaving)
    }
}
