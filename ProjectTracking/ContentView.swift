import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var showingNewProject = false
    @State private var showingRecentProjects = false
    @State private var showingShortcutHelp = false
    @State private var showingWhatsNew = false
    @State private var taskEditor: TaskEditorContext?
    @State private var columnVisibility: NavigationSplitViewVisibility =
        ProcessInfo.processInfo.environment["TRACE_COLLAP"] == "1" ? .detailOnly : .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PulseSidebar()
        } detail: {
            Group {
                if store.isLoading && store.projects.isEmpty {
                    ProgressView("Читаю Markdown-хранилище…")
                } else {
                    destinationView
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: store.destination)

        }
        .frame(minWidth: 680, minHeight: 520)
        .tint(store.palette.color)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.goBack() } label: { Label("Назад", systemImage: "chevron.backward") }
                    .labelStyle(.iconOnly)
                    .disabled(!store.canGoBack)
                    .help("Назад (⌘[)")
                Button { store.goForward() } label: { Label("Вперёд", systemImage: "chevron.forward") }
                    .labelStyle(.iconOnly)
                    .disabled(!store.canGoForward)
                    .help("Вперёд (⌘])")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup {
                if store.destination == .today || (store.destination == .projects && store.projectsPresentation == .feed) {
                    Picker("Вид", selection: Binding(
                        get: { store.interfaceMode },
                        set: { store.interfaceMode = $0 }
                    )) {
                        ForEach(InterfaceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help("Фокус — только срочное; Подробно — все детали")

                }

                OpenQuickStatusButton()
                    .labelStyle(.iconOnly)
                    .help("Быстрый статус (⌘⇧S)")
                Button { taskEditorForQuickTask() } label: { Label("Новая задача", systemImage: "plus.circle") }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("t", modifiers: .command)
                    .help("Новая задача (⌘T)")
                Button { showingNewProject = true } label: { Label("Новый проект", systemImage: "plus") }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Новый проект (⌘N)")
                Button { store.openRecentProjects() } label: { Label("Недавние проекты", systemImage: "clock") }
                    .labelStyle(.iconOnly)
                    .help("Недавние проекты (⌘E)")

                navigationMenu
            }
        }
        .sheet(isPresented: $showingNewProject) { NewProjectView() }
        .sheet(isPresented: $showingRecentProjects) { RecentProjectsView() }
        .sheet(isPresented: $showingShortcutHelp) { ShortcutHelpView() }
        .sheet(isPresented: $showingWhatsNew) { WhatsNewView() }
        .sheet(item: $taskEditor) { context in TaskEditorView(context: context) }
        .alert("Trace", isPresented: .init(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onAppear {
            store.openMainWindow = { openWindow(id: "main"); NSApp.activate() }
        }
        .onChange(of: store.recentProjectsRequest) { _, _ in showingRecentProjects = true }
        .onChange(of: store.shortcutHelpRequest) { _, _ in showingShortcutHelp = true }
        .onChange(of: store.whatsNewRequest) { _, _ in showingWhatsNew = true }
        .onChange(of: store.quickTaskRequest) { _, _ in taskEditorForQuickTask() }
    }

    private func taskEditorForQuickTask() {
        let target = store.quickTaskProjectID.flatMap { id in store.projects.first { $0.id == id && !$0.isCompleted } }
            ?? store.selectedProject.flatMap { $0.isArchived ? nil : $0 }
            ?? store.activeProjects.first
        guard let project = target else {
            store.errorMessage = "Сначала создайте проект, чтобы добавить задачу."
            return
        }
        store.quickTaskProjectID = nil
        taskEditor = TaskEditorContext(projectID: project.id, taskID: nil)
    }

    /// Нативное меню навигации: экраны с галочкой текущего и возврат панели.
    private var navigationMenu: some View {
        Menu {
            Picker("Экран", selection: Binding(
                get: { store.destination },
                set: { store.open($0) }
            )) {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbol).tag(destination)
                }
            }
            Divider()
            OpenQuickStatusButton()
            OpenStatusGuideButton()
            Divider()
            Button {
                columnVisibility = .all
            } label: {
                Label("Показать боковую панель", systemImage: "sidebar.left")
            }
        } label: {
            Label("Навигация", systemImage: "square.grid.2x2")
        }
        .help("Экраны и навигация (⌘1…⌘6)")
    }

    @ViewBuilder private var destinationView: some View {
        switch store.destination {
        case .today: TodayView()
        case .statuses: StatusesView()
        case .projects: ProjectsView()
        case .overdue: OverdueView()
        case .search: SearchView()
        case .archive: ArchiveView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Боковая панель (нативный список)

private struct PulseSidebar: View {
    @Environment(AppStore.self) private var store
    @State private var collapsedQuarters: Set<String> = []
    private let primary: [SidebarDestination] = [.today, .statuses, .projects, .overdue, .search]
    private let library: [SidebarDestination] = [.archive, .settings]

    private enum Selection: Hashable {
        case destination(SidebarDestination)
        case project(UUID)
    }

    private var selection: Binding<Selection?> {
        Binding(
            get: {
                if store.destination == .projects, store.projectsPresentation == .editor,
                   let id = store.selectedProjectID {
                    return .project(id)
                }
                return .destination(store.destination)
            },
            set: { selection in
                switch selection {
                case .destination(let destination): store.open(destination)
                case .project(let id): store.openProject(id)
                case nil: break
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Рабочее пространство") {
                ForEach(primary) { destination in
                    sidebarRow(destination).tag(Selection.destination(destination))
                }
            }

            if !store.activeProjects.isEmpty {
                Section("Проекты") {
                    ForEach(store.activeProjects.groupedByQuarter(), id: \.quarter) { group in
                        DisclosureGroup(isExpanded: quarterBinding(group.quarter)) {
                            ForEach(group.projects) { project in
                                SidebarProjectRow(project: project)
                                    .tag(Selection.project(project.id))
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

                }
            }

            Section("Библиотека") {
                ForEach(library) { destination in
                    sidebarRow(destination).tag(Selection.destination(destination))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
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
        case .statuses: nil
        case .projects: store.activeProjects.count
        case .overdue: store.overdueTasks.count
        case .archive: store.archivedProjects.count
        default: nil
        }
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

/// Выбор проекта принадлежит List: вся строка и клавиши стрелок открывают проект.
private struct SidebarProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        HStack {
            Label(project.title, systemImage: project.state.symbol)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !project.openTasks.isEmpty {
                Text("\(project.openTasks.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .help(project.title)
        .projectContextMenu(project)
    }
}

#Preview { ContentView().environment(AppStore()) }
