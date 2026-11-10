import SwiftUI

private enum StatusesPresentation: String {
    case table, list
}

struct StatusesView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("statusesPresentation") private var presentation = StatusesPresentation.table
    @AppStorage("statusesDayCount") private var dayCount = 3
    @State private var day = Date.now
    @State private var query = ""
    @State private var filter = StatusRowsFilter.all
    @State private var selectedID: UUID?
    @State private var editing: StatusEditorContext?
    @State private var isPreparing = true
    @State private var snapshot = StatusTableSnapshot(projects: [], endingOn: .now, dayCount: 3)

    private struct SnapshotKey: Equatable { let revision: Int; let day: Date; let count: Int }
    var body: some View {
        let visibleRows = snapshot.filtered(query: query, filter: filter, selectedDayOnly: presentation == .list)
        VStack(spacing: 0) {
            controls
                .padding(.vertical, PulseMetrics.card)
            Divider()
            if store.activeProjects.isEmpty {
                ContentUnavailableView("Нет активных проектов", systemImage: "tablecells",
                                       description: Text("Создайте проект, чтобы вести статусы по дням."))
            } else if isPreparing && snapshot.rows.isEmpty {
                ProgressView("Готовлю статусы…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleRows.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                switch presentation {
                case .table: table(rows: visibleRows)
                case .list:
                    ScrollView {
                        LazyVStack(spacing: PulseMetrics.card) {
                            ForEach(visibleRows) { row in
                                StatusDayCard(project: row.project, day: snapshot.selectedDay, showsProjectTitle: true) {
                                    editing = StatusEditorContext(projectID: row.id, day: snapshot.selectedDay)
                                }
                            }
                        }
                        .padding(.vertical, PulseMetrics.screen)
                    }
                }
            }
            Divider()
            HStack {
                Text("\(visibleRows.count) из \(snapshot.rows.count) проектов")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation == .table ? "Ячейка — открыть запись · колонки можно расширять" : "Полный текст за выбранный день")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: PulseMetrics.contentWidth)
        .padding(.horizontal, PulseMetrics.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Статусы")
        .sheet(item: $editing) { DailyStatusEditor(context: $0) }
        .task(id: SnapshotKey(revision: store.projectsRevision, day: Calendar.current.startOfDay(for: day), count: dayCount)) {
            isPreparing = true
            let projects = store.activeProjects
            let end = day, count = dayCount
            let prepared = await Task.detached(priority: .userInitiated) {
                StatusTableSnapshot(projects: projects, endingOn: end, dayCount: count)
            }.value
            guard !Task.isCancelled else { return }
            snapshot = prepared
            isPreparing = false
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { presentationPicker; Spacer(); dateControls }
                VStack(alignment: .leading, spacing: 12) { presentationPicker; dateControls }
            }
            ViewThatFits(in: .horizontal) {
                HStack { searchField; filterPicker; rangePicker }
                VStack(alignment: .leading, spacing: 12) {
                    searchField
                    ViewThatFits(in: .horizontal) {
                        HStack { filterPicker; rangePicker }
                        VStack(alignment: .leading, spacing: 12) { filterPicker; rangePicker }
                    }
                }
            }
        }
    }

    private var presentationPicker: some View {
        Picker("Вид статусов", selection: $presentation) {
            Text("Таблица").tag(StatusesPresentation.table)
            Text("Список").tag(StatusesPresentation.list)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 190)
    }

    private var dateControls: some View {
        HStack {
            Button { shiftDay(-1) } label: { Label("Предыдущий день", systemImage: "chevron.left") }
                .labelStyle(.iconOnly).help("Предыдущий день")
            DatePicker("Дата", selection: $day, displayedComponents: .date).labelsHidden().fixedSize()
            Button { shiftDay(1) } label: { Label("Следующий день", systemImage: "chevron.right") }
                .labelStyle(.iconOnly).help("Следующий день")
            Button("Сегодня") { day = .now }
        }
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск по проектам и статусам", text: $query).textFieldStyle(.plain)
            Button { query = "" } label: { Label("Очистить поиск", systemImage: "xmark.circle.fill") }
                .labelStyle(.iconOnly).buttonStyle(.plain).disabled(query.isEmpty)
        }
        .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private var filterPicker: some View {
        Picker("Показать", selection: $filter) {
            ForEach(StatusRowsFilter.allCases) { Text($0.title).tag($0) }
        }.fixedSize()
    }
    private var rangePicker: some View {
        Picker("Период", selection: $dayCount) {
            Text("3 дня").tag(3); Text("5 дней").tag(5); Text("7 дней").tag(7)
        }
        .fixedSize().disabled(presentation == .list)
    }

    private func table(rows: [StatusTableRow]) -> some View {
        Table(rows, selection: $selectedID) {
            TableColumn("Проект") { row in
                Button { store.openProject(row.id) } label: {
                    Label(row.project.title, systemImage: row.project.state.symbol)
                        .font(.body.weight(.semibold)).lineLimit(2)
                }
                .buttonStyle(.plain).help(row.project.title)
            }
            .width(min: 150, ideal: 200, max: 320)
            TableColumnForEach(snapshot.days, id: \.self) { date in
                TableColumn(RuDate.dayMonthShort(date) + (Calendar.current.isDateInToday(date) ? " · сегодня" : "")) { row in
                    StatusTableCellView(cell: row.cells[date] ?? StatusTableCell(entry: nil)) {
                        editing = StatusEditorContext(projectID: row.id, day: date)
                    }
                }
                .width(min: 180, ideal: 250, max: 500)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .onKeyPress(.return) {
            guard let id = selectedID else { return .ignored }
            editing = StatusEditorContext(projectID: id, day: snapshot.selectedDay)
            return .handled
        }
    }

    private func shiftDay(_ offset: Int) {
        day = Calendar.current.date(byAdding: .day, value: offset, to: day) ?? day
    }
}

private struct StatusTableCellView: View {
    let cell: StatusTableCell
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                Text(cell.summary.isEmpty ? (cell.entry == nil ? "Добавить статус…" : "Нет текста статуса") : cell.summary)
                    .font(.body).lineLimit(3).multilineTextAlignment(.leading)
                    .foregroundStyle(cell.summary.isEmpty ? .secondary : .primary)
                if let blockers = cell.entry?.blockers.nilIfBlank {
                    Label(String(blockers.prefix(180)), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).lineLimit(1)
                }
                if let entry = cell.entry, !entry.tasks.isEmpty {
                    Text("Чекбоксы: \(entry.tasks.filter(\.isDone).count)/\(entry.tasks.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .help("Открыть полный текст и редактирование")
        .contextMenu {
            Button("Открыть запись…", action: onOpen)
            if let entry = cell.entry {
                Button("Копировать запись") {
                    Clipboard.copy("## Статус\n" + entry.editableMarkdown + "\n\n## Блокеры\n" + entry.blockers)
                }
            }
        }
        .accessibilityLabel(cell.entry == nil ? "Добавить статус" : "Открыть статус: \(cell.summary)")
    }
}
