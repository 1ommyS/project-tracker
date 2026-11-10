import SwiftUI

struct OpenQuickStatusButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            store.prepareQuickStatus()
            openWindow(id: "quick-status")
            NSApp.activate()
        } label: { Label("Быстрый статус…", systemImage: "square.and.pencil") }
    }
}

struct OpenStatusGuideButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Гайд: статусы из Confluence…", systemImage: "text.book.closed") {
            openWindow(id: "status-guide")
            NSApp.activate()
        }
    }
}

struct TraceMenuBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        OpenQuickStatusButton()
        OpenStatusGuideButton()
        Divider()
        Button("Открыть Trace Desktop") { openWindow(id: "main"); NSApp.activate() }
        SettingsLink { Text("Настройки…") }
        Divider()
        Button("Завершить Trace Desktop") { NSApp.terminate(nil) }
    }
}

struct QuickStatusView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var draft = store.quickStatusDraft
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Быстрый статус").font(.title2.bold())
                Spacer()
                OpenStatusGuideButton().labelStyle(.iconOnly).help("Как перенести статус из Confluence")
            }
            Picker("Проект", selection: $draft.projectID) {
                Text("Выберите проект").tag(UUID?.none)
                ForEach(store.activeProjects.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { project in
                    Text(project.title).tag(Optional(project.id))
                }
            }
            DatePicker("Дата", selection: $draft.day, displayedComponents: .date)
            MarkdownEditor(text: $draft.text,
                           placeholder: "Что изменилось? Можно вставить ответ модели с разделами «## Статус» и «## Блокеры».",
                           minHeight: 180, autofocus: true)
            Text(draft.error ?? "Заметка дополнит статус выбранного дня. Существующий текст останется.")
                .font(.callout).foregroundStyle(draft.error == nil ? Color.secondary : Color.red)
                .frame(height: 40, alignment: .topLeading)
            HStack {
                Button("Закрыть") { dismissWindow(id: "quick-status") }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Добавить статус") {
                    Task {
                        if await store.saveQuickStatus() { dismissWindow(id: "quick-status") }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.projectID == nil || draft.text.nilIfBlank == nil)
            }
            Text("⌘↩ — добавить · Закрытие окна сохраняет черновик до выхода из Trace Desktop")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(PulseMetrics.screen)
        .frame(width: 560, height: 660)
        .disabled(draft.isSaving)
        .task { await store.start(); store.prepareQuickStatus() }
    }
}
