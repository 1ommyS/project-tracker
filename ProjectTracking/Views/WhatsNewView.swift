import SwiftUI

// MARK: - Модель и парсер

struct WhatsNewSection: Identifiable, Equatable {
    enum Block: Equatable {
        case header(String)
        case item(String)
    }

    var title: String
    var blocks: [Block]
    var id: String { title }
}

nonisolated enum WhatsNewParser {
    /// Разбирает простой markdown (## секции, ### подзаголовки, - пункты).
    static func parse(_ markdown: String) -> [WhatsNewSection] {
        var sections: [WhatsNewSection] = []
        var current: WhatsNewSection?
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                if let section = current { sections.append(section) }
                current = WhatsNewSection(title: String(trimmed.dropFirst(3)), blocks: [])
            } else if trimmed.hasPrefix("### ") {
                current?.blocks.append(.header(String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("- ") {
                current?.blocks.append(.item(String(trimmed.dropFirst(2))))
            } else if !trimmed.isEmpty {
                current?.blocks.append(.item(trimmed))
            }
        }
        if let section = current { sections.append(section) }
        return sections
    }

    /// Содержимое WhatsNew.md из бандла приложения.
    static var bundledMarkdown: String {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

// MARK: - Экран «Что нового»

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections = WhatsNewParser.parse(WhatsNewParser.bundledMarkdown)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Что нового").font(.title2.bold())
                Spacer()
                Button("Продолжить") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, PulseMetrics.screen)
            .padding(.vertical, 16)

            Divider()

            if sections.isEmpty {
                EmptyState(symbol: "sparkles", title: "Нет описания",
                           message: "Файл WhatsNew.md не найден в сборке.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(PulseMetrics.screen)
                    .frame(maxWidth: 620, alignment: .leading)
                }
                .softScrollFade()
            }
        }
        .frame(minWidth: 460, idealWidth: 620, maxWidth: 720, minHeight: 420, idealHeight: 580, maxHeight: 760)
    }

    private func sectionView(_ section: WhatsNewSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.title3.bold())
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: WhatsNewSection.Block) -> some View {
        switch block {
        case .header(let title):
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        case .item(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.tint)
                Text(inlineMarkdown(text))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
