import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focused: Bool
    @State private var kind: SearchHit.Kind?
    private var hits: [SearchHit] { store.searchHits(query: store.searchQuery).filter { kind == nil || $0.kind == kind } }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Проекты, задачи, теги…", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .arrowCursorOnExit()
                    if !store.searchQuery.isEmpty {
                        Button { store.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .pulsePanel(radius: 12)
                Picker("Тип", selection: $kind) {
                    Text("Всё").tag(SearchHit.Kind?.none)
                    Text("Проекты").tag(Optional(SearchHit.Kind.project))
                    Text("Задачи").tag(Optional(SearchHit.Kind.task))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 430)
            }
            .padding(PulseMetrics.screen)
            .navigationTitle("Поиск")
            Divider()
            if store.searchQuery.isEmpty {
                EmptyState(symbol: "text.magnifyingglass", title: "Найдите что угодно",
                           message: "Поиск работает по названиям проектов, описаниям, тегам и задачам, включая кириллицу.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hits.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Ничего не найдено",
                           message: "Попробуйте изменить запрос или фильтр.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(hits) { hit in
                    Button {
                        store.openProject(hit.projectID)
                    } label: {
                        SearchResultRow(hit: hit, query: store.searchQuery)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear { focused = true }
        .onChange(of: store.searchFocusRequest) { _, _ in focused = true }
    }
}

private struct SearchResultRow: View {
    let hit: SearchHit
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: hit.kind == .project ? "square.stack.3d.up" : "checkmark.circle")
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack { title; Spacer(minLength: 12); date }
                    VStack(alignment: .leading, spacing: 4) { title; date }
                }
                HighlightedText(text: hit.excerpt, query: query).lineLimit(2)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .pointingHandOnHover()
    }

    private var title: some View {
        HStack(spacing: 8) {
            Text(hit.title).font(.headline).lineLimit(2)
            Text(hit.kind.rawValue).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var date: some View {
        if let date = hit.date {
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

private struct HighlightedText: View {
    let text: String, query: String
    var body: some View { Text(attributed).foregroundStyle(.secondary) }
    private var attributed: AttributedString {
        var value = AttributedString(text)
        var searchStart = value.startIndex
        while searchStart < value.endIndex, let range = value[searchStart...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            value[range].backgroundColor = .yellow.opacity(0.35)
            value[range].foregroundColor = .primary
            searchStart = range.upperBound
        }
        return value
    }
}

struct ArchiveView: View {
    @Environment(AppStore.self) private var store
    @State private var expandedQuarters: Set<String> = []
    @State private var didInitializeExpansion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Завершённые проекты по кварталам")
                .font(.headline)
                .foregroundStyle(.secondary)
            if store.archivedProjects.isEmpty {
                EmptyState(symbol: "archivebox", title: "Архив пуст",
                           message: "Завершённые и архивированные проекты останутся доступны здесь.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.archivedProjects.groupedByQuarter(), id: \.quarter) { group in
                        DisclosureGroup(isExpanded: quarterBinding(group.quarter)) {
                            ForEach(group.projects) { project in
                                archiveRow(project)
                            }
                        } label: {
                            QuarterGroupLabel(quarter: group.quarter, count: group.projects.count)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .onAppear(perform: initializeExpansion)
            }
        }
        .padding(PulseMetrics.screen)
        .navigationTitle("Архив")
    }

    /// По умолчанию развёрнут только самый свежий квартал.
    private func initializeExpansion() {
        guard !didInitializeExpansion,
              let newest = store.archivedProjects.groupedByQuarter().first?.quarter else { return }
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

    private func archiveRow(_ project: Project) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                archiveCopy(project)
                Spacer()
                StateBadge(state: project.state)
                restoreButton(project)
            }
            VStack(alignment: .leading, spacing: 8) {
                archiveCopy(project)
                HStack {
                    StateBadge(state: project.state)
                    Spacer()
                    restoreButton(project)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func archiveCopy(_ project: Project) -> some View {
        VStack(alignment: .leading) {
            InlineEditableText(font: .headline,
                               lineLimit: 2,
                               placeholder: "Проект",
                               text: project.title) { newTitle in
                Task { await store.renameProject(project, to: newTitle) }
            }
            Text(project.summary).lineLimit(2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                QuarterTag(quarter: project.quarter, compact: true)
                if !project.tasks.isEmpty {
                    Text("\(project.doneTasks.count)/\(project.tasks.count) задач выполнено")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func restoreButton(_ project: Project) -> some View {
        Button("Восстановить") { Task { await store.restore(project) } }
            .buttonStyle(.glass)
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Form {
                Section("Хранилище") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Рабочая папка").font(.caption).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack { vaultPath; chooseVaultButton }
                            VStack(alignment: .leading, spacing: 8) { vaultPath; chooseVaultButton }
                        }
                    }
                    Text("Данные остаются локальными. Можно выбрать корень существующего Obsidian Vault; Trace создаст внутри папку Projects.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Внешний вид") {
                    Picker("Тема", selection: $store.theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Уведомления о задачах") {
                    LabeledContent("Статус") {
                        HStack {
                            Circle()
                                .fill(store.notifications.authorization == .allowed ? PulseStyle.mint : PulseStyle.amber)
                                .frame(width: 8, height: 8)
                            Text(store.notifications.authorization.title)
                        }
                    }
                    if store.notifications.authorization == .allowed {
                        Button("Отправить тестовое напоминание", systemImage: "bell.badge") {
                            Task { await store.notifications.sendTestNotification() }
                        }
                        .buttonStyle(.glass)
                        Button("Перепланировать напоминания", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await store.notifications.sync(projects: store.projects) }
                        }
                        .buttonStyle(.glass)
                    } else if store.notifications.authorization != .denied {
                        Button("Разрешить уведомления", systemImage: "bell.badge") {
                            Task {
                                await store.notifications.requestAccess()
                                await store.notifications.syncIfAllowed(projects: store.projects)
                            }
                        }
                        .buttonStyle(.glass)
                    }
                    if let message = store.notifications.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Напоминание приходит в срок задачи. Нажатие открывает проект, а кнопка «Выполнено» прямо в уведомлении закрывает задачу. Всё локально и без интернета.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Конфиденциальность") {
                    Label("Нет аккаунтов, аналитики, телеметрии и сетевой синхронизации", systemImage: "lock.shield.fill")
                        .foregroundStyle(PulseStyle.mint)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .softScrollFade()
        }
        .navigationTitle("Настройки")
    }

    private var vaultPath: some View {
        FadeOverflowRow { Text(store.vaultURL.path).font(.callout) }
    }

    private var chooseVaultButton: some View {
        Button("Выбрать…") { Task { await store.chooseVault() } }.buttonStyle(.glass)
    }
}
