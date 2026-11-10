import Foundation

nonisolated enum MarkdownTextOps {
    static func wrap(_ text: String, range: NSRange, marker: String, placeholder: String) -> (text: String, selection: NSRange) {
        let view = text as NSString
        let range = range.clamped(to: view.length)
        let markerLength = marker.utf16.count
        if range.location >= markerLength,
           range.location + range.length + markerLength <= view.length,
           view.substring(with: NSRange(location: range.location - markerLength, length: markerLength)) == marker,
           view.substring(with: NSRange(location: range.location + range.length, length: markerLength)) == marker {
            let selected = view.substring(with: range)
            let updated = view.replacingCharacters(in: NSRange(location: range.location - markerLength,
                                                               length: range.length + 2 * markerLength), with: selected)
            return (updated, NSRange(location: range.location - markerLength, length: range.length))
        }
        let selected = view.substring(with: range)
        let inner = selected.isEmpty ? placeholder : selected
        return (view.replacingCharacters(in: range, with: marker + inner + marker),
                NSRange(location: range.location + markerLength, length: inner.utf16.count))
    }

    static func prefixLine(_ text: String, range: NSRange, prefix: String) -> (text: String, selection: NSRange) {
        let view = text as NSString
        let range = range.clamped(to: view.length)
        // Выделение, закончившееся в начале следующей строки, не включает её.
        let covered = NSRange(location: range.location, length: max(0, range.length - 1))
        let lines = view.lineRange(for: covered)
        let source = view.substring(with: lines)
        var pieces = source.components(separatedBy: "\n")
        let count = pieces.count - (source.hasSuffix("\n") ? 1 : 0)
        for index in 0..<count { pieces[index] = prefix + pieces[index] }
        let result = view.replacingCharacters(in: lines, with: pieces.joined(separator: "\n"))
        let added = prefix.utf16.count
        return (result, NSRange(location: range.location + added,
                                length: range.length == 0 ? 0 : range.length + added * max(0, count - 1)))
    }

    static func insertLink(_ text: String, range: NSRange) -> (text: String, selection: NSRange) {
        let view = text as NSString
        let range = range.clamped(to: view.length)
        let selected = view.substring(with: range)
        let title = selected.isEmpty ? "ссылка" : selected
        let replacement = "[\(title)](https://)"
        let selection = selected.isEmpty
            ? NSRange(location: range.location + title.utf16.count + 3, length: "https://".utf16.count)
            : NSRange(location: range.location + 1, length: title.utf16.count)
        return (view.replacingCharacters(in: range, with: replacement), selection)
    }
}

extension NSRange {
    nonisolated func clamped(to length: Int) -> NSRange {
        let limit = max(0, length)
        let start = location == NSNotFound ? limit : min(max(0, location), limit)
        return NSRange(location: start, length: min(max(0, self.length), limit - start))
    }
}
