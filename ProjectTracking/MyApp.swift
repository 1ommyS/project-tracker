import SwiftUI

@main
struct ProjectTrackingApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    ThemeController.apply(store.theme)
                    await store.start()
                }
                .onChange(of: store.theme) { _, theme in ThemeController.apply(theme) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Недавние проекты…") { store.openRecentProjects() }.keyboardShortcut("e", modifiers: .command)
                Button("Поиск…") { store.openSearch() }.keyboardShortcut("k", modifiers: .command)
                Button("Новая задача…") { store.openQuickTask() }.keyboardShortcut("t", modifiers: .command)
                Button("Обновить статус…") { store.openStatusEditor() }.keyboardShortcut(.return, modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Найти в Project Tracking…") { store.openSearch() }.keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Горячие клавиши Project Tracking") { store.openShortcutHelp() }
            }
            CommandMenu("Навигация") {
                Button("Сегодня") { store.open(.today) }.keyboardShortcut("1", modifiers: .command)
                Button("Проекты") { store.open(.projects) }.keyboardShortcut("2", modifiers: .command)
                Button("Активность") { store.open(.activity) }.keyboardShortcut("3", modifiers: .command)
                Button("Архив") { store.open(.archive) }.keyboardShortcut("4", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
                .environment(store)
                .frame(minWidth: 480, idealWidth: 620, maxWidth: 760, minHeight: 420, idealHeight: 560, maxHeight: 820)
        }
    }

}
