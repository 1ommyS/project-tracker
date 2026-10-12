import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var showingNewProject = false
    @State private var showingRecentProjects = false
    @State private var showingShortcutHelp = false
    @State private var statusProject: Project?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PulseSidebar()
        } detail: {
            ZStack {
                PageBackdrop()
                Group {
                    if store.isLoading { ProgressView("Читаю Markdown-хранилище…") }
                    else { destinationView }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 520)
        .toolbar {
            ToolbarItemGroup {
                Button { store.openSearch() } label: { Label("Поиск", systemImage: "magnifyingglass") }
                Button { showingNewProject = true } label: { Label("Новый проект", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                Button { showingShortcutHelp = true } label: { Label("Горячие клавиши", systemImage: "questionmark.circle") }
            }
        }
        .sheet(isPresented: $showingNewProject) { NewProjectView() }
        .sheet(isPresented: $showingRecentProjects) { RecentProjectsView() }
        .sheet(isPresented: $showingShortcutHelp) { ShortcutHelpView() }
        .sheet(item: $statusProject) { project in
            StatusEditorView(project: project) { status, advance in
                await store.saveStatus(status, projectID: project.id)
                let next = advance ? store.activeProjects.first(where: { !$0.isUpdatedToday() && $0.id != project.id }) : nil
                statusProject = nil
                if let next { Task { @MainActor in try? await Task.sleep(for: .milliseconds(180)); statusProject = next } }
            }
        }
        .alert("PROJECT Tracking", isPresented: .init(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: store.recentProjectsRequest) { _, _ in showingRecentProjects = true }
        .onChange(of: store.shortcutHelpRequest) { _, _ in showingShortcutHelp = true }
        .onChange(of: store.statusEditorRequest) { _, _ in
            statusProject = store.selectedProject.flatMap { $0.isArchived ? nil : $0 } ?? store.activeProjects.first
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch store.destination {
        case .today:
            TodayView(onUpdate: { statusProject = $0 }, onUpdateAll: { statusProject = store.activeProjects.first(where: { !$0.isUpdatedToday() }) })
        case .projects: ProjectsView(onUpdate: { statusProject = $0 })
        case .activity: ActivityView()
        case .search: SearchView()
        case .archive: ArchiveView()
        case .settings: SettingsView()
        }
    }
}

private struct RecentProjectsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var recentProjects: [Project] {
        Array(store.projects.sorted { $0.updatedAt > $1.updatedAt }.prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(PulseStyle.indigo.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundStyle(PulseStyle.indigo)
                }
                VStack(alignment: .leading, spacing: 2) {
                    SectionEyebrow(text: "⌘E · Быстрый переход")
                    Text("Недавние проекты").font(.title2.bold())
                }
                Spacer()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            if recentProjects.isEmpty {
                EmptyState(symbol: "clock", title: "Недавних проектов нет", message: "Созданные проекты появятся здесь в порядке последних изменений.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recentProjects) { project in
                            Button {
                                store.selectedProjectID = project.id
                                store.destination = .projects
                                dismiss()
                            } label: {
                                RecentProjectRow(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .softScrollFade()
            }
        }
        .frame(minWidth: 440, idealWidth: 650, maxWidth: 760, minHeight: 360, idealHeight: 520, maxHeight: 720)
    }
}

private struct RecentProjectRow: View {
    let project: Project

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 13) {
                projectIcon
                projectCopy
                Spacer(minLength: 10)
                StateBadge(state: project.state)
                updatedLabel
                chevron
            }
            HStack(alignment: .top, spacing: 12) {
                projectIcon
                VStack(alignment: .leading, spacing: 8) {
                    projectCopy
                    HStack { StateBadge(state: project.state); Spacer(); updatedLabel }
                }
                chevron.padding(.top, 7)
            }
        }
        .padding(12).contentShape(Rectangle()).pulsePanel(radius: 14)
    }

    private var projectIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(PulseStyle.blue.opacity(0.12)).frame(width: 40, height: 40)
            Image(systemName: project.state.symbol).foregroundStyle(PulseStyle.blue)
        }
    }

    private var projectCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title).font(.headline).lineLimit(2)
            FadeOverflowRow { Text(project.pathLabel).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var updatedLabel: some View {
        Text(project.updatedAt.formatted(.relative(presentation: .named)))
            .font(.caption).foregroundStyle(.tertiary).fixedSize()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
    }
}

private struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(keys: [String], title: String, detail: String)] = [
        (["⌘", "E"], "Недавние проекты", "Быстро открыть недавно изменённый проект, как Recent Files в IDEA."),
        (["⌘", "F"], "Найти", "Открыть общий поиск и сразу перейти к вводу запроса."),
        (["⌘", "N"], "Новый проект", "Создать новую часть проекта в выбранной иерархии."),
        (["⌘", "T"], "Новая задача", "Открыть текущий проект и поставить курсор в поле быстрой задачи."),
        (["⌘", "⇧", "↩"], "Обновить статус", "Открыть статус на сегодня для выбранного или первого активного проекта."),
        (["⌘", "1…4"], "Навигация", "Сегодня, Проекты, Активность и Архив — без мыши."),
        (["⌘", ","], "Настройки", "Открыть системное окно настроек PROJECT Tracking."),
        (["⌘", "K"], "Поиск", "Дополнительное сочетание для быстрого поиска.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                BrandIcon(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    SectionEyebrow(text: "PROJECT Tracking")
                    Text("Горячие клавиши").font(.title2.bold())
                }
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) {
                                shortcutKeys(shortcut.keys).frame(width: 118, alignment: .leading)
                                shortcutCopy(shortcut)
                                Spacer()
                            }
                            VStack(alignment: .leading, spacing: 9) {
                                shortcutKeys(shortcut.keys)
                                shortcutCopy(shortcut)
                            }
                        }
                        .padding(14).pulsePanel(radius: 14)
                    }
                }
                .padding(18)
            }
            .softScrollFade()

            Text("Подсказка: сочетания работают из любого основного экрана PROJECT Tracking.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 18)
        }
        .frame(minWidth: 440, idealWidth: 630, maxWidth: 760, minHeight: 460, idealHeight: 700, maxHeight: 820)
    }

    private func shortcutKeys(_ keys: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { key in
                Text(key).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(minWidth: 30, minHeight: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator.opacity(0.5)))
            }
        }
    }

    private func shortcutCopy(_ shortcut: (keys: [String], title: String, detail: String)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(shortcut.title).font(.headline)
            Text(shortcut.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PulseSidebar: View {
    @Environment(AppStore.self) private var store
    private let primary: [SidebarDestination] = [.today, .projects, .activity, .search]
    private let library: [SidebarDestination] = [.archive, .settings]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandIcon(size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text("PROJECT Tracking").font(.system(size: 19, weight: .bold, design: .rounded)).minimumScaleFactor(0.72).lineLimit(1)
                    Text("Project rhythm").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 22)

            SectionEyebrow(text: "Рабочее пространство").padding(.horizontal, 18).padding(.bottom, 7)
            VStack(spacing: 4) { ForEach(primary) { destination in sidebarButton(destination) } }

            SectionEyebrow(text: "Библиотека").padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 7)
            VStack(spacing: 4) { ForEach(library) { destination in sidebarButton(destination) } }

            Spacer()
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(PulseStyle.mint.opacity(0.14)).frame(width: 32, height: 32)
                    Image(systemName: "lock.shield.fill").foregroundStyle(PulseStyle.mint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Локально и приватно").font(.caption.weight(.semibold))
                    Text(store.vaultURL.lastPathComponent).lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12).pulsePanel(radius: 14).padding(10)
        }
        .frame(minWidth: 196, idealWidth: 218, maxWidth: 270)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(_ destination: SidebarDestination) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { store.destination = destination }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: destination.symbol).font(.system(size: 14, weight: .semibold)).frame(width: 23)
                    .foregroundStyle(store.destination == destination ? .white : iconColor(destination))
                Text(destination.title).font(.system(size: 13.5, weight: store.destination == destination ? .semibold : .medium))
                Spacer()
                if let badge = badge(for: destination), badge > 0 {
                    Text("\(badge)").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(store.destination == destination ? .white.opacity(0.2) : .secondary.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(store.destination == destination ? .white : .primary)
            .padding(.horizontal, 12).frame(height: 39)
            .background {
                if store.destination == destination {
                    LinearGradient(colors: [PulseStyle.blue, PulseStyle.indigo], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .shadow(color: PulseStyle.blue.opacity(0.25), radius: 9, y: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 9)
    }

    private func badge(for destination: SidebarDestination) -> Int? {
        switch destination {
        case .today: store.activeProjects.filter { !$0.isUpdatedToday() }.count
        case .projects: store.activeProjects.count
        case .archive: store.archivedProjects.count
        default: nil
        }
    }

    private func iconColor(_ destination: SidebarDestination) -> Color {
        switch destination {
        case .today: PulseStyle.amber
        case .projects: PulseStyle.blue
        case .activity: PulseStyle.indigo
        case .search: PulseStyle.mint
        case .archive: .secondary
        case .settings: .secondary
        }
    }
}

struct StateBadge: View {
    let state: ProjectState
    var body: some View {
        Label(state.title, systemImage: state.symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
    private var color: Color {
        switch state { case .active: PulseStyle.blue; case .blocked: .red; case .onHold: PulseStyle.amber; case .done: PulseStyle.mint; case .archived: .secondary; case .planned: PulseStyle.indigo }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(message)) }
}

#Preview { ContentView().environment(AppStore()) }
