import SwiftUI

/// Дашборд просроченных задач: всё, что пропущено по срокам,
/// сгруппировано по проектам, самые старые — сверху.
struct OverdueView: View {
    @Environment(AppStore.self) private var store

    private var groups: [(project: Project, tasks: [ProjectTask])] {
        var byProject: [UUID: (Project, [ProjectTask])] = [:]
        for context in store.overdueTasks {
            if let existing = byProject[context.project.id] {
                byProject[context.project.id] = (existing.0, existing.1 + [context.task])
            } else {
                byProject[context.project.id] = (context.project, [context.task])
            }
        }
        return byProject.values
            .map { (project: $0.0, tasks: $0.1.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }) }
            .sorted { oldest($0.tasks) < oldest($1.tasks) }
    }

    private func oldest(_ tasks: [ProjectTask]) -> Date {
        tasks.compactMap(\.dueDate).min() ?? .distantFuture
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                EmptyState(symbol: "checkmark.seal.fill",
                           title: "Просроченных задач нет",
                           message: "Все задачи в срок. Если дедлайн пройдёт — задача появится здесь.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summary
                        ForEach(groups, id: \.project.id) { group in
                            groupView(group.project, tasks: group.tasks)
                        }
                    }
                    .padding(PulseMetrics.screen)
                    .frame(maxWidth: PulseMetrics.contentWidth, alignment: .leading)
                }
                .softScrollFade()
            }
        }
        .navigationTitle("Просрочено")
    }

    private var summary: some View {
        let taskCount = store.overdueTasks.count
        let worst = worstOverdueDays
        return HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.red)
            Text("\(taskCount) \(RuGrammar.plural(taskCount, one: "просроченная задача", few: "просроченные задачи", many: "просроченных задач")) в \(groups.count) \(RuGrammar.plural(groups.count, one: "проекте", few: "проектах", many: "проектах"))")
                .font(.headline)
            Spacer()
            if worst > 0 {
                Text("самая старая — \(worst) \(RuGrammar.plural(worst, one: "день", few: "дня", many: "дней")) назад")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func groupView(_ project: Project, tasks: [ProjectTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                store.openProject(project.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: project.state.symbol)
                        .font(.body.weight(.medium))
                        .foregroundStyle(project.state.color(palette: store.palette))
                        .frame(width: 20)
                    Text(project.title)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    QuarterTag(quarter: project.quarter, compact: true)
                    Spacer()
                    Text("\(tasks.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .help("Открыть проект в редакторе")

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tasks) { task in
                    overdueRow(task, in: project)
                }
            }
            .padding(PulseMetrics.card)
            .pulsePanel(radius: 12)
            .animation(.snappy, value: tasks.map(\.id))
        }
    }

    private func overdueRow(_ task: ProjectTask, in project: Project) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                Task { await store.toggleTask(task, in: project) }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                InlineEditableText(font: .body,
                                   lineLimit: nil,
                                   tooltip: "Клик — переименовать задачу",
                                   placeholder: "Задача",
                                   text: task.title) { newTitle in
                    Task { await store.renameTask(task, to: newTitle, in: project) }
                }
                Text(overdueText(for: task))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 8)

            InlineEditableDate(date: task.dueDate, onCommit: { newDate in
                Task { await store.setTaskDueDate(task, to: newDate, in: project) }
            })
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Отметить выполненной", systemImage: "checkmark.circle.fill") {
                Task { await store.toggleTask(task, in: project) }
            }
            Divider()
            Button("Удалить", systemImage: "trash", role: .destructive) {
                Task { await store.deleteTask(task, in: project) }
            }
        }
    }

    private var worstOverdueDays: Int {
        let calendar = Calendar.current
        return store.overdueTasks
            .compactMap(\.task.dueDate)
            .compactMap { calendar.dateComponents([.day], from: $0, to: .now).day }
            .max() ?? 0
    }

    private func overdueText(for task: ProjectTask) -> String {
        guard let due = task.dueDate else { return "" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: due, to: .now).day ?? 0
        let date = RuDate.abbreviatedDateTime(due)
        if days >= 1 {
            return "просрочено на \(days) \(RuGrammar.plural(days, one: "день", few: "дня", many: "дней")) · срок \(date)"
        }
        return "срок прошёл сегодня в \(RuDate.timeOnly(due))"
    }
}
