import Foundation

/// Разобранный ввод: заголовок, срок и диапазон исходной строки,
/// который распознан как срок («завтра в 18:00») — для подсветки.
struct ParsedInput {
    let title: String
    let dueDate: Date?
    let highlightRange: Range<String.Index>?
}

/// Разбирает строку быстрого ввода в заголовок задачи и, возможно, срок.
/// Понимает «сегодня», «завтра», «послезавтра», даты «25.12» / «25.12.2027»
/// и время «18:30» / «в 14». Остальной текст остаётся заголовком задачи.
nonisolated enum TaskInputParser {
    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> (title: String, dueDate: Date?) {
        let detailed = parseDetailed(input, now: now, calendar: calendar)
        return (detailed.title, detailed.dueDate)
    }

    static func parseDetailed(_ input: String, now: Date = .now, calendar: Calendar = .current) -> ParsedInput {
        var removals: [Range<String.Index>] = []
        var day: Date?
        var time: (hour: Int, minute: Int)?

        if let match = input.firstMatch(of: /(?:^|\s)(?:[Сс]егодня|[Зз]автра|[Пп]ослезавтра)(?=\s|$)/) {
            let word = String(input[match.range]).lowercased()
            let offset = word.contains("послезавтра") ? 2 : (word.contains("завтра") ? 1 : 0)
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
            removals.append(match.range)
        }

        if day == nil,
           let match = input.firstMatch(of: /(?:^|\s)(\d{1,2})\.(\d{1,2})(?:\.(\d{2}|\d{4}))?(?=\s|$)/) {
            let dayNumber = Int(String(match.output.1)) ?? 0
            let month = Int(String(match.output.2)) ?? 0
            let rawYear = match.output.3.flatMap { Int(String($0)) }
            if (1...12).contains(month), (1...31).contains(dayNumber) {
                var components = DateComponents()
                components.day = dayNumber
                components.month = month
                components.year = rawYear.map { $0 < 100 ? 2000 + $0 : $0 } ?? calendar.component(.year, from: now)
                if let date = calendar.date(from: components) {
                    day = date
                    removals.append(match.range)
                }
            }
        }

        if let match = input.firstMatch(of: /(?:^|\s)(?:[Вв]\s+)?(\d{1,2}):(\d{2})(?=\s|$)/),
           let hour = Int(String(match.output.1)), let minute = Int(String(match.output.2)),
           (0...23).contains(hour), (0...59).contains(minute) {
            time = (hour, minute)
            removals.append(match.range)
        } else if let match = input.firstMatch(of: /(?:^|\s)[Вв]\s+(\d{1,2})(?=\s|$)/),
                  let hour = Int(String(match.output.1)), (0...23).contains(hour) {
            time = (hour, 0)
            removals.append(match.range)
        }

        guard day != nil || time != nil else {
            return ParsedInput(title: input.trimmingCharacters(in: .whitespaces), dueDate: nil, highlightRange: nil)
        }

        var lower = removals.map(\.lowerBound).min()!
        var upper = removals.map(\.upperBound).max()!
        // Regex захватывает пробел перед совпадением — в подсветку он не входит.
        while lower < upper, input[lower] == " " { lower = input.index(after: lower) }
        while upper > lower, input[input.index(before: upper)] == " " { upper = input.index(before: upper) }
        let dueDate = resolvedDate(day: day, time: time, now: now, calendar: calendar)
        return ParsedInput(title: title(from: input, removing: removals),
                           dueDate: dueDate,
                           highlightRange: lower..<upper)
    }

    private static func resolvedDate(day: Date?, time: (hour: Int, minute: Int)?, now: Date, calendar: Calendar) -> Date? {
        guard let day else {
            // Только время: сегодня, а если уже прошло — завтра.
            guard let (hour, minute) = time else { return nil }
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            let candidate = calendar.date(from: components) ?? now
            if candidate <= now {
                return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        if let (hour, minute) = time {
            components.hour = hour
            components.minute = minute
        } else {
            // Без времени задача «висит весь день»: срок — конец дня.
            components.hour = 23
            components.minute = 59
        }
        return calendar.date(from: components)
    }

    private static func title(from input: String, removing ranges: [Range<String.Index>]) -> String {
        var result = ""
        var index = input.startIndex
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where range.lowerBound >= index {
            result += input[index..<range.lowerBound]
            index = max(index, range.upperBound)
        }
        result += input[index...]
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t,−–—-"))
    }
}
