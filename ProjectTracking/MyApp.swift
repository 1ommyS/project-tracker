import AppKit
import SwiftUI

final class TraceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load the artwork from this build instead of Launch Services' cached app icon.
        guard let url = Bundle.main.url(forResource: "TraceLogo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}

@main
struct ProjectTrackingApp: App {
    @NSApplicationDelegateAdaptor(TraceAppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @AppStorage("showMenuBarQuickStatus") private var showMenuBarQuickStatus = true

    var body: some Scene {
        WindowGroup("Trace", id: "main") {
            ContentView()
                .environment(store)
                .task {
                    ThemeController.apply(store.theme)
                    await store.start()
                }
                .onChange(of: store.theme) { _, theme in ThemeController.apply(theme) }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Недавние проекты…") { store.openRecentProjects() }.keyboardShortcut("e", modifiers: .command)
                Button("Поиск…") { store.openSearch() }.keyboardShortcut("k", modifiers: .command)
                Button("Новая задача…") { store.openQuickTask() }.keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Найти в Trace…") { store.openSearch() }.keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Назад") { store.goBack() }.keyboardShortcut("[", modifiers: .command).disabled(!store.canGoBack)
                Button("Вперёд") { store.goForward() }.keyboardShortcut("]", modifiers: .command).disabled(!store.canGoForward)
            }
            CommandMenu("Статусы") {
                OpenQuickStatusButton().environment(store).keyboardShortcut("s", modifiers: [.command, .shift])
                OpenStatusGuideButton()
            }
            CommandGroup(replacing: .help) {
                OpenStatusGuideButton()
                Button("Что нового в Trace") { store.openWhatsNew() }
                Button("Горячие клавиши Trace") { store.openShortcutHelp() }
            }
            CommandMenu("Навигация") {
                Button("Сегодня") { store.open(.today) }.keyboardShortcut("1", modifiers: .command)
                Button("Статусы") { store.open(.statuses) }.keyboardShortcut("6", modifiers: .command)
                Button("Проекты") { store.open(.projects) }.keyboardShortcut("2", modifiers: .command)
                Button("Просрочено") { store.open(.overdue) }.keyboardShortcut("3", modifiers: .command)
                Button("Поиск") { store.open(.search) }.keyboardShortcut("4", modifiers: .command)
                Button("Архив") { store.open(.archive) }.keyboardShortcut("5", modifiers: .command)
            }
        }
        Window("Быстрый статус", id: "quick-status") {
            QuickStatusView().environment(store).environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        Window("Статусы из Confluence", id: "status-guide") {
            StatusTransferGuideView().environment(store).environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        MenuBarExtra("Trace", systemImage: "square.and.pencil", isInserted: $showMenuBarQuickStatus) {
            TraceMenuBar().environment(store)
        }
        Settings {
            SettingsView()
                .environment(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .frame(minWidth: 480, idealWidth: 620, maxWidth: 760, minHeight: 420, idealHeight: 560, maxHeight: 820)
        }
    }

}
