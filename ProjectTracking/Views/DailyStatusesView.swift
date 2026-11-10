import SwiftUI

/// Один выбранный день, полноразмерные записи без горизонтальной прокрутки.
/// Дата редактора фиксируется при открытии листа и не зависит от выбора на экране.
struct DailyStatusesSection: View {
    @Environment(AppStore.self) private var store
    let projects: [Project]
    @Binding var day: Date
    var showsProjectTitle = true
    @State private var editing: StatusEditorContext?

    var body: some View {
        VStack(alignment: .leading, spacing: PulseMetrics.card) {
            Text("Статусы по дням").font(.title2.bold())
            ViewThatFits(in: .horizontal) {
                HStack { datePicker; Spacer(); dayButtons }
                VStack(alignment: .leading, spacing: 12) { datePicker; dayButtons }
            }
            if projects.isEmpty {
                Text("Создайте проект, чтобы вести дневные статусы.").foregroundStyle(.secondary)
            }
            ForEach(projects.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { project in
                StatusDayCard(project: project, day: day, showsProjectTitle: showsProjectTitle) {
                    editing = StatusEditorContext(projectID: project.id, day: day)
                }
            }
        }
        .sheet(item: $editing) { context in
            DailyStatusEditor(context: context)
        }
    }

    private var datePicker: some View {
        DatePicker("Дата", selection: $day, displayedComponents: .date)
            .fixedSize()
    }

    private var dayButtons: some View {
        HStack {
            Button { moveDay(-1) } label: { Label("Предыдущий день", systemImage: "chevron.left") }
                .labelStyle(.iconOnly)
                .help("Предыдущий день")
            Button("Сегодня") { day = .now }
            Button { moveDay(1) } label: { Label("Следующий день", systemImage: "chevron.right") }
                .labelStyle(.iconOnly)
                .help("Следующий день")
        }
        .controlSize(.large)
    }

    private func moveDay(_ offset: Int) {
        day = Calendar.current.date(byAdding: .day, value: offset, to: day) ?? day
    }
}

struct StatusDayCard: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let day: Date
    let showsProjectTitle: Bool
    let onEdit: () -> Void

    var body: some View {
        let entry = project.dailyStatus(on: day)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if showsProjectTitle {
                    Button(project.title) { store.openProject(project.id) }.font(.headline).buttonStyle(.plain)
                } else { Text(RuDate.full(day)).font(.headline) }
                Spacer()
                Button(entry == nil ? "Добавить статус" : "Редактировать", systemImage: "square.and.pencil", action: onEdit)
            }
            if let entry {
                if !entry.status.isEmpty { MarkdownPreview(text: entry.status).equatable() }
                ForEach(entry.tasks) { task in
                    Toggle(task.title, isOn: Binding(get: { task.isDone }, set: { _ in
                        Task { await store.toggleStatusTask(task, in: entry, for: project) }
                    }))
                    .toggleStyle(.checkbox).strikethrough(task.isDone)
                }
                if !entry.blockers.isEmpty {
                    Label("Блокеры", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange)
                    MarkdownPreview(text: entry.blockers).equatable()
                }
                if entry.editableMarkdown.isEmpty && entry.blockers.isEmpty {
                    Text("Статус за этот день пуст").foregroundStyle(.secondary)
                }
            } else { Text("За этот день пока нет записи").foregroundStyle(.secondary) }
        }
        .font(.body).frame(maxWidth: .infinity, alignment: .leading)
        .padding(PulseMetrics.card).pulsePanel().projectContextMenu(project)
    }
}

struct StatusEditorContext: Identifiable {
    let projectID: UUID
    let day: Date
    var id: String { "\(projectID)-\(day.timeIntervalSince1970)" }
}

struct DailyStatusEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let context: StatusEditorContext
    @State private var status = ""
    @State private var field = 0
    @State private var blockers = ""
    @State private var hydrated = false
    @State private var isSaving = false
    @State private var saveError: String?

    private var project: Project? { store.projects.first { $0.id == context.projectID } }

    var body: some View {
        VStack(alignment: .leading, spacing: PulseMetrics.card) {
            Text(project?.title ?? "Проект недоступен").font(.title2.bold())
            Text(RuDate.full(context.day)).foregroundStyle(.secondary)
            Picker("Раздел записи", selection: $field) {
                Text("Статус").tag(0)
                Text("Блокеры").tag(1)
            }
            .pickerStyle(.segmented)
            GeometryReader { geometry in
                ZStack {
                    MarkdownEditor(text: $status, placeholder: "Что сделано и что дальше…",
                                   minHeight: max(100, geometry.size.height - 110), autofocus: true, isActive: field == 0)
                        .opacity(field == 0 ? 1 : 0).allowsHitTesting(field == 0).accessibilityHidden(field != 0)
                    MarkdownEditor(text: $blockers, placeholder: "Что мешает двигаться дальше",
                                   minHeight: max(100, geometry.size.height - 110), autofocus: true, isActive: field == 1)
                        .opacity(field == 1 ? 1 : 0).allowsHitTesting(field == 1).accessibilityHidden(field != 1)
                }
            }
            Text(saveError ?? " ")
                .foregroundStyle(.red)
                .lineLimit(2)
                .frame(height: 36, alignment: .topLeading)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isSaving ? "Сохранение…" : "Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(project == nil)
            }
            .disabled(isSaving)
        }
        .padding(PulseMetrics.screen)
        .frame(width: 660, height: 680)
        .interactiveDismissDisabled()
        .onAppear {
            guard !hydrated else { return }
            hydrated = true
            let entry = project?.dailyStatus(on: context.day)
            status = entry?.editableMarkdown ?? ""
            blockers = entry?.blockers ?? ""
        }
        .disabled(isSaving)
    }

    private func save() {
        guard let project else { return }
        isSaving = true
        Task {
            let saved = await store.setDailyStatus(text: status, blockers: blockers, for: project,
                                                  on: context.day, replacesTasks: true)
            isSaving = false
            if saved { dismiss() } else { saveError = store.errorMessage ?? "Не удалось сохранить статус." }
        }
    }
}
