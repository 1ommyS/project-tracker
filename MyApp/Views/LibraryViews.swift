import SwiftUI

struct ActivityView: View {
    @Environment(AppStore.self) private var store
    @State private var projectID: UUID?
    @State private var state: ProjectState?
    @State private var period = ActivityPeriod.all
    @State private var presentation = ActivityPresentation.summary

    enum ActivityPresentation: String, CaseIterable, Identifiable {
        case summary = "Сводка"
        case timeline = "Лента"
        var id: String { rawValue }
    }

    enum ActivityPeriod: String, CaseIterable, Identifiable {
        case week = "7 дней", month = "30 дней", all = "Всё время"
        var id: String { rawValue }
        var days: Int? { switch self { case .week: 7; case .month: 30; case .all: nil } }
    }

    private var items: [ActivityItem] {
        store.activity.filter { item in
            (projectID == nil || item.projectID == projectID) &&
            (state == nil || item.status.state == state) &&
            (period.days == nil || item.status.date >= Calendar.current.date(byAdding: .day, value: -(period.days ?? 0), to: .now)!)
        }
        .sorted {
            if Calendar.current.isDate($0.status.date, inSameDayAs: $1.status.date) {
                return $0.projectTitle.localizedCaseInsensitiveCompare($1.projectTitle) == .orderedAscending
            }
            return $0.status.date > $1.status.date
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { activityTitle; Spacer(); activityFilters }
                VStack(alignment: .leading, spacing: 14) {
                    activityTitle
                    activityFilters.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(18).pulsePanel(radius: 20).padding(20)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { presentationPicker; Spacer(); resultCount }
                VStack(alignment: .leading, spacing: 8) { presentationPicker; resultCount }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if items.isEmpty {
                EmptyState(symbol: "clock.badge.questionmark", title: "Нет обновлений", message: "Измените фильтры или добавьте ежедневный статус.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if presentation == .summary {
                GeometryReader { proxy in
                    if proxy.size.width >= 820 {
                        statusTable
                    } else {
                        compactSummary
                    }
                }
            } else {
                timeline
            }
        }
    }

    private var presentationPicker: some View {
        Picker("Вид", selection: $presentation) {
            ForEach(ActivityPresentation.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).frame(maxWidth: 280)
    }

    private var resultCount: some View {
        Text("\(items.count) обновлений · новые сверху")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var statusTable: some View {
        Table(items) {
            TableColumn("Проект") { item in
                Button { open(item) } label: {
                    FadeOverflowRow { Text(item.projectTitle).font(.callout.weight(.semibold)) }
                }
                .buttonStyle(.plain)
            }
            .width(min: 180, ideal: 250)

            TableColumn("Дата") { item in
                Text(item.status.date.formatted(date: .abbreviated, time: .omitted)).fixedSize()
            }
            .width(min: 90, ideal: 105, max: 125)

            TableColumn("Статус") { item in StateBadge(state: item.status.state) }
                .width(min: 110, ideal: 125, max: 150)

            TableColumn("Результат / план") { item in
                Text(summaryText(for: item)).lineLimit(2).foregroundStyle(.secondary)
            }
            .width(min: 180, ideal: 300)

            TableColumn("Блокер") { item in
                Text(item.status.blockers.nilIfBlank ?? "—")
                    .lineLimit(2)
                    .foregroundStyle(item.status.blockers.nilIfBlank == nil ? Color.secondary.opacity(0.55) : Color.red)
            }
            .width(min: 130, ideal: 220)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var compactSummary: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    Button { open(item) } label: { statusCard(item) }.buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .softScrollFade()
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    Button { open(item) } label: {
                        HStack(alignment: .top, spacing: 18) {
                            VStack { Circle().fill(item.status.state == .blocked ? Color.red : PulseStyle.blue).frame(width: 10, height: 10); Rectangle().fill(.quaternary).frame(width: 1, height: 90) }
                            VStack(alignment: .leading, spacing: 7) {
                                ViewThatFits(in: .horizontal) {
                                    HStack { activityName(item); Spacer(); activityDate(item) }
                                    VStack(alignment: .leading, spacing: 7) { activityName(item); activityDate(item) }
                                }
                                Text(summaryText(for: item)).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(20).frame(maxWidth: 900)
        }
        .softScrollFade()
    }

    private func statusCard(_ item: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FadeOverflowRow { Text(item.projectTitle).font(.headline) }
            HStack { activityDate(item); Spacer(); StateBadge(state: item.status.state) }
            Text(summaryText(for: item)).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
            if let blocker = item.status.blockers.nilIfBlank {
                Label(blocker, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.red).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).contentShape(Rectangle()).pulsePanel(radius: 14)
    }

    private func summaryText(for item: ActivityItem) -> String {
        item.status.completed.nilIfBlank ?? item.status.plans.nilIfBlank ?? item.status.notes.nilIfBlank ?? "Без краткого описания"
    }

    private func open(_ item: ActivityItem) {
        store.selectedProjectID = item.projectID
        store.destination = .projects
    }

    private func activityName(_ item: ActivityItem) -> some View {
        HStack(spacing: 8) {
            Text(item.projectTitle).font(.headline).lineLimit(2)
            StateBadge(state: item.status.state)
        }
    }

    private func activityDate(_ item: ActivityItem) -> some View {
        Text(item.status.date.formatted(date: .abbreviated, time: .omitted))
            .font(.caption).foregroundStyle(.secondary).fixedSize()
    }

    private var activityTitle: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(PulseStyle.indigo.opacity(0.13)).frame(width: 50, height: 50)
                Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundStyle(PulseStyle.indigo)
            }
            VStack(alignment: .leading, spacing: 3) { SectionEyebrow(text: "Хронология"); Text("Сводка статусов").font(.largeTitle.bold()).minimumScaleFactor(0.72).lineLimit(1); Text("Все проекты и даты в одном месте").foregroundStyle(.secondary) }
        }
    }

    private var activityFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                projectPicker.frame(width: 180); statePicker.frame(width: 170); periodPicker.frame(width: 130)
            }
            VStack(alignment: .leading, spacing: 8) { projectPicker; statePicker; periodPicker }
        }
    }

    private var projectPicker: some View { Picker("Проект", selection: $projectID) { Text("Все проекты").tag(UUID?.none); ForEach(store.projects) { Text($0.title).tag(Optional($0.id)) } } }
    private var statePicker: some View { Picker("Состояние", selection: $state) { Text("Все состояния").tag(ProjectState?.none); ForEach(ProjectState.allCases) { Text($0.title).tag(Optional($0)) } } }
    private var periodPicker: some View { Picker("Период", selection: $period) { ForEach(ActivityPeriod.allCases) { Text($0.rawValue).tag($0) } } }
}

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focused: Bool
    @State private var kind: SearchHit.Kind?
    private var hits: [SearchHit] { store.searchHits(query: store.searchQuery).filter { kind == nil || $0.kind == kind } }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack { RoundedRectangle(cornerRadius: 13).fill(PulseStyle.mint.opacity(0.13)).frame(width: 46, height: 46); Image(systemName: "sparkle.magnifyingglass").font(.title2).foregroundStyle(PulseStyle.mint) }
                    VStack(alignment: .leading, spacing: 2) { SectionEyebrow(text: "Быстрый доступ"); Text("Поиск").font(.largeTitle.bold()) }
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Проекты, статусы, заметки…", text: $store.searchQuery).textFieldStyle(.plain).font(.title3).focused($focused)
                    if !store.searchQuery.isEmpty { Button { store.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                }.padding(14).pulsePanel(radius: 14)
                Picker("Тип", selection: $kind) { Text("Всё").tag(SearchHit.Kind?.none); Text("Проекты").tag(Optional(SearchHit.Kind.project)); Text("Статусы").tag(Optional(SearchHit.Kind.status)); Text("Заметки").tag(Optional(SearchHit.Kind.note)) }.pickerStyle(.segmented).frame(maxWidth: 430)
            }.padding(20)
            Divider()
            if store.searchQuery.isEmpty {
                EmptyState(symbol: "text.magnifyingglass", title: "Найдите что угодно", message: "Поиск работает по названиям, тегам, задачам, заметкам и всей истории статусов, включая кириллицу.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hits.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Ничего не найдено", message: "Попробуйте изменить запрос или фильтр.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(hits) { hit in
                    Button {
                        store.selectedProjectID = hit.projectID; store.destination = .projects
                    } label: {
                        SearchResultRow(hit: hit, query: store.searchQuery)
                    }.buttonStyle(.plain)
                }.listStyle(.inset).scrollContentBackground(.hidden)
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
            Image(systemName: hit.kind == .project ? "square.stack.3d.up" : hit.kind == .status ? "calendar" : "note.text")
                .font(.title2).frame(width: 32).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack { title; Spacer(minLength: 12); date }
                    VStack(alignment: .leading, spacing: 4) { title; date }
                }
                HighlightedText(text: hit.excerpt, query: query).lineLimit(2)
            }
        }
        .padding(.vertical, 7).contentShape(Rectangle())
    }

    private var title: some View {
        HStack(spacing: 8) {
            Text(hit.title).font(.headline).lineLimit(2)
            Text(hit.kind.rawValue).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var date: some View {
        if let date = hit.date {
            Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary).fixedSize()
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
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 13).fill(Color.secondary.opacity(0.12)).frame(width: 46, height: 46); Image(systemName: "archivebox.fill").font(.title2).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 2) { SectionEyebrow(text: "Библиотека"); Text("Архив").font(.largeTitle.bold()) }
            }
            if store.archivedProjects.isEmpty {
                EmptyState(symbol: "archivebox", title: "Архив пуст", message: "Завершённые и архивированные проекты останутся доступны здесь.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.archivedProjects) { project in
                    ViewThatFits(in: .horizontal) {
                        HStack { archiveCopy(project); Spacer(); StateBadge(state: project.state); restoreButton(project) }
                        VStack(alignment: .leading, spacing: 8) {
                            archiveCopy(project)
                            HStack { StateBadge(state: project.state); Spacer(); restoreButton(project) }
                        }
                    }
                        .padding(.vertical, 6)
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
        }.padding(20)
    }

    private func archiveCopy(_ project: Project) -> some View {
        VStack(alignment: .leading) {
            Text(project.title).font(.headline).lineLimit(2)
            Text(project.summary).lineLimit(2).foregroundStyle(.secondary)
        }
    }

    private func restoreButton(_ project: Project) -> some View {
        Button("Восстановить") { Task { await store.restore(project) } }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                BrandIcon(size: 52)
                VStack(alignment: .leading, spacing: 3) { SectionEyebrow(text: "PROJECT Tracking"); Text("Настройки").font(.largeTitle.bold()); Text("Ваше пространство, ваши правила").foregroundStyle(.secondary) }
                Spacer()
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)
            Form {
                Section("Хранилище") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Рабочая папка").font(.caption).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack { vaultPath; chooseVaultButton }
                            VStack(alignment: .leading, spacing: 8) { vaultPath; chooseVaultButton }
                        }
                    }
                    Text("Данные остаются локальными. Можно выбрать корень существующего Obsidian Vault; PROJECT Tracking создаст внутри папку Projects.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Внешний вид") {
                    Picker("Тема", selection: $store.theme) { ForEach(AppTheme.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                }
                Section("Уведомления о задачах") {
                    LabeledContent("Статус") {
                        HStack {
                            Circle().fill(store.notifications.authorization == .allowed ? PulseStyle.mint : PulseStyle.amber).frame(width: 8, height: 8)
                            Text(store.notifications.authorization.title)
                        }
                    }
                    if store.notifications.authorization != .allowed {
                        Button("Разрешить уведомления", systemImage: "bell.badge") { Task { await store.notifications.requestAccess(); if store.notifications.authorization == .allowed { await store.notifications.sync(projects: store.projects) } } }
                    }
                    Text("Напоминания создаются локально для незавершённых задач с дедлайном и работают без интернета.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Шаблон ежедневного статуса") {
                    TextEditor(text: $store.statusTemplate).font(.system(.body, design: .monospaced)).frame(minHeight: 100)
                    Text("Шаблон хранится локально и служит памяткой для структуры обновлений.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Конфиденциальность") {
                    Label("Нет аккаунтов, аналитики, телеметрии и сетевой синхронизации", systemImage: "lock.shield.fill").foregroundStyle(PulseStyle.mint)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden).softScrollFade()
        }.navigationTitle("Настройки")
    }

    private var vaultPath: some View {
        FadeOverflowRow { Text(store.vaultURL.path).font(.callout) }
    }

    private var chooseVaultButton: some View {
        Button("Выбрать…") { Task { await store.chooseVault() } }
    }
}
