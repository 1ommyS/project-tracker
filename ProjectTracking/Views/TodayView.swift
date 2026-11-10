import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store

    private var openTasks: [TaskContext] { store.allOpenTasks }

    private var overdue: [TaskContext] { store.taskAgenda.beforeToday }
    private var dueToday: [TaskContext] { store.taskAgenda.today }
    private var upcoming: [TaskContext] { store.taskAgenda.upcoming }
    private var unscheduled: [TaskContext] { store.taskAgenda.unscheduled }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    switch store.interfaceMode {
                    case .detailed:
                        detailedContent
                    case .focused:
                        focusedContent
                    }
                }
                .padding(PulseMetrics.screen)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .softScrollFade()
        }
        .navigationTitle("Сегодня")
    }

    /// Tasks stay in focus; the full status workspace has its own navigation item.
    @ViewBuilder
    private var detailedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(RuDate.full(.now)).font(.title2.bold())
            Text("Сегодня: \(dueToday.count) · Просрочено: \(overdue.count) · Открыто: \(openTasks.count)")
                .foregroundStyle(.secondary)
            HStack {
                Button("Статусы проектов", systemImage: "tablecells") { store.open(.statuses) }
                Spacer()
                OpenQuickStatusButton()
            }
        }
        .padding(PulseMetrics.card).pulsePanel().pageWidth()
        sectionsContent.pageWidth()
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
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(contexts) { context in
                    ContextTaskRow(context: context)
                }
            }
            .padding(PulseMetrics.card)
            .pulsePanel(radius: 12)
        }
    }
}

private struct TodayUnscheduledSection: View {
    let contexts: [TaskContext]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $expanded) {
                LazyVStack(alignment: .leading, spacing: 4) {
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
