import AppKit
import SwiftUI

@MainActor
final class MarkdownEditorController {
    weak var textView: NSTextView?

    func apply(_ operation: (String, NSRange) -> (text: String, selection: NSRange)) {
        guard let textView, textView.isEditable else { return }
        let result = operation(textView.string, textView.selectedRange())
        textView.window?.makeFirstResponder(textView)
        // insertText проходит через стандартный механизм ввода AppKit и Undo.
        textView.insertText(result.text, replacementRange: NSRange(location: 0, length: textView.string.utf16.count))
        textView.setSelectedRange(result.selection.clamped(to: textView.string.utf16.count))
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

/// NSTextView обязательно живёт в NSScrollView: длинный текст переносится
/// по ширине и прокручивается, а курсор остаётся в видимой области.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var isEditing = true
    var autofocus = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = isEditing
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Текст Markdown")
        scrollView.documentView = textView
        controller.textView = textView
        if autofocus && isEditing {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.window?.firstResponder !== textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        controller.textView = textView
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selection.clamped(to: text.utf16.count))
            textView.undoManager?.removeAllActions()
        }
        let becameEditable = !textView.isEditable && isEditing
        textView.isEditable = isEditing
        if becameEditable, autofocus {
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
        if !isEditing, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

struct MarkdownEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 110
    var autofocus = false
    var isActive = true
    @State private var controller = MarkdownEditorController()
    @State private var showsPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Markdown").foregroundStyle(.secondary); Spacer(); modePicker }
                modePicker
            }
            toolbar
                .disabled(showsPreview)
            Divider()
            ZStack(alignment: .topLeading) {
                MarkdownTextEditor(text: $text, controller: controller, isEditing: !showsPreview && isActive, autofocus: autofocus)
                    .frame(height: minHeight)
                    .opacity(showsPreview ? 0 : 1)
                    .allowsHitTesting(!showsPreview)
                    .accessibilityHidden(showsPreview)
                if text.isEmpty && !showsPreview {
                    Text(placeholder).foregroundStyle(.tertiary)
                        .padding(.horizontal, 4).padding(.top, 6)
                        .allowsHitTesting(false)
                }
                if showsPreview {
                    ScrollView {
                        MarkdownPreview(text: text.isEmpty ? "Нет текста для просмотра" : text).equatable()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: minHeight)
                    .background(.background)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var modePicker: some View {
        Picker("Режим редактора", selection: $showsPreview) {
            Text("Редактор").tag(false)
            Text("Просмотр").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var toolbar: some View {
        FlowLayout(spacing: 4) {
            ToolButton("bold", help: "Жирный") { controller.apply { MarkdownTextOps.wrap($0, range: $1, marker: "**", placeholder: "жирный") } }
            ToolButton("italic", help: "Курсив") { controller.apply { MarkdownTextOps.wrap($0, range: $1, marker: "*", placeholder: "курсив") } }
            ToolButton("strikethrough", help: "Зачёркнутый") { controller.apply { MarkdownTextOps.wrap($0, range: $1, marker: "~~", placeholder: "зачёркнутый") } }
            ToolButton("chevron.left.forwardslash.chevron.right", help: "Код") { controller.apply { MarkdownTextOps.wrap($0, range: $1, marker: "`", placeholder: "код") } }
            ToolButton("textformat.size", help: "Заголовок") { controller.apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "### ") } }
            ToolButton("list.bullet", help: "Список") { controller.apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "- ") } }
            ToolButton("checklist", help: "Чекбокс") { controller.apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "- [ ] ") } }
            ToolButton("text.quote", help: "Цитата") { controller.apply { MarkdownTextOps.prefixLine($0, range: $1, prefix: "> ") } }
            ToolButton("link", help: "Ссылка") { controller.apply { MarkdownTextOps.insertLink($0, range: $1) } }
        }
    }
}

struct ToolButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = .primary
    var action: () -> Void

    init(_ symbol: String, help: String = "", tint: Color = .primary, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 30, height: 24)
                .foregroundStyle(tint)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Блочная разметка остаётся блочной: Text(AttributedString(markdown:))
/// сам по себе склеивает абзацы и не рисует заголовки и маркеры списков.
struct MarkdownPreview: View, Equatable {
    let text: String

    private struct Line: Identifiable {
        let id: Int
        let text: String
        let isCode: Bool
    }

    private var lines: [Line] {
        var fence: String?
        return text.components(separatedBy: .newlines).enumerated().compactMap { index, line in
            let next = MarkdownCodec.codeFence(after: line, current: fence)
            if next != fence { fence = next; return nil }
            return Line(id: index, text: line, isCode: fence != nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                if line.isCode {
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    formattedLine(line.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func formattedLine(_ line: String) -> some View {
        let hashes = line.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
            inline(String(line.dropFirst(hashes + 1)))
                .font(hashes <= 2 ? .title2.bold() : .headline)
        } else if line.hasPrefix("- [ ] ") || line.lowercased().hasPrefix("- [x] ") {
            HStack(alignment: .top) {
                Image(systemName: line.lowercased().hasPrefix("- [x]") ? "checkmark.square" : "square")
                inline(String(line.dropFirst(6)))
            }
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top) { Text("•"); inline(String(line.dropFirst(2))) }
        } else if line.hasPrefix("> ") {
            HStack(alignment: .top) { Text("│").foregroundStyle(.secondary); inline(String(line.dropFirst(2))) }
        } else {
            inline(line.isEmpty ? " " : line)
        }
    }

    private func inline(_ value: String) -> some View {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
             ?? AttributedString(value))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
