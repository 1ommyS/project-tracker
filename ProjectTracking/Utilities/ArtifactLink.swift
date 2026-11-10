import Foundation

nonisolated struct ArtifactLink {
    let title: String
    let url: String

    init(title: String, url: String) throws {
        var raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = raw.firstMatch(of: /^\[(.+?)\]\((.+)\)$/) {
            if label.isEmpty { label = String(match.output.1) }
            raw = String(match.output.2)
        }
        if URLComponents(string: raw)?.scheme == nil, raw.contains("."), !raw.contains(" ") {
            raw = "https://" + raw
        }
        guard !raw.contains("\n"), !raw.contains("\r"), !label.contains("\n"), !label.contains("\r"),
              let components = URLComponents(string: raw), let scheme = components.scheme, !scheme.isEmpty,
              let parsed = components.url,
              !["http", "https"].contains(scheme.lowercased()) || components.host?.nilIfBlank != nil else {
            throw LinkError.invalidURL
        }
        self.url = parsed.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        self.title = label.isEmpty ? self.url : label
    }

    enum LinkError: LocalizedError {
        case invalidURL
        var errorDescription: String? { "Введите полную ссылку, например https://example.com/document. Можно вставить Markdown-ссылку [название](адрес)." }
    }
}
