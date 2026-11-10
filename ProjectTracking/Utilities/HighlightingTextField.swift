import AppKit
import SwiftUI

/// Однострочное поле ввода с цветовой подсветкой диапазона текста —
/// для визуализации распознанного срока («завтра в 18:00»).
/// Обычный SwiftUI TextField рендерит только плоский текст, поэтому
/// здесь NSTextView с обновлением атрибутов на лету.
struct HighlightingTextField: NSViewRepresentable {
    @Binding var text: String
    var highlightRange: Range<String.Index>?
    var accent: NSColor = .controlAccentColor
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // Однострочное поведение: строка уходит за край, а не переносится.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.applyHighlight(to: textView, fullText: text, range: highlightRange)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.string != text, !textView.hasMarkedText() {
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selected.clamped(to: text.utf16.count))
        }
        guard !textView.hasMarkedText() else { return }
        context.coordinator.applyHighlight(to: textView, fullText: text, range: highlightRange)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextField
        private var previousText: String?
        private var previousRange: NSRange?
        private var previousAccent: NSColor?

        init(_ parent: HighlightingTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }

        func applyHighlight(to textView: NSTextView, fullText: String, range: Range<String.Index>?) {
            let length = (fullText as NSString).length
            guard length == (textView.string as NSString).length else { return }

            let highlight = range.map { NSRange($0, in: fullText) }
            guard previousText != fullText || previousRange != highlight || previousAccent != parent.accent else { return }
            guard let storage = textView.textStorage else { return }
            previousText = fullText
            previousRange = highlight
            previousAccent = parent.accent
            storage.beginEditing()
            defer { storage.endEditing() }
            let whole = NSRange(location: 0, length: length)
            let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            storage.removeAttribute(.foregroundColor, range: whole)
            storage.removeAttribute(.font, range: whole)
            storage.addAttribute(.font, value: baseFont, range: whole)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: whole)

            if let range {
                let nsRange = NSRange(range, in: fullText)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold), range: nsRange)
                storage.addAttribute(.foregroundColor, value: parent.accent, range: nsRange)
            }

            // Печать продолжается обычным стилем, даже если курсор внутри подсветки.
            textView.typingAttributes = [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ]
        }
    }
}
