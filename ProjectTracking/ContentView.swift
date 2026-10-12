import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var showingNewProject = false
    @State private var showingRecentProjects = false
    @State private var showingShortcutHelp = false
    @State private var taskEditor: TaskEditorContext?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PulseSidebar()
        } detail: {
            Group {
                if store.isLoading {
                    ProgressView("Читаю Markdown-хранилище…")
                } else {
                    destinationView
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: store.destination)
            .overlay(alignment: .topLeading) {
                if columnVisibility == .detailOnly {
                    MiniNavMap { columnVisibility = .all }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25), value: columnVisibility)
        }
        .frame(minWidth: 680, minHeight: 520)
        .toolbar {
            ToolbarItemGroup {
                Button { store.goBack() } label: { Label("Назад", systemImage: "chevron.backward") }
                    .disabled(!store.canGoBack)
                    .help("Назад (⌘[)")
                Button { store.goForward() } label: { Label("Вперёд", systemImage: "chevron.forward") }
                    .disabled(!store.canGoForward)
                    .help("Вперёд (⌘])")
                Divider()
                Button { taskEditorForQuickTask() } label: { Label("Новая задача", systemImage: "plus.circle") }
                    .keyboardShortcut("t", modifiers: .command)
                Button { showingNewProject = true } label: { Label("Новый проект", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                Button { store.openRecentProjects() } label: { Label("Недавние", systemImage: "clock") }
                Button { showingShortcutHelp = true } label: { Label("Горячие клавиши", systemImage: "questionmark.circle") }
            }
        }
        .sheet(isPresented: $showingNewProject) { NewProjectView() }
        .sheet(isPresented: $showingRecentProjects) { RecentProjectsView() }
        .sheet(isPresented: $showingShortcutHelp) { ShortcutHelpView() }
        .sheet(item: $taskEditor) { context in TaskEditorView(context: context) }
        .alert("Trace", isPresented: .init(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: store.recentProjectsRequest) { _, _ in showingRecentProjects = true }
        .onChange(of: store.shortcutHelpRequest) { _, _ in showingShortcutHelp = true }
        .onChange(of: store.quickTaskRequest) { _, _ in taskEditorForQuickTask() }
    }

    private func taskEditorForQuickTask() {
        guard let project = store.selectedProject.flatMap({ $0.isArchived ? nil : $0 }) ?? store.activeProjects.first else {
            store.errorMessage = "Сначала создайте проект, чтобы добавить задачу."
            return
        }
        taskEditor = TaskEditorContext(projectID: project.id, taskID: nil)
    }

    @ViewBuilder private var destinationView: some View {
        switch store.destination {
        case .today: TodayView()
        case .projects: ProjectsView()
        case .search: SearchView()
        case .archive: ArchiveView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Мини-панель навигации (когда сайдбар свёрнут)

private struct MiniNavMap: View {
    @Environment(AppStore.self) private var store
    let onShowSidebar: () -> Void
    private let destinations: [SidebarDestination] = [.today, .projects, .search, .archive]

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            VStack(spacing: 4) {
                Button(action: onShowSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .help("Показать боковую панель")

                ForEach(destinations) { destination in
                    destinationButton(destination)
                }
            }
            .padding(6)
        }
        .padding(.leading, 12)
        .padding(.top, 10)
    }

    private func destinationButton(_ destination: SidebarDestination) -> some View {
        let isSelected = store.destination == destination
        return Button {
            store.open(destination)
        } label: {
            Image(systemName: destination.symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .overlay(alignment: .topTrailing) {
                    if destination == .today, store.urgentTaskCount > 0 {
                        Circle().fill(.red).frame(width: 6, height: 6).offset(x: 2, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .tint(isSelected ? .accentColor : .secondary)
        .help(destination.title)
    }
}

// MARK: - Боковая панель (нативный список)

private struct PulseSidebar: View {
    @Environment(AppStore.self) private var store
    @State private var collapsedQuarters: Set<String> = []
    private let primary: [SidebarDestination] = [.today, .projects, .search]
    private let library: [SidebarDestination] = [.archive, .settings]

    private var selection: Binding<SidebarDestination?> {
        Binding(
            get: { store.destination },
            set: { destination in
                if let destination { store.open(destination) }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Рабочее пространство") {
                ForEach(primary) { destination in
                    sidebarRow(destination).tag(destination)
                }
            }

            if !store.activeProjects.isEmpty {
                Section("Проекты") {
                    ForEach(store.activeProjects.groupedByQuarter(), id: \.quarter) { group in
                        DisclosureGroup(isExpanded: quarterBinding(group.quarter)) {
                            ForEach(group.projects) { project in
                                sidebarProjectRow(project)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.tint)
                                Text(group.quarter)
                                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                Spacer(minLength: 0)
                                Text("\(group.projects.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Button {
                        store.openProjectsList()
                    } label: {
                        Label("Все проекты", systemImage: "rectangle.stack")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Библиотека") {
                ForEach(library) { destination in
                    sidebarRow(destination).tag(destination)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(_ destination: SidebarDestination) -> some View {
        HStack(spacing: 6) {
            Label(destination.title, systemImage: destination.symbol)
            Spacer(minLength: 0)
            if let badge = badge(for: destination), badge > 0 {
                Text("\(badge)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }

    private func badge(for destination: SidebarDestination) -> Int? {
        switch destination {
        case .today: store.urgentTaskCount
        case .projects: store.activeProjects.count
        case .archive: store.archivedProjects.count
        default: nil
        }
    }

    private func sidebarProjectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: project.state.symbol)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(project.state.color)
            InlineEditableText(font: .system(size: 13, weight: isProjectSelected(project) ? .medium : .regular),
                               tooltip: "Клик — переименовать, по строке — открыть",
                               placeholder: "Проект",
                               text: project.title) { newTitle in
                Task { await store.renameProject(project, to: newTitle) }
            }
            Spacer(minLength: 0)
            if !project.openTasks.isEmpty {
                Text("\(project.openTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .background {
            if isProjectSelected(project) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary)
            }
        }
        .onTapGesture { store.openProject(project.id) }
    }

    private func isProjectSelected(_ project: Project) -> Bool {
        store.destination == .projects && store.projectsPresentation == .editor && store.selectedProjectID == project.id
    }

    private func quarterBinding(_ quarter: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedQuarters.contains(quarter) },
            set: { isExpanded in
                if isExpanded {
                    collapsedQuarters.remove(quarter)
                } else {
                    collapsedQuarters.insert(quarter)
                }
            }
        )
    }
}

#Preview { ContentView().environment(AppStore()) }
