import SwiftUI

struct StatusTransferGuideView: View {
    @Environment(AppStore.self) private var store
    @State private var projectID: UUID?
    @State private var day = Date.now
    @State private var copied = false

    private var prompt: String {
        StatusTransfer.prompt(project: store.projects.first(where: { $0.id == projectID })?.title ?? "Название проекта", date: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PulseMetrics.card) {
            Text("Статусы из Confluence").font(.title2.bold())
            Text("1. Скопируйте нужный фрагмент страницы Confluence.\n2. Передайте модели промпт ниже и текст страницы.\n3. Скопируйте ответ в «Быстрый статус», проверьте проект и дату, нажмите ⌘↩.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Проект", selection: $projectID) {
                    Text("Любой проект").tag(UUID?.none)
                    ForEach(store.activeProjects) { Text($0.title).tag(Optional($0.id)) }
                }
                DatePicker("Дата", selection: $day, displayedComponents: .date)
            }
            HStack {
                Text("Промпт для модели").font(.headline)
                Spacer()
                Button(copied ? "Скопировано" : "Копировать промпт", systemImage: "doc.on.doc") {
                    Clipboard.copy(prompt)
                    copied = true
                }
            }
            ScrollView {
                Text(prompt).font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PulseMetrics.card)
            }
            .pulsePanel()
            HStack {
                Text("Trace Desktop принимает обычный текст или два Markdown-раздела. Приложение само не подключается к Confluence или модели.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                OpenQuickStatusButton()
            }
        }
        .padding(PulseMetrics.screen)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 620, idealHeight: 740)
        .onAppear { projectID = store.selectedProjectID }
        .onChange(of: projectID) { _, _ in copied = false }
        .onChange(of: day) { _, _ in copied = false }
    }
}
