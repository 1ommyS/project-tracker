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
    let state: ProjectState
    var body: some View {
        Label(state.title, systemImage: state.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(state.color.opacity(0.12), in: Capsule())
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
