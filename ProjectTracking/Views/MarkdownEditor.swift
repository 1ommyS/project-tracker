import AppKit
import SwiftUI

// MARK: - NSTextView с выбором диапазона

/// Многострочное поле для Markdown-редактора: сообщает выделение,
/// чтобы кнопки тулбара оборачивали выбранный текст.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var onFocusChange: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.string = text
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selection = textView.selectedRange
            parent.onFocusChange?()
        }
    }
}

// MARK: - Markdown-редактор

/// Редактор Markdown с тулбаром: обёртка выделения (**, *, ~~, `),
/// префиксы строк (##, -, - [ ], >), вставка ссылки и предпросмотр.
struct MarkdownEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 110

    @State private var selection = NSRange(location: 0, length: 0)
    @State private var showsPreview = false
    @State private var commitTask: Task<Void, Never>?
    var onCommit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolbar
            Divider()
            if showsPreview {
                ScrollView {
                    Text(rendered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .frame(minHeight: minHeight)
            } else if text.isEmpty {
                ZStack(alignment: .topLeading) {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                    editor
                }
            } else {
                editor
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var editor: some View {
        MarkdownTextEditor(text: $text, selection: $selection)
            .frame(minHeight: text.isEmpty ? minHeight : nil, alignment: .topLeading)
            .onChange(of: text) { _, _ in scheduleCommit() }
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            ToolButton("bold", help: "Жирный") { wrap("**", placeholder: "жирный") }
            ToolButton("italic", help: "Курсив") { wrap("*", placeholder: "курсив") }
            ToolButton("strikethrough", help: "Зачёркнутый") { wrap("~~", placeholder: "зачёркнутый") }
            ToolButton("chevron.left.forwardslash.chevron.right", help: "Код") { wrap("`", placeholder: "код") }
            toolDivider
            ToolButton("textformat.size", help: "Заголовок") { prefixLine("## ") }
            ToolButton("list.bullet", help: "Список") { prefixLine("- ") }
            ToolButton("checklist", help: "Чекбокс") { prefixLine("- [ ] ") }
            ToolButton("text.quote", help: "Цитата") { prefixLine("> ") }
            toolDivider
            ToolButton("link", help: "Ссылка") { insertLink() }
            Spacer(minLength: 6)
            ToolButton(showsPreview ? "pencil.line" : "eye",
                       help: showsPreview ? "К редактору" : "Предпросмотр Markdown",
                       tint: .secondary) { showsPreview.toggle() }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.separator.opacity(0.35)))
    }

    private var toolDivider: some View {
        Rectangle().fill(.separator.opacity(0.5)).frame(width: 1, height: 14).padding(.horizontal, 3)
    }

    // MARK: Операции с текстом

    private func wrap(_ marker: String, placeholder template: String) {
        let view = NSString(string: text)
        let range = selection.clamped(to: view.length)
        let selected = view.substring(with: range)
        let inner = selected.isEmpty ? template : selected
        let replacement = marker + inner + marker
        replace(range: range, with: replacement,
                select: NSRange(location: range.location + marker.count, length: inner.count))
    }

    private func prefixLine(_ prefix: String) {
        let view = NSString(string: text)
        let range = selection.clamped(to: view.length)
        let lineStart = max(0, (text as NSString).lineRange(for: NSRange(location: range.location, length: 0)).location)
        replace(range: NSRange(location: lineStart, length: 0), with: prefix, select: nil)
    }

    private func insertLink() {
        let view = NSString(string: text)
        let range = selection.clamped(to: view.length)
        let selected = view.substring(with: range)
        let title = selected.isEmpty ? "ссылка" : selected
        let replacement = "[\(title)](https://)"
        let selectTitle = NSRange(location: range.location + 1, length: title.count)
        let selectURL = NSRange(location: range.location + title.count + 3, length: "https://".count)
        replace(range: range, with: replacement, select: range.length == 0 ? selectURL : selectTitle)
    }

    /// Замена диапазона с восстановлением выделения после пересборки строки.
    private func replace(range: NSRange, with replacement: String, select: NSRange?) {
        let view = NSString(string: text)
        let updated = view.replacingCharacters(in: range, with: replacement)
        text = updated
        DispatchQueue.main.async {
            selection = select ?? NSRange(location: range.location + replacement.count, length: 0)
        }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onCommit?()
        }
    }
}

/// Иконка внутри стеклянной полосы: без собственной кнопочной
/// графике, hover — тихий кружок, как в системных тулбарах.
struct ToolButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = .primary
    var action: () -> Void
    @State private var isHovering = false

    init(_ symbol: String, help: String = "", tint: Color = .primary, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 28, height: 24)
                .foregroundStyle(tint)
                .background {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quinary)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help.isEmpty ? symbol : help)
    }
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        let location = Swift.min(self.location, length)
        let upper = Swift.min(location + self.length, length)
        return NSRange(location: location, length: upper - location)
    }
}
