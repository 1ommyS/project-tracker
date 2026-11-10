import Foundation
import CryptoKit

nonisolated enum MarkdownCodec {
    static let iso = ISO8601DateFormatter()

    static func encode(project: Project) -> String {
        let tags = project.tags.map { quote($0) }.joined(separator: ", ")
        let tasks = project.tasks.map { task in
            let due = task.dueDate.map { " 📅 \(taskDate.string(from: $0)) ⏰ \(taskTime.string(from: $0))" } ?? ""
            return "- [\(task.isDone ? "x" : " ")] \(task.title)\(due) <!-- trace-task-id:\(task.id.uuidString) -->"
        }.joined(separator: "\n")
        return """
        ---
        type: project
        id: \(project.id.uuidString)
        title: \(quote(project.title))
        epic: \(quote(project.epic))
        parent_project: \(quote(project.parentProject))
        state: \(project.state.rawValue)
        tags: [\(tags)]
        created: \(iso.string(from: project.createdAt))
        updated: \(iso.string(from: project.updatedAt))
        archived: \(project.isArchived)
        ---
        # \(project.title)

        ## Описание
        \(project.summary)

        ## Статус
        \(project.status)

        ## Артефакты
        \(project.artifacts.map { "- [\(escapeLinkTitle($0.title))](\($0.url)) <!-- trace-artifact-id:\($0.id.uuidString) -->" }.joined(separator: "\n"))

        ## Задачи
        \(tasks)
        """
    }

    static func decodeProject(_ text: String, folderURL: URL) throws -> Project {
        let frontmatter = parseFrontmatter(text)
        guard let id = UUID(uuidString: frontmatter["id"] ?? ""),
              let title = frontmatter["title"]?.unquoted else { throw CodecError.invalidProject }
        let created = iso.date(from: frontmatter["created"] ?? "") ?? .now
        let updated = iso.date(from: frontmatter["updated"] ?? "") ?? created
        let tags = parseArray(frontmatter["tags"] ?? "")
        let state = ProjectState(rawValue: frontmatter["state"] ?? "active") ?? .active
        let archived = frontmatter["archived"] == "true" || state == .archived
        var taskOccurrences: [String: Int] = [:]
        let tasks = section("Задачи", in: text).split(separator: "\n").compactMap { line -> ProjectTask? in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("- ["), value.count > 6 else { return nil }
            let done = value.lowercased().hasPrefix("- [x]")
            let identity = splitIdentity(value, kind: "task")
            let rawTitle = String(identity.content.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let parsed = parseTaskText(rawTitle)
            let occurrence = taskOccurrences[identity.content, default: 0]
            taskOccurrences[identity.content] = occurrence + 1
            let taskID = identity.id ?? stableID(projectID: id, kind: "task", source: identity.content, occurrence: occurrence)
            return ProjectTask(id: taskID, title: parsed.title, isDone: done, dueDate: parsed.date)
        }
        return Project(id: id, title: title,
                       epic: frontmatter["epic"]?.unquoted ?? "",
                       parentProject: frontmatter["parent_project"]?.unquoted ?? "",
                       summary: section("Описание", in: text),
                       status: section("Статус", in: text), tags: tags,
                       state: state, tasks: tasks,
                       createdAt: created, updatedAt: updated, isArchived: archived,
                       statuses: [],
                       artifacts: parseArtifacts(section("Артефакты", in: text), projectID: id),
                       folderURL: folderURL)
    }

    static func encode(status: DailyStatus) -> String {
        """
        ---
        type: daily-status
        id: \(status.id.uuidString)
        project: \(status.projectID.uuidString)
        date: \(iso.string(from: status.date))
        created: \(iso.string(from: status.createdAt))
        updated: \(iso.string(from: status.updatedAt))
        ---
        ## Статус
        \(status.status)
        \(status.tasks.isEmpty ? "" : "\n" + status.tasks.map { "- [\($0.isDone ? "x" : " ")] \($0.title)" }.joined(separator: "\n"))

        ## Блокеры
        \(status.blockers)
        """
    }

    static func decodeStatus(_ text: String, fileURL: URL) throws -> DailyStatus {
        let frontmatter = parseFrontmatter(text)
        guard let id = UUID(uuidString: frontmatter["id"] ?? ""),
              let projectID = UUID(uuidString: frontmatter["project"] ?? "") else { throw CodecError.invalidStatus }
        let created = iso.date(from: frontmatter["created"] ?? "") ?? .now
        let date = iso.date(from: frontmatter["date"] ?? "") ?? created
        // Строки-чекбоксы выносятся из текста статуса в отдельный список задач.
        var statusText = ""
        var tasks: [StatusTask] = []
        var fence: String?
        for line in section("Статус", in: text).split(separator: "\n", omittingEmptySubsequences: false) {
            let value = line.trimmingCharacters(in: .whitespaces)
            let wasInCodeBlock = fence != nil
            fence = codeFence(after: value, current: fence)
            if !wasInCodeBlock && fence == nil && (value.hasPrefix("- [ ] ") || value.lowercased().hasPrefix("- [x] ")) {
                tasks.append(StatusTask(id: tasks.count,
                                        title: String(value.dropFirst(6)),
                                        isDone: value.lowercased().hasPrefix("- [x]")))
            } else {
                statusText += line + "\n"
            }
        }
        return DailyStatus(id: id,
                           projectID: projectID,
                           date: date,
                           status: statusText.trimmingCharacters(in: .whitespacesAndNewlines),
                           blockers: section("Блокеры", in: text),
                           tasks: tasks,
                           createdAt: created,
                           updatedAt: iso.date(from: frontmatter["updated"] ?? "") ?? created,
                           fileURL: fileURL)
    }

    static func parseFrontmatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    private static func section(_ name: String, in text: String) -> String {
        let metadata = parseFrontmatter(text)
        let isDaily = metadata["type"] == "daily-status" || metadata["project"] != nil
        let headers: Set<String> = isDaily
            ? ["## Статус", "## Блокеры"]
            : ["## Описание", "## Статус", "## Артефакты", "## Задачи"]
        var collecting = false
        var fence: String?
        var result: [String] = []
        var inFrontmatter = text.hasPrefix("---\n") || text.hasPrefix("---\r\n")
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            if inFrontmatter {
                if index > 0 && line == "---" { inFrontmatter = false }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence == nil, headers.contains(trimmed) {
                if collecting { break }
                collecting = trimmed == "## \(name)"
                continue
            }
            fence = codeFence(after: trimmed, current: fence)
            if collecting { result.append(line) }
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Не допускаем запись текста, который неоднозначен с разделителями формата.
    /// Ошибка остаётся в редакторе вместе с исходным черновиком.
    static func validate(status: DailyStatus) throws {
        for content in [status.status, status.blockers] {
            var fence: String?
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if fence == nil && ["## Статус", "## Блокеры"].contains(trimmed) {
                    throw CodecError.reservedHeading
                }
                fence = codeFence(after: trimmed, current: fence)
            }
            if fence != nil { throw CodecError.unclosedCodeFence }
        }
    }

    static func codeFence(after line: String, current: String?) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return current }
        let marker = String(trimmed.prefix(while: { $0 == first }))
        guard marker.count >= 3 else { return current }
        if let current {
            return first == current.first && marker.count >= current.count
                && trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).isEmpty ? nil : current
        }
        return marker
    }

    /// Строки «- [Название](url)» -> артефакты.
    private static func parseArtifacts(_ section: String, projectID: UUID) -> [ProjectArtifact] {
        var occurrences: [String: Int] = [:]
        return section.split(separator: "\n").compactMap { line in
            let identity = splitIdentity(String(line), kind: "artifact")
            guard let match = identity.content.firstMatch(of: /^\s*-\s*\[(.+?)\]\((.+?)\)\s*$/) else { return nil }
            let occurrence = occurrences[identity.content, default: 0]
            occurrences[identity.content] = occurrence + 1
            let id = identity.id ?? stableID(projectID: projectID, kind: "artifact", source: identity.content, occurrence: occurrence)
            let title = String(match.output.1).replacingOccurrences(of: "\\]", with: "]")
                .replacingOccurrences(of: "\\[", with: "[").replacingOccurrences(of: "\\\\", with: "\\")
            return ProjectArtifact(id: id, title: title, url: String(match.output.2))
        }
    }

    private static func escapeLinkTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func splitIdentity(_ line: String, kind: String) -> (content: String, id: UUID?) {
        let marker = " <!-- trace-\(kind)-id:"
        guard line.hasSuffix(" -->"), let range = line.range(of: marker, options: .backwards),
              let id = UUID(uuidString: String(line[range.upperBound...].dropLast(4))) else { return (line, nil) }
        return (String(line[..<range.lowerBound]), id)
    }

    /// Legacy files have reproducible IDs even before their first save.
    private static func stableID(projectID: UUID, kind: String, source: String, occurrence: Int) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("\(projectID)|\(kind)|\(source)|\(occurrence)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func parseArray(_ value: String) -> [String] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).unquoted }
            .filter { !$0.isEmpty }
    }

    private static func parseTaskText(_ value: String) -> (title: String, date: Date?) {
        guard let dueRange = value.range(of: " 📅 ") else { return (value, nil) }
        let title = String(value[..<dueRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let metadata = String(value[dueRange.upperBound...])
        let parts = metadata.components(separatedBy: " ⏰ ")
        guard let day = parts.first, let base = taskDate.date(from: day) else { return (title, nil) }
        guard parts.count > 1, let time = taskTime.date(from: parts[1]) else { return (title, base) }
        let timeParts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (title, Calendar.current.date(bySettingHour: timeParts.hour ?? 9, minute: timeParts.minute ?? 0, second: 0, of: base))
    }

    private static let taskDate: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    private static let taskTime: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm"; return formatter
    }()

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    enum CodecError: LocalizedError {
        case invalidProject, invalidStatus, reservedHeading, unclosedCodeFence

        var errorDescription: String? {
            switch self {
            case .invalidProject: "Некорректные данные проекта в Markdown."
            case .invalidStatus: "Некорректные данные дневного статуса в Markdown."
            case .reservedHeading: "Заголовки «## Статус» и «## Блокеры» зарезервированы форматом. Используйте ### для вложенного заголовка."
            case .unclosedCodeFence: "Закройте блок кода таким же количеством символов ` или ~ перед сохранением."
            }
        }
    }
}

private extension String {
    nonisolated var unquoted: String {
        guard hasPrefix("\""), hasSuffix("\"") else { return self }
        return String(dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
