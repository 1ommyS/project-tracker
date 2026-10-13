import AppKit
import SwiftUI

// MARK: - NSTextView с выбором диапазона

/// Многострочное поле для Markdown-редактора: сообщает и принимает
/// выделение, чтобы кнопки тулбара оборачивали выбранный текст.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

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
            let keep = textView.selectedRange
            textView.string = text
            let length = (text as NSString).length
            if keep.location != NSNotFound, keep.location <= length {
                textView.setSelectedRange(keep.clamped(to: length))
            }
        }
        // Синхронизируем выделение (после действий тулбара), остерегаясь цикла.
        let length = (text as NSString).length
        if !NSEqualRanges(textView.selectedRange, selection),
           selection.location != NSNotFound,
           selection.location + selection.length <= length {
            textView.setSelectedRange(selection)
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
            if !NSEqualRanges(textView.selectedRange, parent.selection) {
                parent.selection = textView.selectedRange
            }
        }
    }
}

// MARK: - Markdown-редактор

/// Редактор Markdown с тулбаром. Поле живёт в стабильной раскладке
/// (высота не зависит от пустоты), предпросмотр накрывает его сверху,
/// не пересоздавая — состояние и фокус не теряются.
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
            ZStack(alignment: .topLeading) {
                MarkdownTextEditor(text: $text, selection: $selection)
                    .frame(minHeight: minHeight, alignment: .topLeading)
                    .opacity(showsPreview ? 0 : 1)
                    .allowsHitTesting(!showsPreview)
                    .onChange(of: text) { _, _ in scheduleCommit() }

                if text.isEmpty && !showsPreview {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                }

                if showsPreview {
                    ScrollView {
                        Text(rendered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                    }
                    .frame(minHeight: minHeight)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.separator.opacity(0.3)))
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            ToolButton("bold", help: "Жирный") { apply { MarkdownTextOps.wrap($0, range: $1, marker: "**", placeholder: "жирный") } }
            ToolButton("italic", help: "Курсив") { apply { MarkdownTextOps.wrap($0, range: $1, marker: "*", placeholder: "курсив") } }
            ToolButton("strikethrough", help: "Зачёркнутый") { apply { MarkdownTextOps.wrap($0, range: $1, marker: "~~", placeholder: "зачёркнутый") } }
            ToolButton("chevron.left.forwardslash.chevron.right", help: "Код") { apply { MarkdownTextOps.wrap($0, range: $1, marker: "`", placeholder: "код") } }
            toolDivider
            ToolButton("textformat.size", help: "Заголовок") { apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "## ") } }
            ToolButton("list.bullet", help: "Список") { apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "- ") } }
            ToolButton("checklist", help: "Чекбокс") { apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "- [ ] ") } }
            ToolButton("text.quote", help: "Цитата") { apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "> ") } }
            toolDivider
            ToolButton("link", help: "Ссылка") { apply { MarkdownTextOps.insertLink($0, range: $1) } }
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

    /// Применяет чистую операцию к текущему тексту и выделению.
    private func apply(_ operation: (String, NSRange) -> (String, NSRange)) {
        let (updatedText, updatedSelection) = operation(text, selection)
        text = updatedText
        selection = updatedSelection
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
/// графики, hover — тихий кружок, как в системных тулбарах.
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
