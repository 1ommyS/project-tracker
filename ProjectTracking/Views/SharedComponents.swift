import SwiftUI

// MARK: - Цвет состояния (единый источник для всех экранов)

extension ProjectState {
    var color: Color {
        switch self {
        case .active: PulseStyle.blue
        case .blocked: .red
        case .onHold: PulseStyle.amber
        case .done: PulseStyle.mint
        case .planned: PulseStyle.indigo
        case .archived: .secondary
        }
    }

    /// Активное состояние следует за выбранной палитрой, остальные — семантические.
    func color(palette: AppPalette) -> Color {
        self == .active ? palette.color : color
    }
}

// MARK: - Русский формат дат

/// Приложение не локализовано как бандл, поэтому даты форматируем
/// с явной русской локалью — иначе форматы берутся из development region.
enum RuDate {
    private static let ru = Locale(identifier: "ru_RU")

    static func full(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        style.locale = ru
        return date.formatted(style)
    }

    static func dayMonthTime(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute()
        style.locale = ru
        return date.formatted(style)
    }

    static func dayMonthShort(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        style.locale = ru
        return date.formatted(style)
    }

    static func abbreviatedDateTime(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = ru
        return date.formatted(style)
    }

    static func timeOnly(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = ru
        return date.formatted(style)
    }

    static func relative(_ date: Date) -> String {
        let minutes = Int(date.distance(to: .now) / 60)
        switch minutes {
        case ..<1: return "только что"
        case ..<60: return "\(minutes) мин назад"
        case ..<1440: return "\(minutes / 60) ч назад"
        case ..<2880: return "вчера"
        default: return "\(minutes / 1440) дн назад"
        }
    }
}

// MARK: - Русская множественная форма

enum RuGrammar {
    static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}

// MARK: - Общие компоненты

struct StateBadge: View {
    @Environment(AppStore.self) private var store
    let state: ProjectState
    var body: some View {
        Label(state.title, systemImage: state.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(state.color(palette: store.palette))
    }
}

/// Интерактивный переключатель состояния проекта: выглядит как бейдж,
/// но открывает меню состояний и сохраняет выбор.
struct ProjectStateMenu: View {
    @Environment(AppStore.self) private var store
    let project: Project
    var minWidth: CGFloat = 148

    var body: some View {
        Picker("Состояние", selection: Binding(
            get: { project.state },
            set: { newState in
                Task { await store.setProjectState(project, to: newState) }
            }
        )) {
            ForEach(ProjectState.allCases.filter { $0 != .archived || project.state == .archived }) { state in
                Label(state.title, systemImage: state.symbol).tag(state)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(minWidth: minWidth, alignment: .leading)
        .help("Изменить состояние проекта")
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(message)) }
}

/// Метка квартала формата YYQN: «26Q4».
struct QuarterTag: View {
    let quarter: String
    var compact = false

    var body: some View {
        Text(quarter)
            .font(.system(size: compact ? 9.5 : 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 1 : 3)
            .background(.secondary.opacity(0.1), in: Capsule())
            .help("Квартал создания проекта")
    }
}

/// Заголовок группы-папки квартала: 📁 26Q4 · N проектов.
struct QuarterGroupLabel: View {
    let quarter: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tint)
            Text(quarter)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension Array where Element == Project {
    /// Группировка по кварталу создания: свежие кварталы сверху,
    /// внутри квартала проекты по свежести обновления.
    func groupedByQuarter() -> [(quarter: String, projects: [Project])] {
        Dictionary(grouping: self, by: \.quarter)
            .map { (quarter: $0.key, projects: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { $0.quarter > $1.quarter }
    }
}

/// Инлайн-редактирование срока задачи в духе Reminders: клик по бейджу
/// (или по колокольчику у задач без срока) открывает поповер с большим
/// графическим календарём, строкой времени и действиями.
/// Esc/клик мимо закрывают без применения, Return — «Готово».
struct InlineEditableDate: View {
    @Environment(AppStore.self) private var store
    let date: Date?
    var isDone = false
    let onCommit: (Date?) -> Void

    @State private var draft = Date.now
    @State private var isEditing = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let date {
                badge(text: text(for: date), systemImage: isDone ? "checkmark.circle" : "bell.fill",
                      color: color(for: date), tapDate: date)
            } else if isHovering {
                badge(text: "Срок", systemImage: "bell", color: .secondary, tapDate: defaultDraft)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
    }

    private func badge(text: String, systemImage: String, color: Color, tapDate: Date) -> some View {
        Button { start(from: tapDate) } label: {
            Label(text, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(color)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .help("Задать срок и напоминание")
            .popover(isPresented: $isEditing, arrowEdge: .bottom) { editor }
    }

    // Большой графический календарь + время, как в Reminders/Календаре.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("", selection: $draft, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            Divider()

            DatePicker("Время", selection: $draft, displayedComponents: [.hourAndMinute])
                .labelsHidden()

            Divider()

            HStack {
                if date != nil {
                    Button(role: .destructive) {
                        isEditing = false
                        onCommit(nil)
                    } label: {
                        Label("Убрать срок", systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Отмена") { isEditing = false }
                Button("Готово") {
                    isEditing = false
                    onCommit(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PulseMetrics.card)
        .frame(width: 300)
    }

    private func start(from date: Date) {
        draft = date
        isEditing = true
    }

    private var defaultDraft: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components) ?? .now
    }

    private func color(for date: Date) -> Color {
        if isDone { return .secondary }
        return date < .now ? .red : store.palette.color
    }

    private func text(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let isAllDay = components.hour == 23 && components.minute == 59
        if isAllDay {
            return Calendar.current.isDateInToday(date) ? "весь день" : "\(RuDate.dayMonthShort(date)) · весь день"
        }
        if Calendar.current.isDateInToday(date) {
            return RuDate.timeOnly(date)
        }
        return RuDate.dayMonthTime(date)
    }
}

// MARK: - Задачи

/// Строка задачи с явным открытием редактора и отдельным чекбоксом.
struct ContextTaskRow: View {
    @Environment(AppStore.self) private var store
    let context: TaskContext
    @State private var editor: TaskEditorContext?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                Task { await store.toggleTask(context.task, in: context.project) }
            } label: {
                Image(systemName: context.task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(context.task.isDone ? PulseStyle.mint : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(context.task.isDone ? "Вернуть задачу в работу" : "Выполнить задачу")

            VStack(alignment: .leading, spacing: 2) {
                Button(context.task.title) {
                    editor = TaskEditorContext(projectID: context.project.id, taskID: context.task.id)
                }
                .buttonStyle(.plain)
                .font(.body)
                Button {
                    store.openProject(context.project.id)
                } label: {
                    Label(context.project.title,
                          systemImage: "square.stack.3d.up")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            InlineEditableDate(date: context.task.dueDate, isDone: context.task.isDone) { newDate in
                Task { await store.setTaskDueDate(context.task, to: newDate, in: context.project) }
            }

            Button {
                editor = TaskEditorContext(projectID: context.project.id, taskID: context.task.id)
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Редактировать задачу")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .sheet(item: $editor) { context in TaskEditorView(context: context) }
        .taskContextMenu(task: context.task, project: context.project) {
            editor = TaskEditorContext(projectID: context.project.id, taskID: context.task.id)
        }
    }
}

/// Быстрый выбор срока с обычным размером системной кнопки.
struct DayChip: View {
    let title: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .foregroundStyle(isSelected ? accent : .primary)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
