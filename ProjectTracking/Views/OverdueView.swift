import Charts
import SwiftUI

/// Дашборд просроченных задач: всё, что пропущено по срокам,
/// сгруппировано по проектам, самые старые — сверху.
struct OverdueView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay: Date?

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
                        dailyChart
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

    // MARK: - Гистограмма просрочек по дням

    private struct DailyOverdue: Identifiable {
        let day: Date
        let count: Int
        var id: Date { day }
    }

    /// От самого старого просроченного дедлайна до сегодня; пустые дни — нули.
    private var dailyHistogram: [DailyOverdue] {
        let calendar = Calendar.current
        let dues = store.overdueTasks.compactMap { $0.task.dueDate }
        guard let oldest = dues.min() else { return [] }
        var byDay: [Date: Int] = [:]
        for due in dues {
            byDay[calendar.startOfDay(for: due), default: 0] += 1
        }
        var result: [DailyOverdue] = []
        var day = calendar.startOfDay(for: oldest)
        let today = calendar.startOfDay(for: .now)
        while day <= today {
            result.append(DailyOverdue(day: day, count: byDay[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private var todayStart: Date { Calendar.current.startOfDay(for: .now) }

    private var worstDay: Date? {
        dailyHistogram.max(by: { $0.count < $1.count })?.day
    }

    private var dailyChart: some View {
        let histogram = dailyHistogram
        let labelStride = max(1, histogram.count / 6)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Просрочки по дням", systemImage: "chart.bar.fill")
                    .font(.title3.bold())
                Spacer()
                Text("по дню дедлайна")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart(histogram) { item in
                BarMark(
                    x: .value("День", item.day, unit: .day),
                    y: .value("Задачи", item.count)
                )
                .foregroundStyle(item.day == todayStart ? Color.red : Color.red.opacity(0.45))
                .cornerRadius(3)
            }
            .chartXSelection(value: $selectedDay)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: labelStride)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(RuDate.dayMonthShort(date))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 150)

            if let day = selectedDay ?? worstDay, (selectedDay ?? worstDay) != nil {
                selectionDetail(for: day)
            }
        }
        .padding(PulseMetrics.card)
        .pulsePanel(radius: 12)
    }

    private func selectionDetail(for day: Date) -> some View {
        let calendar = Calendar.current
        let items = store.overdueTasks.filter {
            guard let due = $0.task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
        let names = items.prefix(3).map(\.task.title).joined(separator: ", ")
        let rest = items.count > 3 ? " и ещё \(items.count - 3)" : ""
        return HStack(spacing: 8) {
            Text(RuDate.dayMonthShort(day))
                .font(.caption.weight(.bold))
            Text(items.isEmpty ? "просроченных с этим дедлайном нет" : "\(names)\(rest)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
