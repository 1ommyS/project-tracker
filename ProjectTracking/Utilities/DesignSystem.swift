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

enum PulseStyle {
    static let blue = Color(red: 0.12, green: 0.42, blue: 0.98)
    static let indigo = Color(red: 0.26, green: 0.20, blue: 0.82)
    static let mint = Color(red: 0.16, green: 0.86, blue: 0.72)
    static let amber = Color(red: 1.0, green: 0.64, blue: 0.18)
    static let cardRadius: CGFloat = 20
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

struct PageBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [PulseStyle.blue.opacity(colorScheme == .dark ? 0.13 : 0.075), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 270
            )
            .frame(width: 540, height: 540)
            .offset(x: 370, y: -300)
            RadialGradient(
                colors: [PulseStyle.mint.opacity(colorScheme == .dark ? 0.075 : 0.045), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 230
            )
            .frame(width: 460, height: 460)
            .offset(x: -420, y: 350)
        }
        .ignoresSafeArea()
    }
}

struct BrandIcon: View {
    var size: CGFloat = 42
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: PulseStyle.blue.opacity(0.25), radius: size * 0.2, y: size * 0.08)
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

    func pulsePanel(radius: CGFloat = PulseStyle.cardRadius) -> some View {
        self
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.055), radius: 18, y: 8)
    }
}
