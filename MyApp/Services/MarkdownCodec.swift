import Foundation

nonisolated enum MarkdownCodec {
    static let iso = ISO8601DateFormatter()

    static func encode(project: Project) -> String {
        let tags = project.tags.map { quote($0) }.joined(separator: ", ")
        let tasks = project.tasks.map { task in
            let due = task.dueDate.map { " 📅 \(taskDate.string(from: $0)) ⏰ \(taskTime.string(from: $0))" } ?? ""
            return "- [\(task.isDone ? "x" : " ")] \(task.title)\(due)"
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

        ## Задачи
        \(tasks)

        ## Заметки
        \(project.notes)
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
        let tasks = section("Задачи", in: text).split(separator: "\n").compactMap { line -> ProjectTask? in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("- ["), value.count > 6 else { return nil }
            let done = value.lowercased().hasPrefix("- [x]")
            let rawTitle = String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let parsed = parseTaskText(rawTitle)
            return ProjectTask(title: parsed.title, isDone: done, dueDate: parsed.date)
        }
        return Project(id: id, title: title,
                       epic: frontmatter["epic"]?.unquoted ?? "",
                       parentProject: frontmatter["parent_project"]?.unquoted ?? "",
                       summary: section("Описание", in: text), tags: tags,
                       state: state, tasks: tasks, notes: section("Заметки", in: text),
                       createdAt: created, updatedAt: updated, isArchived: archived,
                       statuses: [], folderURL: folderURL)
    }

    static func encode(status: DailyStatus) -> String {
        """
        ---
        type: daily-status
        id: \(status.id.uuidString)
        project: \(status.projectID.uuidString)
        project_title: \(quote(status.projectTitle))
        date: \(iso.string(from: status.date))
        state: \(status.state.rawValue)
        created: \(iso.string(from: status.createdAt))
        updated: \(iso.string(from: status.updatedAt))
        ---
        # Статус за \(status.date.formatted(date: .long, time: .omitted))

        Проект: [[Project]]

        ## Выполнено
        \(status.completed)

        ## Планы
        \(status.plans)

        ## Блокеры
        \(status.blockers)

        ## Заметки
        \(status.notes)
        """
    }

    static func decodeStatus(_ text: String, fileURL: URL) throws -> DailyStatus {
        let fm = parseFrontmatter(text)
        guard let id = UUID(uuidString: fm["id"] ?? ""),
              let projectID = UUID(uuidString: fm["project"] ?? "") else { throw CodecError.invalidStatus }
        let created = iso.date(from: fm["created"] ?? "") ?? .now
        return DailyStatus(id: id, projectID: projectID, projectTitle: fm["project_title"]?.unquoted ?? "Проект",
                           date: iso.date(from: fm["date"] ?? "") ?? created,
                           state: ProjectState(rawValue: fm["state"] ?? "active") ?? .active,
                           completed: section("Выполнено", in: text), plans: section("Планы", in: text),
                           blockers: section("Блокеры", in: text), notes: section("Заметки", in: text),
                           createdAt: created, updatedAt: iso.date(from: fm["updated"] ?? "") ?? created,
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
        let marker = "## \(name)"
        guard let range = text.range(of: marker) else { return "" }
        let rest = text[range.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    enum CodecError: Error { case invalidProject, invalidStatus }
}

private extension String {
    nonisolated var unquoted: String {
        guard hasPrefix("\""), hasSuffix("\"") else { return self }
        return String(dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
