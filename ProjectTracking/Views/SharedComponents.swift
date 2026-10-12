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
                var value = project
                value.state = newState
                Task { await store.saveProject(value) }
            }
        )) {
            ForEach(ProjectState.allCases.filter { $0 != .archived }) { state in
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
            .map { (quarter: $0.key, projects: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.quarter > $1.quarter }
    }
}

/// Инлайн-редактирование срока задачи. Клик по бейджу (или по колокольчику,
/// появляющемуся при наведении у задач без срока) разворачивает компактный
/// DatePicker: галочка — применить, крестик — отмена, корзина — убрать срок.
struct InlineEditableDate: View {
    @Environment(AppStore.self) private var store
    let date: Date?
    var isDone = false
    let onCommit: (Date?) -> Void

    @State private var isEditing = false
    @State private var draft = Date.now
    @State private var isHovering = false

    var body: some View {
        Group {
            if isEditing {
                editor
                    .transition(.opacity)
            } else {
                display
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isEditing)
    }

    // MARK: Просмотр

    private var display: some View {
        HStack(spacing: 6) {
            if let date {
                Label(text(for: date), systemImage: isDone ? "checkmark.circle" : "bell.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color(for: date))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background {
                        if isHovering {
                            Capsule().fill(.quinary)
                        } else {
                            Capsule().fill(color(for: date).opacity(0.09))
                        }
                    }
                    .onTapGesture { start(from: date) }
                    .help("Клик — изменить срок")
            } else if isHovering {
                Label("Срок", systemImage: "bell")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.quinary))
                    .onTapGesture { start(from: defaultDraft) }
                    .transition(.opacity.combined(with: .scale))
                    .help("Задать срок и напоминание")
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
    }

    // MARK: Правка

    private var editor: some View {
        HStack(spacing: 6) {
            DatePicker("", selection: $draft, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            Button {
                isEditing = false
                onCommit(draft)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .help("Применить (Return не нужен — нажмите галочку)")
            Button {
                isEditing = false
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Отмена (Esc)")
            if date != nil {
                Button {
                    isEditing = false
                    onCommit(nil)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Убрать срок")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
        .onKeyPress(.escape) {
            isEditing = false
            return .handled
        }
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
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

// MARK: - Инлайн-редактирование текста

/// Клик по тексту превращает его в поле ввода. Return или клик мимо — сохраняет,
/// Esc — отменяет, пустой ввод откатывается к прежнему значению.
/// Аффорданс: при наведении появляется плашка и карандаш, в правке — поле с рамкой.
/// Курсор-стрелка остаётся обычным: I-beam включается только внутри поля,
/// иначе текст выглядит «выделяемым», а не редактируемым.
struct InlineEditableText: View {
    var font: Font = .headline
    var color: Color = .primary
    var strikethrough = false
    var lineLimit: Int? = 1
    var tooltip: String = "Клик — переименовать"
    var pencilSize: CGFloat = 10
    let placeholder: String
    let text: String
    let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                editor
                    .transition(.opacity)
            } else {
                display
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isEditing)
    }

    // Режим правки: явное поле с подложкой и акцентной рамкой.
    private var editor: some View {
        TextField(placeholder, text: $draft, axis: lineLimit == nil ? .vertical : .horizontal)
            .font(font)
            .foregroundStyle(color)
            .textFieldStyle(.plain)
            .focused($focused)
            .lineLimit(lineLimit ?? 4)
            .onSubmit(finish)
            .onKeyPress(.escape) {
                cancel()
                return .handled
            }
            .onChange(of: focused) { _, hasFocus in
                if !hasFocus { finish() }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(PulseStyle.blue, lineWidth: 1))
            .arrowCursorOnExit()
    }

    // Режим просмотра: наведение подсвечивает плашку и показывает карандаш,
    // место под карандаш зарезервировано — вёрстка не двигается.
    private var display: some View {
        HStack(spacing: 4) {
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .foregroundStyle(text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
                .strikethrough(strikethrough)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "pencil")
                .font(.system(size: pencilSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(isHovering && !text.isEmpty ? 1 : 0)
        }
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
            }
        }
        .onTapGesture { start() }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(tooltip)
        .contentShape(Rectangle())
    }

    private func start() {
        draft = text
        isEditing = true
        focused = true
    }

    private func finish() {
        guard isEditing else { return }
        isEditing = false
        if let value = draft.nilIfBlank, value != text {
            onCommit(value)
        }
    }

    private func cancel() {
        isEditing = false
    }
}
