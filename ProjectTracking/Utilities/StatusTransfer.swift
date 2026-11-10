import Foundation

nonisolated struct StatusTransfer {
    let status: String
    let blockers: String

    /// A model can return two ordinary Markdown sections; plain text is a quick note.
    static func parse(_ source: String) throws -> StatusTransfer {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```markdown\n"), text.hasSuffix("\n```") {
            text = String(text.dropFirst("```markdown\n".count).dropLast("\n```".count))
        }
        var status: [String] = []
        var blockers: [String] = []
        var section = 0
        var sawStatus = false
        var sawBlockers = false
        var fence: String?
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence == nil, trimmed == "## Статус" {
                guard !sawStatus, !sawBlockers, status.allSatisfy({ $0.nilIfBlank == nil }) else { throw TransferError.invalidSections }
                sawStatus = true
                section = 0
                continue
            }
            if fence == nil, trimmed == "## Блокеры" {
                guard !sawBlockers else { throw TransferError.invalidSections }
                sawBlockers = true
                section = 1
                continue
            }
            fence = MarkdownCodec.codeFence(after: trimmed, current: fence)
            if section == 0 { status.append(line) } else { blockers.append(line) }
        }
        let value = StatusTransfer(status: status.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                                   blockers: blockers.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        guard value.status.nilIfBlank != nil || value.blockers.nilIfBlank != nil else { throw TransferError.empty }
        try MarkdownCodec.validate(status: DailyStatus(projectID: UUID(), date: .now, status: value.status, blockers: value.blockers))
        return value
    }

    static func prompt(project: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return """
        Преобразуй предоставленный ниже текст из Confluence в дневной статус проекта «\(project)» за \(formatter.string(from: date)) для Trace.
        Используй только факты из источника: не придумывай сроки, результаты, ответственных и блокеры. Не считай старые планы выполненной работой. Если источник охватывает разные даты или проекты, включай только явно относящееся к выбранному проекту и дню; неопределённость обозначь в тексте.
        Кратко перечисли результат и следующие шаги; сохрани полезные ссылки как [название](полный URL). Не сокращай адреса. Если явных блокеров нет, оставь раздел блокеров пустым.
        Верни только Markdown, без вводных слов, внешнего блока кода, YAML, ID, даты и названия проекта. Формат строго такой:

        ## Статус
        - Что сделано по фактам источника
        - Следующий шаг, если он указан

        ## Блокеры
        - Только явно указанные препятствия

        Внутри разделов используй заголовки ###, обычные списки и при необходимости - [ ] для следующих действий. Не повторяй служебные заголовки ## Статус / ## Блокеры. Закрывай блоки кода.

        Исходный текст Confluence:
        [вставлю сюда скопированный текст страницы]
        """
    }

    enum TransferError: LocalizedError {
        case empty, invalidSections
        var errorDescription: String? {
            switch self {
            case .empty: "Напишите заметку или вставьте подготовленный статус."
            case .invalidSections: "Ожидаются два раздела: ## Статус, затем ## Блокеры. Уберите повторные заголовки и вводные слова."
            }
        }
    }
}
