import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    let onUpdate: (Project) -> Void
    let onUpdateAll: () -> Void

    private var pending: [Project] { store.activeProjects.filter { !$0.isUpdatedToday() } }
    private var groupedProjects: [(String, [Project])] {
        Dictionary(grouping: store.activeProjects, by: { $0.epic.nilIfBlank ?? "Без эпика" })
            .map { ($0.key, $0.value.sorted { $0.pathLabel < $1.pathLabel }) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TodayHero(total: store.activeProjects.count, completed: store.activeProjects.count - pending.count,
                          pending: pending.count, onUpdateAll: onUpdateAll)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    MetricCard(value: "\(store.activeProjects.count)", label: "активных", symbol: "square.stack.3d.up", tint: .blue)
                    MetricCard(value: "\(store.activeProjects.count - pending.count)", label: "обновлено", symbol: "checkmark.circle", tint: .green)
                    MetricCard(value: "\(pending.count)", label: "ждут статуса", symbol: "clock", tint: pending.isEmpty ? .green : .orange)
                }

                if store.activeProjects.isEmpty {
                    EmptyState(symbol: "square.stack.3d.up.slash", title: "Нет активных проектов", message: "Создайте проект кнопкой + в панели инструментов.")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                SectionEyebrow(text: "Фокус на сегодня")
                                Text("Активные проекты").font(.title2.bold())
                            }
                            Spacer()
                            Text("\(store.activeProjects.count) всего").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                        ForEach(groupedProjects, id: \.0) { epic, projects in
                            HStack(spacing: 7) {
                                Image(systemName: "square.3.layers.3d.top.filled").foregroundStyle(PulseStyle.indigo)
                                Text(epic).font(.subheadline.bold())
                                Text("\(projects.count)").font(.caption2.bold()).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2).background(.secondary.opacity(0.1), in: Capsule())
                            }.padding(.top, 8)
                            ForEach(projects) { project in TodayProjectCard(project: project, onUpdate: { onUpdate(project) }) }
                        }
                    }
                }
            }
            .padding(28).frame(maxWidth: 1050, alignment: .leading)
        }
        .softScrollFade()
    }
}

private struct TodayHero: View {
    let total: Int, completed: Int, pending: Int
    let onUpdateAll: () -> Void
    private var progress: Double { total == 0 ? 1 : Double(completed) / Double(total) }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        default: "Добрый вечер"
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 26) {
                heroCopy
                Spacer(minLength: 20)
                progressRing
            }
            VStack(alignment: .leading, spacing: 18) {
                heroCopy
                HStack { Spacer(); progressRing; Spacer() }
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [PulseStyle.blue.opacity(0.13), PulseStyle.indigo.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .pulsePanel(radius: 24)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            Text(greeting).font(.system(size: 34, weight: .bold, design: .rounded)).minimumScaleFactor(0.75)
            Text(pending == 0 ? "Все проекты обновлены. Можно спокойно двигаться дальше." : "Соберите ритм дня — осталось обновить \(pending) \(projectWord(pending)).")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if pending > 0 {
                Button("Начать ежедневный обзор", systemImage: "arrow.right.circle.fill", action: onUpdateAll)
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 5)
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.12), lineWidth: 10)
            Circle().trim(from: 0, to: progress).stroke(
                AngularGradient(colors: [PulseStyle.blue, PulseStyle.mint, PulseStyle.blue], center: .center),
                style: StrokeStyle(lineWidth: 10, lineCap: .round)
            ).rotationEffect(.degrees(-90)).animation(.spring, value: progress)
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))%").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("готово").font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(width: 108, height: 108).padding(.trailing, 6)
    }

    private func projectWord(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "проект" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "проекта" }
        return "проектов"
    }
}

private struct MetricCard: View {
    let value: String, label: String, symbol: String
    let tint: Color
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint).frame(width: 35, height: 35)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title2.bold())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(16).frame(maxWidth: .infinity)
        .pulsePanel(radius: 16)
    }
}

private struct TodayProjectCard: View {
    let project: Project
    let onUpdate: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                statusMarker
                projectCopy
                Spacer(minLength: 12)
                statusButton
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) { statusMarker; projectCopy }
                statusButton.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(18).pulsePanel(radius: 18)
        .animation(.snappy, value: project.isUpdatedToday())
        .contextMenu { Button("Обновить статус", action: onUpdate) }
    }

    private var statusMarker: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(project.isUpdatedToday() ? PulseStyle.mint : PulseStyle.amber).frame(width: 4, height: 58)
            Image(systemName: project.isUpdatedToday() ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2).foregroundStyle(project.isUpdatedToday() ? PulseStyle.mint : PulseStyle.amber)
        }
    }

    private var projectCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(project.title).font(.headline); StateBadge(state: project.state) }
                VStack(alignment: .leading, spacing: 5) { Text(project.title).font(.headline); StateBadge(state: project.state) }
            }
            if project.breadcrumb.count > 1 {
                FadeOverflowRow { Text(project.pathLabel).font(.caption.weight(.medium)).foregroundStyle(PulseStyle.blue) }
            }
            if let status = project.latestStatus {
                Text(status.completed.nilIfBlank ?? status.plans.nilIfBlank ?? "Статус без текста").lineLimit(2).foregroundStyle(.secondary)
                if let blocker = status.blockers.nilIfBlank { Label(blocker, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.medium)).foregroundStyle(.red).lineLimit(2) }
                Text("Обновлено \(status.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.tertiary)
            } else { Text("Статусов ещё нет").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var statusButton: some View {
        if project.isUpdatedToday() { Button("Изменить", action: onUpdate).buttonStyle(.bordered) }
        else { Button("Добавить статус", action: onUpdate).buttonStyle(.borderedProminent) }
    }
}

