import Foundation

/// Чистые операции Markdown-редактора над (текст, выделение).
/// Выделены отдельно, чтобы покрывать модульными тестами.
enum MarkdownTextOps {
    static func wrap(_ text: String, range: NSRange, marker: String, placeholder: String) -> (text: String, selection: NSRange) {
        let view = text as NSString
        let clamped = range.clamped(to: view.length)
        let selected = view.substring(with: clamped)
        let inner = selected.isEmpty ? placeholder : selected
        let updated = view.replacingCharacters(in: clamped, with: marker + inner + marker)
        return (updated, NSRange(location: clamped.location + marker.count, length: inner.count))
    }

    static func prefixLine(_ text: String, range: NSRange, prefix: String) -> (text: String, selection: NSRange) {
        let view = text as NSString
        let clamped = range.clamped(to: view.length)
        let lineStart = view.lineRange(for: NSRange(location: clamped.location, length: 0)).location
        let updated = view.replacingCharacters(in: NSRange(location: lineStart, length: 0), with: prefix)
        // Курсор сохраняет позицию, сдвинутую на длину вставленного префикса.
        return (updated, NSRange(location: clamped.location + prefix.count + clamped.length, length: 0))
    }

    static func insertLink(_ text: String, range: NSRange) -> (text: String, selection: NSRange) {
        let view = text as NSString
        let clamped = range.clamped(to: view.length)
        let selected = view.substring(with: clamped)
        let title = selected.isEmpty ? "ссылка" : selected
        let replacement = "[\(title)](https://)"
        let selection: NSRange
        if selected.isEmpty {
            // Курсор на URL для замены: после "](" — выделяем https://
            selection = NSRange(location: clamped.location + title.count + 3, length: "https://".count)
        } else {
            // Выделен текст-название — оставляем выделение на нём.
            selection = NSRange(location: clamped.location + 1, length: title.count)
        }
        return (view.replacingCharacters(in: clamped, with: replacement), selection)
    }
}

extension NSRange {
    /// Безопасный диапазон внутри строки заданной длины.
    func clamped(to length: Int) -> NSRange {
        let location = Swift.min(self.location, length)
        let upper = Swift.min(location + self.length, length)
        return NSRange(location: location, length: upper - location)
    }
}
