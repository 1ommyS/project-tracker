import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.calendar) private var calendar

    private var openTasks: [TaskContext] { store.allOpenTasks }

    private var overdue: [TaskContext] {
        let startOfDay = calendar.startOfDay(for: .now)
        return openTasks
            .filter { context in context.task.dueDate.map { $0 < startOfDay } ?? false }
            .sorted { ($0.task.dueDate ?? .now) < ($1.task.dueDate ?? .now) }
    }

    private var dueToday: [TaskContext] {
        openTasks
            .filter { context in context.task.dueDate.map { calendar.isDateInToday($0) } ?? false }
            .sorted { ($0.task.dueDate ?? .now) < ($1.task.dueDate ?? .now) }
    }

    private var upcoming: [TaskContext] {
        let startOfDay = calendar.startOfDay(for: .now)
        let horizon = calendar.date(byAdding: .day, value: 8, to: startOfDay) ?? startOfDay
        return openTasks
            .filter { context in
                guard let due = context.task.dueDate, due > startOfDay, due < horizon, !calendar.isDateInToday(due) else { return false }
                return true
            }
            .sorted { ($0.task.dueDate ?? .now) < ($1.task.dueDate ?? .now) }
    }

    private var unscheduled: [TaskContext] {
        openTasks
            .filter { $0.task.dueDate == nil }
            .sorted { $0.project.pathLabel.localizedCaseInsensitiveCompare($1.project.pathLabel) == .orderedAscending }
    }

    private var doneCount: Int { store.activeProjects.reduce(0) { $0 + $1.doneTasks.count } }
    private var totalCount: Int { store.activeProjects.reduce(0) { $0 + $1.tasks.count } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch store.interfaceMode {
                case .detailed:
                    detailedContent
                case .focused:
                    focusedContent
                }
            }
            .padding(PulseMetrics.screen)
            .frame(maxWidth: PulseMetrics.contentWidth, alignment: .leading)
        }
        .softScrollFade()
        .navigationTitle("Сегодня")
    }

    /// Полный вид: приветствие, метрики и все секции задач.
    @ViewBuilder
    private var detailedContent: some View {
        TodayHero(total: totalCount, done: doneCount,
                  dueToday: dueToday.count, overdue: overdue.count,
                  accent: store.palette.color,
                  onOpenProjects: { store.open(.projects) })

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            MetricCard(value: "\(openTasks.count)", label: "открытых задач", symbol: "circle.stack", tint: .blue)
            MetricCard(value: "\(dueToday.count)", label: "на сегодня", symbol: "sun.max.fill", tint: dueToday.isEmpty ? .green : PulseStyle.amber)
            MetricCard(value: "\(overdue.count)", label: "просрочено", symbol: "exclamationmark.triangle.fill", tint: overdue.isEmpty ? .green : .red)
        }

        statusMatrix
        sectionsContent
    }

    /// Фокус: без шапки и метрик — только просроченное и сегодняшнее.
    @ViewBuilder
    private var focusedContent: some View {
        if store.projects.isEmpty {
            EmptyState(symbol: "square.stack.3d.up.slash", title: "Пока нет проектов",
                       message: "Создайте первый проект — и его задачи появятся здесь.")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if overdue.isEmpty && dueToday.isEmpty {
            EmptyState(symbol: "checkmark.seal.fill", title: "Всё под контролем",
                       message: "Срочных задач нет. Отдыхайте — или загляните в «Подробно», чтобы увидеть предстоящее.")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            if !overdue.isEmpty {
                TodaySection(title: "Просроченные задачи",
                             symbol: "exclamationmark.triangle.fill", tint: .red, contexts: overdue)
            }
            if !dueToday.isEmpty {
                TodaySection(title: "Задачи на сегодня",
                             symbol: "sun.max.fill", tint: store.palette.color, contexts: dueToday)
            }
        }
    }

    /// Матрица статусов: проекты × дни, с колонкой блокеров.
    /// Клик по ячейке правит статус конкретного дня инлайн.
    private var statusMatrix: some View {
        let calendar = Calendar.current
        // По убыванию даты: сегодня — первая колонка.
        let days = (0..<5).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now)) }
        let projects = store.activeProjects.sorted { $0.updatedAt > $1.updatedAt }
        let today = calendar.startOfDay(for: .now)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2").foregroundStyle(.tint).font(.body.weight(.medium))
                Text("Статусы по дням").font(.title3.bold())
                Spacer()
                Text("клик по ячейке — правка статуса на этот день")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 0) {
                    GridRow {
                        Text("Проект").font(.callout.weight(.bold)).foregroundStyle(.secondary)
                        Text("Блокеры").font(.callout.weight(.bold)).foregroundStyle(.secondary)
                        ForEach(days, id: \.self) { day in
                            Text(RuDate.dayMonthShort(day))
                                .font(day == today ? .callout.weight(.bold) : .callout)
                                .foregroundStyle(day == today ? Color.red : .secondary)
                                .frame(width: 210, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 6)

                    ForEach(projects) { project in
                        GridRow {
                            VStack(alignment: .leading, spacing: 3) {
                                Button {
                                    store.openProject(project.id)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: project.state.symbol)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(project.state.color(palette: store.palette))
                                        Text(project.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .pointingHandOnHover()
                                QuarterTag(quarter: project.quarter, compact: true)
                            }
                            .frame(width: 210, alignment: .leading)

                            InlineEditableText(font: .callout,
                                               color: (project.latestBlockers ?? "").isEmpty ? .secondary : .red,
                                               lineLimit: 4,
                                               tooltip: "Клик — правка блокеров (записывается в сегодняшний статус)",
                                               placeholder: "—",
                                               text: project.latestBlockers ?? "") { newBlockers in
                                Task { await store.setDailyStatus(text: nil, blockers: newBlockers, for: project, on: .now) }
                            }
                            .frame(width: 200, alignment: .leading)

                            ForEach(days, id: \.self) { day in
                                statusCell(project: project, day: day)
                            }
                        }
                        Divider().gridCellColumns(2 + days.count)
                    }
                }
                .padding(PulseMetrics.card)
                .frame(minWidth: 1290, alignment: .leading)
            }
        }
    }

    /// Ячейка дня: текст статуса + чекбоксы задач из файла статуса.
    private func statusCell(project: Project, day: Date) -> some View {
        let entry = project.dailyStatus(on: day)
        return VStack(alignment: .leading, spacing: 3) {
            InlineEditableText(font: .callout,
                               color: .secondary,
                               lineLimit: 5,
                               tooltip: "Статус на \(RuDate.dayMonthShort(day))",
                               placeholder: "—",
                               text: entry?.status ?? "") { newText in
                Task { await store.setDailyStatus(text: newText, blockers: nil, for: project, on: day) }
            }
            if let entry {
                ForEach(entry.tasks) { task in
                    Button {
                        Task { await store.toggleStatusTask(task, in: entry, for: project) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.footnote)
                                .foregroundStyle(task.isDone ? PulseStyle.mint : .secondary)
                            Text(task.title)
                                .font(.footnote)
                                .foregroundStyle(task.isDone ? .secondary : .primary)
                                .strikethrough(task.isDone)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(task.isDone ? "Вернуть в работу" : "Отметить выполненной")
                }
            }
        }
        .frame(width: 210, alignment: .leading)
    }

    @ViewBuilder
    private var sectionsContent: some View {
        if store.projects.isEmpty {
            EmptyState(symbol: "square.stack.3d.up.slash", title: "Пока нет проектов",
                       message: "Создайте первый проект — и его задачи появятся здесь.")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if openTasks.isEmpty {
            EmptyState(symbol: "checkmark.seal.fill", title: "Все задачи выполнены",
                       message: "Открытых задач нет. Добавьте новую в любом проекте — поле быстрого ввода ждёт в ленте проектов.")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            if !overdue.isEmpty {
                TodaySection(title: "Просроченные задачи",
                             symbol: "exclamationmark.triangle.fill", tint: .red, contexts: overdue)
            }
            if !dueToday.isEmpty {
                TodaySection(title: "Задачи на сегодня",
                             symbol: "sun.max.fill", tint: store.palette.color, contexts: dueToday)
            }
            if !upcoming.isEmpty {
                TodaySection(title: "Предстоящие задачи",
                             symbol: "clock.arrow.circlepath", tint: PulseStyle.indigo, contexts: upcoming)
            }
            if !unscheduled.isEmpty {
                TodayUnscheduledSection(contexts: unscheduled)
            }
        }
    }
}

// MARK: - Шапка

private struct TodayHero: View {
    let total: Int, done: Int, dueToday: Int, overdue: Int
    let accent: Color
    let onOpenProjects: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { total == 0 ? 1 : Double(done) / Double(total) }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        default: "Добрый вечер"
        }
    }

    private var headline: String {
        if total == 0 { return "Задач пока нет — самое время их добавить." }
        if overdue > 0 { return "Просрочено задач: \(overdue). Начните с них — они ждут дольше всех." }
        if dueToday > 0 { return "На сегодня задач: \(dueToday). Ровно столько, сколько нужно для хорошего дня." }
        return "Срочных задач нет. Всё под контролем."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(RuDate.full(.now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(greeting).font(.largeTitle.bold())
                Text(headline)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if dueToday + overdue > 0 {
                    Button("Открыть проекты", systemImage: "arrow.right.circle.fill", action: onOpenProjects)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 12)
            progressRing
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle().trim(from: 0, to: progress).stroke(
                AngularGradient(colors: [accent, .mint, accent], center: .center),
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
            ).rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .spring, value: progress)
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))%").font(.title3.bold()).monospacedDigit()
                Text("выполнено").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
    }
}

private struct MetricCard: View {
    let value: String, label: String, symbol: String
    let tint: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(PulseMetrics.card).frame(maxWidth: .infinity)
        .pulsePanel(radius: 12)
        .animation(.snappy, value: value)
    }
}

// MARK: - Секции задач

private struct TodaySection: View {
    let title: String
    let symbol: String
    let tint: Color
    let contexts: [TaskContext]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint).font(.body.weight(.medium))
                Text(title).font(.title3.bold())
                Spacer()
                Text("\(contexts.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(contexts) { context in
                    ContextTaskRow(context: context)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(PulseMetrics.card)
            .pulsePanel(radius: 12)
            .animation(.snappy, value: contexts.map(\.id))
        }
    }
}

private struct TodayUnscheduledSection: View {
    let contexts: [TaskContext]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(contexts) { context in
                        ContextTaskRow(context: context)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray").foregroundStyle(.secondary).font(.body.weight(.medium))
                    Text("Без срока").font(.title3.bold())
                    Spacer()
                    Text("\(contexts.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(PulseMetrics.card)
            .pulsePanel(radius: 12)
        }
    }
}