struct StatusEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let onSave: (DailyStatus, Bool) async -> Void
    @State private var date = Date.now
    @State private var state: ProjectState
    @State private var completed = ""
    @State private var plans = ""
    @State private var blockers = ""
    @State private var notes = ""
    @State private var editingID = UUID()
    @State private var createdAt = Date.now
    @State private var fileURL: URL?
    @State private var saving = false

    init(project: Project, initialDate: Date = .now, onSave: @escaping (DailyStatus, Bool) async -> Void) {
        self.project = project
        self.onSave = onSave
        _date = State(initialValue: initialDate)
        _state = State(initialValue: project.state)
        if let existing = project.statuses.first(where: { Calendar.current.isDate($0.date, inSameDayAs: initialDate) }) {
            _date = State(initialValue: existing.date); _state = State(initialValue: existing.state)
            _completed = State(initialValue: existing.completed); _plans = State(initialValue: existing.plans)
            _blockers = State(initialValue: existing.blockers); _notes = State(initialValue: existing.notes)
            _editingID = State(initialValue: existing.id); _createdAt = State(initialValue: existing.createdAt)
            _fileURL = State(initialValue: existing.fileURL)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Статус на \(date.formatted(date: .abbreviated, time: .omitted))").font(.title2.bold())
                    Text(project.pathLabel).font(.subheadline.weight(.medium)).foregroundStyle(PulseStyle.blue)
                }
                Spacer(); StateBadge(state: state)
            }.padding(22)
            Divider()
            Form {
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            statusDateSelector
                            statePicker.frame(maxWidth: 230)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            statusDateSelector
                            statePicker
                        }
                    }
                }
                StatusField(title: "Выполнено", hint: "Что изменилось и какой результат получен?", text: $completed)
                StatusField(title: "Планы", hint: "Следующие конкретные шаги", text: $plans)
                StatusField(title: "Блокеры", hint: "Что мешает двигаться дальше?", text: $blockers, tint: .red)
                StatusField(title: "Заметки", hint: "Markdown, [[WikiLinks]], #теги", text: $notes)
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить") { save(advance: false) }.keyboardShortcut(.defaultAction).disabled(saving || !hasContent)
                Button("Сохранить и дальше") { save(advance: true) }.buttonStyle(.borderedProminent).disabled(saving || !hasContent)
            }.padding(18)
        }
        .frame(minWidth: 500, idealWidth: 680, maxWidth: 760, minHeight: 520, idealHeight: 680, maxHeight: 820)
        .onAppear {
            if project.statuses.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) == nil,
               completed.isEmpty, plans.isEmpty, blockers.isEmpty, notes.isEmpty {
                notes = store.statusTemplate
            }
        }
        .onChange(of: date) { _, newDate in loadStatus(for: newDate) }
    }

    private var statePicker: some View {
        Picker("Состояние", selection: $state) {
            ForEach(ProjectState.allCases.filter { $0 != .archived }) { Text($0.title).tag($0) }
        }
    }

    private var statusDateSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Дата статуса").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Button { shiftDate(by: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Предыдущий день")
                quickDateButton("Вчера", date: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
                quickDateButton("Сегодня", date: .now)
                DatePicker("Выбрать дату", selection: $date, displayedComponents: .date)
                    .labelsHidden().help("Выбрать дату в календаре")
                Button { shiftDate(by: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Следующий день")
            }
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.caption.weight(.medium)).foregroundStyle(PulseStyle.blue)
        }
    }

    @ViewBuilder
    private func quickDateButton(_ title: String, date target: Date) -> some View {
        if Calendar.current.isDate(date, inSameDayAs: target) {
            Button(title) { date = Calendar.current.startOfDay(for: target) }.buttonStyle(.borderedProminent)
        } else {
            Button(title) { date = Calendar.current.startOfDay(for: target) }.buttonStyle(.bordered)
        }
    }

    private func shiftDate(by days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    private var hasContent: Bool { completed.nilIfBlank != nil || plans.nilIfBlank != nil || blockers.nilIfBlank != nil || notes.nilIfBlank != nil }
    private func loadStatus(for selectedDate: Date) {
        if let existing = project.statuses.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            editingID = existing.id; state = existing.state; completed = existing.completed; plans = existing.plans
            blockers = existing.blockers; notes = existing.notes; createdAt = existing.createdAt; fileURL = existing.fileURL
        } else {
            editingID = UUID(); state = project.state; completed = ""; plans = ""; blockers = ""
            notes = store.statusTemplate; createdAt = .now; fileURL = nil
        }
    }
    private func save(advance: Bool) {
        saving = true
        let value = DailyStatus(id: editingID, projectID: project.id, projectTitle: project.title, date: date, state: state,
                                completed: completed, plans: plans, blockers: blockers, notes: notes,
                                createdAt: createdAt, updatedAt: .now, fileURL: fileURL)
        Task { await onSave(value, advance); dismiss() }
    }
}

private struct StatusField: View {
    let title: String, hint: String
    @Binding var text: String
    var tint: Color? = nil
    var body: some View {
        LabeledContent(title) {
            TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).padding(8)
                .frame(minHeight: 70).background((tint ?? .secondary).opacity(tint == nil ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke((tint ?? .clear).opacity(text.isEmpty ? 0.15 : 0.35), lineWidth: 1) }
                .overlay(alignment: .topLeading) { if text.isEmpty { Text(hint).foregroundStyle(.tertiary).padding(13).allowsHitTesting(false) } }
        }
    }
}
