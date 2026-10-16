import SwiftUI

// Explicit property-wrapper alias also supports SDKs that add a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Color {
    static let studioCyan = Color(red: 0.28, green: 0.86, blue: 0.96)
    static let studioViolet = Color(red: 0.57, green: 0.48, blue: 1)
}

struct StudioGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.12)))
        }
    }
}

struct StudioGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: 12) { content() } }
        else { content() }
    }
}

struct StudioCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.07)))
    }
}

struct StudioBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.045, green: 0.055, blue: 0.085) : Color(red: 0.94, green: 0.96, blue: 0.98))
            GeometryReader { g in
                RadialGradient(colors: [Color.studioCyan.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: g.size.width * 0.8)
                RadialGradient(colors: [Color.studioViolet.opacity(0.07), .clear], center: .trailing, startRadius: 0, endRadius: g.size.width * 0.6)
            }.accessibilityHidden(true)
        }.ignoresSafeArea()
    }
}

struct StatusPill: View {
    var text: String
    var color: Color = .studioCyan
    var body: some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.system(size: 10, weight: .semibold)) }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
            .foregroundStyle(color)
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.8).foregroundStyle(.secondary) }
}

struct StudioButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(prominent ? Color.black : Color.primary)
            .background(prominent ? Color.studioCyan.opacity(configuration.isPressed ? 0.65 : 1) : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
