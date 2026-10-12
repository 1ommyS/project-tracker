import SwiftUI

struct ProjectsView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var stateFilter: ProjectState?
    @State private var quarterFilter: String?
    @State private var showingNewProject = false

    /// Динамический список кварталов, реально присутствующих у активных проектов.
    private var quarters: [String] {
        Array(Set(store.activeProjects.map(\.quarter))).sorted(by: >)
    }

    private var filtered: [Project] {
        var result = query.isEmpty ? store.activeProjects : store.activeProjects.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
        if let stateFilter { result = result.filter { $0.state == stateFilter } }
        if let quarterFilter { result = result.filter { $0.quarter == quarterFilter } }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var openTaskCount: Int { store.activeProjects.reduce(0) { $0 + $1.openTasks.count } }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {                switch store.projectsPresentation {
                case .feed: feed.transition(.opacity)
                case .editor: editor.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: store.projectsPresentation)
        }
        .sheet(isPresented: $showingNewProject) { NewProjectView() }
        .navigationTitle("Проекты")
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(store.projectsPresentation == .feed ? "Все проекты по кварталам" : "Редактор")
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
        @Bindable var store = store
        return HStack(spacing: 10) {
            Picker("Вид", selection: $store.projectsPresentation) {
                Text(ProjectsPresentation.feed.title).tag(ProjectsPresentation.feed)
                Text(ProjectsPresentation.editor.title).tag(ProjectsPresentation.editor)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Picker("Состояние", selection: $stateFilter) {
                Text("Все").tag(ProjectState?.none)
                ForEach(ProjectState.allCases.filter { $0 != .archived }) { state in
                    Text(state.title).tag(Optional(state))
                }
            }
            .pickerStyle(.menu)

            if !quarters.isEmpty {
                Picker("Квартал", selection: $quarterFilter) {
                    Text("Все кварталы").tag(String?.none)
                    ForEach(quarters, id: \.self) { quarter in
                        Text(quarter).tag(String?.some(quarter))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск по проектам и задачам", text: $query)
                    .textFieldStyle(.plain)
                    .arrowCursorOnExit()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 280)
        }
    }

    // MARK: - Лента

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if filtered.isEmpty {
                    EmptyState(symbol: store.activeProjects.isEmpty ? "square.stack.3d.up.slash" : "line.3.horizontal.decrease.circle",
                               title: store.activeProjects.isEmpty ? "Нет активных проектов" : "Ничего не найдено",
                               message: store.activeProjects.isEmpty ? "Создайте проект кнопкой + в панели инструментов." : "Измените запрос или фильтр состояния.")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ForEach(filtered.groupedByQuarter(), id: \.quarter) { group in
                        VStack(alignment: .leading, spacing: store.interfaceMode == .focused ? 2 : 10) {
                            QuarterGroupLabel(quarter: group.quarter, count: group.projects.count)
                                .padding(.horizontal, 4)
                            switch store.interfaceMode {
                            case .detailed:
                                ForEach(group.projects) { project in
                                    ProjectFeedCard(project: project)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            case .focused:
                                ForEach(group.projects) { project in
                                    FocusedProjectRow(project: project)
                                        .transition(.opacity)
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
            .animation(.snappy, value: filtered.map(\.id))
        }
        .softScrollFade()
    }

    // MARK: - Редактор

    private var editor: some View {
        HSplitView {
            ProjectListPane(projects: filtered)
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
                .background(.ultraThinMaterial)

            if let project = store.selectedProject, project.state.isActive, !project.isArchived {
                ProjectDetailView(projectId: project.id)
                    .frame(minWidth: 420)
            } else {
                VStack(spacing: 14) {
                    EmptyState(symbol: "sidebar.right",
                               title: filtered.isEmpty ? "Нет проектов" : "Выберите проект",
                               message: filtered.isEmpty ? "Создайте проект — и он появится в редакторе." : "Слева выберите проект, чтобы править его поля и задачи прямо на месте.")
                    if filtered.isEmpty {
                        Button("Новый проект", systemImage: "plus") { showingNewProject = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

// MARK: - Список проектов в редакторе

private struct ProjectListPane: View {
    @Environment(AppStore.self) private var store
    let projects: [Project]
    @State private var expandedQuarters: Set<String> = []
    @State private var didInitializeExpansion = false

    /// Кварталы сверху вниз, внутри — стабильный алфавитный порядок:
    /// навигатор не должен прыгать при автосохранении.
    private var groups: [(quarter: String, projects: [Project])] {
        projects.groupedByQuarter().map { group in
            (group.quarter, group.projects.sorted {
                $0.pathLabel.localizedCaseInsensitiveCompare($1.pathLabel) == .orderedAscending
            })
        }
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedProjectID) {
            ForEach(groups, id: \.quarter) { group in
                DisclosureGroup(isExpanded: quarterBinding(group.quarter)) {
                    ForEach(group.projects) { project in
                        ProjectListRow(project: project)
                            .tag(project.id)
                            .padding(.vertical, 3)
                    }
                } label: {
                    QuarterGroupLabel(quarter: group.quarter, count: group.projects.count)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if projects.isEmpty {
                EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "Ничего не найдено",
                           message: "Измените запрос или фильтр состояния вверху.")
            }
        }
        .onAppear(perform: initializeExpansion)
    }

    /// По умолчанию развёрнут только самый свежий квартал.
    private func initializeExpansion() {
        guard !didInitializeExpansion, let newest = groups.first?.quarter else { return }
        didInitializeExpansion = true
        expandedQuarters = [newest]
    }

    private func quarterBinding(_ quarter: String) -> Binding<Bool> {
        Binding(
            get: { expandedQuarters.contains(quarter) },
            set: { isExpanded in
                if isExpanded {
                    expandedQuarters.insert(quarter)
                } else {
                    expandedQuarters.remove(quarter)
                }
            }
        )
    }
}

struct ProjectListRow: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: project.state.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(project.state.color(palette: store.palette))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                InlineEditableText(font: .headline,
                                   placeholder: "Название проекта",
                                   text: project.title) { newTitle in
                    Task { await store.renameProject(project, to: newTitle) }
                }
                HStack(spacing: 5) {
                    QuarterTag(quarter: project.quarter, compact: true)
                    if project.breadcrumb.count > 1 {
                        Text([project.epic, project.parentProject].compactMap(\.nilIfBlank).joined(separator: " › "))
                            .font(.caption2.weight(.medium)).foregroundStyle(.tint).lineLimit(1)
                    }
                }
                HStack(spacing: 7) {
                    if !project.tasks.isEmpty {
                        ProgressView(value: project.taskProgress).tint(PulseStyle.mint).frame(maxWidth: 60)
                        Text("\(project.doneTasks.count)/\(project.tasks.count)")
                    }
                    Spacer(minLength: 4)
                    Text(RuDate.relative(project.updatedAt))
                }.font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Компактная строка проекта (фокусный вид)

private struct FocusedProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: project.state.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(project.state.color(palette: store.palette))
                .frame(width: 20)
            InlineEditableText(font: .body.weight(.medium),
                               placeholder: "Название проекта",
                               text: project.title) { newTitle in
                Task { await store.renameProject(project, to: newTitle) }
            }
            QuarterTag(quarter: project.quarter, compact: true)
            Spacer(minLength: 8)
            if !project.openTasks.isEmpty {
                Label("\(project.openTasks.count)", systemImage: "circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProjectStateMenu(project: project, minWidth: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quinary)
            }
        }
        .onTapGesture { store.openProject(project.id) }
        .onHover { isHovering = $0 }
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
                        InlineEditableText(font: .title3.bold(),
                                           placeholder: "Название проекта",
                                           text: project.title) { newTitle in
                            Task { await store.renameProject(project, to: newTitle) }
                        }
                        QuarterTag(quarter: project.quarter)
                        Spacer(minLength: 8)
                        ProjectStateMenu(project: project, minWidth: 0)
                    }
                    if project.breadcrumb.count > 1 {
                        FadeOverflowRow { Text(project.pathLabel).font(.caption.weight(.medium)).foregroundStyle(.tint) }
                    }
                    if let summary = project.summary.nilIfBlank {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !project.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(project.tags, id: \.self) { tag in
                                Text("#\(tag)").font(.caption2.weight(.medium)).foregroundStyle(.tint)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.tint.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Открыть в редакторе", systemImage: "square.and.pencil") { store.openProject(project.id) }
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
                    if title.nilIfBlank != nil {
                        LabeledContent("Путь") {
                            Text([epic, parentProject, title].compactMap(\.nilIfBlank).joined(separator: " › "))
                                .foregroundStyle(PulseStyle.blue)
                        }
                    }
                }
                TextField("Короткое описание", text: $summary, axis: .vertical).lineLimit(3...6)
                TextField("Теги через запятую", text: $tags)
                Picker("Состояние", selection: $state) {
                    ForEach(ProjectState.allCases.filter { $0 != .archived }) { Text($0.title).tag($0) }
                }
            }
            .formStyle(.grouped)
            .arrowCursorOnExit()
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Создать") {
                    Task {
                        _ = await store.createProject(
                            title: title, epic: epic, parentProject: parentProject, summary: summary,
                            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                            state: state
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.nilIfBlank == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 580, maxWidth: 700, minHeight: 440, idealHeight: 540, maxHeight: 760)
    }
}
