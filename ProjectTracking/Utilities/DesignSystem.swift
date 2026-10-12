import AppKit
import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maximumWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > width {
                maximumWidth = max(maximumWidth, lineWidth)
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth == 0 ? 0 : spacing) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }
        return CGSize(width: min(width, max(maximumWidth, lineWidth)), height: totalHeight + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct FadeContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FadeViewportWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct FadeOverflowRow<Content: View>: View {
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @ViewBuilder let content: () -> Content

    private var isOverflowing: Bool { contentWidth > viewportWidth + 2 }

    var body: some View {
        ScrollView(.horizontal) {
            content()
                .fixedSize(horizontal: true, vertical: false)
                .background(GeometryReader { Color.clear.preference(key: FadeContentWidthKey.self, value: $0.size.width) })
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { Color.clear.preference(key: FadeViewportWidthKey.self, value: $0.size.width) })
        .onPreferenceChange(FadeContentWidthKey.self) { contentWidth = $0 }
        .onPreferenceChange(FadeViewportWidthKey.self) { viewportWidth = $0 }
        .mask {
            if isOverflowing {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
            } else {
                Rectangle().fill(.black)
            }
        }
    }
}

private struct SoftScrollFadeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Единые метрики вёрстки: экраны и листы — 24pt, карточки — 18pt.
enum PulseMetrics {
    static let screen: CGFloat = 24
    static let card: CGFloat = 18
    static let contentWidth: CGFloat = 1000
}

enum PulseStyle {
    // Системная палитра: приложение наследует акценты и appearance macOS.
    static let blue = Color.blue
    static let indigo = Color.indigo
    static let mint = Color.mint
    static let amber = Color.orange
    static let cardRadius: CGFloat = 12
}

enum ThemeController {
    @MainActor static func apply(_ theme: AppTheme) {
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.windows.forEach { window in
            window.appearance = theme == .system ? nil : NSApp.appearance
            window.contentView?.needsDisplay = true
        }
    }
}


struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.2).foregroundStyle(.tertiary)
    }
}

extension View {
    func softScrollFade() -> some View { modifier(SoftScrollFadeModifier()) }

    func screenPadding(_ edges: Edge.Set = .all) -> some View { padding(edges, PulseMetrics.screen) }
    func cardPadding(_ edges: Edge.Set = .all) -> some View { padding(edges, PulseMetrics.card) }

    /// Ограничивает ширину до контентной колонки — хедер и контент одной ширины.
    func pageWidth() -> some View { frame(maxWidth: PulseMetrics.contentWidth, alignment: .leading) }

    /// Курсор-рука при наведении — для кликабельных карточек и ссылок-строк.
    /// На выходе дополнительно ставим стрелку: push/pop может разладиться
    /// с системным I-beam текстовых полей, и курсор «залипает».
    func pointingHandOnHover() -> some View { modifier(PointingHandHoverModifier()) }

    /// Возврат стрелки при уходе курсора с поля ввода — системный I-beam
    /// после выхода из SwiftUI-редакторов иногда остаётся висеть.
    func arrowCursorOnExit() -> some View { modifier(ArrowCursorOnExitModifier()) }

    func pulsePanel(radius: CGFloat = PulseStyle.cardRadius) -> some View {
        // Группированная карточка в духе системных inset-секций:
        // без теней и обводок, тихая подложка на фоне окна.
        self
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private struct PointingHandHoverModifier: ViewModifier {
    @State private var didPush = false

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
                didPush = true
            } else {
                if didPush { NSCursor.pop() }
                didPush = false
                NSCursor.arrow.set()
            }
        }
    }
}

private struct ArrowCursorOnExitModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if !hovering {
                NSCursor.arrow.set()
            }
        }
    }
}
