import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var showingNewProject = false
    @State private var showingRecentProjects = false
    @State private var showingShortcutHelp = false
    @State private var showingWhatsNew = false
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
        }
        .frame(minWidth: 680, minHeight: 520)
        .tint(store.palette.color)
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
                Picker("Вид", selection: Binding(
                    get: { store.interfaceMode },
                    set: { store.interfaceMode = $0 }
                )) {
                    ForEach(InterfaceMode.allCases) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Фокус — только срочное; Подробно — все детали")

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
        .onChange(of: store.recentProjectsRequest) { _, _ in showingRecentProjects = true }
        .onChange(of: store.shortcutHelpRequest) { _, _ in showingShortcutHelp = true }
        .onChange(of: store.whatsNewRequest) { _, _ in showingWhatsNew = true }
        .onChange(of: store.quickTaskRequest) { _, _ in taskEditorForQuickTask() }
    }

    private func taskEditorForQuickTask() {
        guard let project = store.selectedProject.flatMap({ $0.isArchived ? nil : $0 }) ?? store.activeProjects.first else {
            store.errorMessage = "Сначала создайте проект, чтобы добавить задачу."
            return
        }
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
            Button {
                columnVisibility = .all
            } label: {
                Label("Показать боковую панель", systemImage: "sidebar.left")
            }
        } label: {
            Label("Навигация", systemImage: "square.grid.2x2")
        }
        .help("Экраны и навигация (⌘1…⌘4)")
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
                                SidebarProjectRow(project: project)
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
        case .projects: store.activeProjects.count
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

/// Строка проекта в сайдбаре: системный hover и выделение,
/// клик по названию — инлайн-переименование.
private struct SidebarProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var isHovering = false

    private var isSelected: Bool {
        store.destination == .projects && store.projectsPresentation == .editor && store.selectedProjectID == project.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.state.symbol)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(project.state.color(palette: store.palette))
            InlineEditableText(font: .system(size: 13, weight: isSelected ? .medium : .regular),
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
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary)
            } else if isHovering {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quinary)
            }
        }
        .onTapGesture { store.openProject(project.id) }
        .onHover { isHovering = $0 }
    }
}

#Preview { ContentView().environment(AppStore()) }
