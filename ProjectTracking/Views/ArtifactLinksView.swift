import SwiftUI

struct ArtifactLinksSection: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var editing: ArtifactEditorContext?
    @State private var removing: ProjectArtifact?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Полезные ссылки").font(.title3.bold())
                Spacer()
                Button("Добавить ссылку", systemImage: "plus") { editing = ArtifactEditorContext(artifact: nil) }
            }
            if project.artifacts.isEmpty {
                Text("Документы, макеты, Confluence — всё нужное для проекта.")
                    .foregroundStyle(.secondary)
            }
            ForEach(project.artifacts) { artifact in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let url = URL(string: artifact.url) { Link(artifact.title, destination: url).font(.headline) }
                        else { Text(artifact.title).font(.headline) }
                        Text(artifact.url).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Button { editing = ArtifactEditorContext(artifact: artifact) } label: {
                        Label("Редактировать ссылку", systemImage: "pencil")
                    }
                    .labelStyle(.iconOnly)
                    .help("Изменить название или адрес")
                    Menu {
                        Button("Копировать адрес") { Clipboard.copy(artifact.url) }
                        Button("Копировать Markdown") { Clipboard.copy("[\(artifact.title)](\(artifact.url))") }
                        Button("Удалить ссылку…", role: .destructive) { removing = artifact }
                    } label: { Label("Действия со ссылкой", systemImage: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(PulseMetrics.card)
        .pulsePanel()
        .sheet(item: $editing) { context in ArtifactEditorView(projectID: project.id, artifact: context.artifact) }
        .confirmationDialog("Удалить ссылку?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible) {
            Button("Удалить ссылку", role: .destructive) {
                guard let removing else { return }
                Task { await store.removeArtifact(removing, from: project) }
            }
        } message: { Text(removing?.title ?? "") }
    }
}

private struct ArtifactEditorContext: Identifiable {
    let artifact: ProjectArtifact?
    var id: String { artifact?.id.uuidString ?? "new" }
}

private struct ArtifactEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let artifact: ProjectArtifact?
    @State private var title: String
    @State private var url: String
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var urlFocused: Bool

    init(projectID: UUID, artifact: ProjectArtifact?) {
        self.projectID = projectID
        self.artifact = artifact
        _title = State(initialValue: artifact?.title ?? "")
        _url = State(initialValue: artifact?.url ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PulseMetrics.card) {
            Text(artifact == nil ? "Новая ссылка" : "Редактирование ссылки").font(.title2.bold())
            VStack(alignment: .leading) {
                Text("Адрес").font(.headline)
                TextField("https://… или [название](адрес)", text: $url)
                    .textFieldStyle(.roundedBorder).focused($urlFocused)
            }
            VStack(alignment: .leading) {
                Text("Название").font(.headline)
                TextField("Например: Техническое задание", text: $title).textFieldStyle(.roundedBorder)
            }
            Text(error ?? "Можно вставить адрес страницы или Markdown-ссылку.")
                .font(.callout).foregroundStyle(error == nil ? Color.secondary : Color.red)
                .frame(height: 44, alignment: .topLeading)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(url.nilIfBlank == nil)
            }
        }
        .padding(PulseMetrics.screen)
        .frame(width: 500)
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
        .onAppear { urlFocused = true }
    }

    private func save() {
        guard let project = store.projects.first(where: { $0.id == projectID }) else {
            error = "Проект больше не доступен."
            return
        }
        isSaving = true
        Task {
            let saved = await store.saveArtifact(id: artifact?.id, title: title, url: url, in: project)
            isSaving = false
            if saved { dismiss() } else { error = store.errorMessage }
        }
    }
}
