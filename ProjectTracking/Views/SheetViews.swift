import SwiftUI

// MARK: - Недавние проекты (⌘E)

struct RecentProjectsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var recentProjects: [Project] {
        Array(store.projects.sorted { $0.updatedAt > $1.updatedAt }.prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Недавние проекты").font(.title2.bold())
                Spacer()
                Text("⌘E")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, PulseMetrics.screen)
            .padding(.vertical, 16)

            Divider()

            if recentProjects.isEmpty {
                EmptyState(symbol: "clock", title: "Недавних проектов нет", message: "Созданные проекты появятся здесь в порядке последних изменений.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recentProjects) { project in
                            Button {
                                store.openProject(project.id)
                                dismiss()
                            } label: {
                                RecentProjectRow(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, PulseMetrics.screen)
                    .padding(.vertical, 20)
                }
                .softScrollFade()
            }
        }
        .frame(minWidth: 460, idealWidth: 640, maxWidth: 760, minHeight: 360, idealHeight: 520, maxHeight: 720)
    }
}

private struct RecentProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.state.symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(project.state.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title).font(.headline).lineLimit(2)
                FadeOverflowRow { Text(project.pathLabel).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 10)
            StateBadge(state: project.state)
            Text(project.updatedAt.formatted(.relative(presentation: .named)))
                .font(.caption).foregroundStyle(.tertiary).fixedSize()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .pulsePanel(radius: 14)
        .pointingHandOnHover()
    }
}

// MARK: - Горячие клавиши (?)

struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut {
        let keys: [String]
        let title: String
        let detail: String
    }

    private struct ShortcutGroup {
        let title: String
        let shortcuts: [Shortcut]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Навигация", shortcuts: [
            .init(keys: ["⌘", "1…4"], title: "Экраны", detail: "Сегодня, Проекты, Поиск и Архив — без мыши."),
            .init(keys: ["⌘", "["], title: "Назад", detail: "Вернуться к предыдущему экрану или проекту, как в браузере."),
            .init(keys: ["⌘", "]"], title: "Вперёд", detail: "Продолжить движение вперёд по истории навигации."),
            .init(keys: ["↑", "↓"], title: "Список проектов", detail: "В режиме редактора стрелки переключают выбранный проект."),
            .init(keys: ["⌘", "E"], title: "Недавние проекты", detail: "Быстро открыть недавно изменённый проект, как Recent Files в IDEA."),
        ]),
        ShortcutGroup(title: "Создание", shortcuts: [
            .init(keys: ["⌘", "T"], title: "Новая задача", detail: "Открыть редактор задачи для выбранного проекта."),
            .init(keys: ["⌘", "N"], title: "Новый проект", detail: "Создать новую часть проекта в выбранной иерархии."),
            .init(keys: ["↩"], title: "Добавить из поля", detail: "В поле быстрого ввода нажатие Return сразу создаёт задачу."),
        ]),
        ShortcutGroup(title: "Поиск и настройки", shortcuts: [
            .init(keys: ["⌘", "F"], title: "Найти", detail: "Открыть общий поиск и сразу перейти к вводу запроса."),
            .init(keys: ["⌘", "K"], title: "Поиск", detail: "Дополнительное сочетание для быстрого поиска."),
            .init(keys: ["⌘", ","], title: "Настройки", detail: "Открыть системное окно настроек Trace."),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.title) { group in
                        shortcutTable(group)
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, PulseMetrics.screen)
                .padding(.top, 20)
                .padding(.bottom, PulseMetrics.screen)
            }
            .softScrollFade()
            Divider()
            Text("Подсказка: слова «сегодня», «завтра», дата «25.12» и время «18:30» в поле быстрого ввода превращаются в срок задачи.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PulseMetrics.screen)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 480, idealWidth: 640, maxWidth: 740, minHeight: 460, idealHeight: 620, maxHeight: 780)
    }

    private var header: some View {
        HStack {
            Text("Горячие клавиши").font(.title2.bold())
            Spacer()
            Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, PulseMetrics.screen)
        .padding(.vertical, 16)
    }

    private func shortcutTable(_ group: ShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(text: group.title)
                .padding(.bottom, 4)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                ForEach(Array(group.shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    GridRow {
                        shortcutKeys(shortcut.keys)
                            .frame(width: 112, alignment: .leading)
                            .padding(.vertical, 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.title).font(.headline)
                            Text(shortcut.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 9)
                    }
                    if index < group.shortcuts.count - 1 {
                        GridRow {
                            Divider().gridCellColumns(2)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func shortcutKeys(_ keys: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .frame(minWidth: 26, minHeight: 24)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.separator.opacity(0.45), lineWidth: 0.8))
            }
        }
    }
}
