import AppKit
import SwiftUI

 enum TestPattern: String, CaseIterable, Identifiable {
    case gradient = "Smooth gradient", grayscale = "Grayscale steps", black = "Shadow detail", white = "Highlight detail", grid = "Pixel grid", colours = "Colour bars"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .gradient: return "rainbow"; case .grayscale: return "rectangle.split.3x1"; case .black: return "moon"; case .white: return "sun.max"; case .grid: return "grid"; case .colours: return "paintpalette" }
    }
    var explanation: String {
        switch self {
        case .gradient: return "Look for smooth transitions without abrupt bands. Visible banding can come from the pipeline or the panel."
        case .grayscale: return "Each step should be distinct and neutral. A colour cast may indicate a white-point or profile mismatch."
        case .black: return "In a dim room, the near-black steps should gradually emerge from the background. Don’t raise contrast to reveal them."
        case .white: return "The near-white steps should remain distinct. If they merge, lower contrast or disable dynamic contrast."
        case .grid: return "Check line consistency and sharpness at your current desktop scaling. This is a logical-pixel grid, not a physical subpixel test."
        case .colours: return "Inspect for consistent colour across the panel. These are visual checks, not a substitute for measurement."
        }
    }
}

struct PatternLibraryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "See the difference", title: "Trust your eyes. Then verify.", subtitle: "Six visual checks for sharpness, clipping, gradients and colour consistency.")
                HStack(spacing: 12) {
                    Label("Target display", systemImage: "display").foregroundStyle(.secondary)
                    // A plain pop-up picker renders dark-on-dark over the studio backdrop; segments stay legible.
                    Picker("Target display", selection: $model.selectedID) {
                        ForEach(model.displays.filter { $0.mirrorOf == nil }) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }.font(.callout)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 16) {
                    ForEach(TestPattern.allCases) { pattern in
                        VStack(alignment: .leading, spacing: 14) {
                            PatternCanvas(pattern: pattern).frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                            Label(pattern.rawValue, systemImage: pattern.symbol).font(.system(size: 14, weight: .semibold))
                            Text(pattern.explanation).font(.system(size: 11)).foregroundStyle(.secondary).frame(minHeight: 48, alignment: .top)
                            Button { PatternPresenter.shared.show(pattern, displayID: model.selectedID) } label: { Label("Open full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                                .buttonStyle(StudioButton()).disabled(model.isDemo || model.selectedDisplay?.mirrorOf != nil || model.selectedID == nil)
                        }.padding(18).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                Text("Press Esc to close a full-screen pattern. Patterns use the current macOS colour pipeline and don’t change your display settings.").font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
}

struct PatternCanvas: View {
    let pattern: TestPattern
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            switch pattern {
            case .gradient:
                context.fill(Path(rect), with: .linearGradient(Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            case .grid:
                context.fill(Path(rect), with: .color(.white))
                var path = Path()
                for x in stride(from: CGFloat(0.5), to: size.width, by: 8) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                for y in stride(from: CGFloat(0.5), to: size.height, by: 8) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(path, with: .color(.black), lineWidth: 1)
            case .colours:
                let colors: [Color] = [.white, .yellow, .cyan, .green, Color(red: 1, green: 0, blue: 1), .red, .blue, .black]
                for i in colors.indices { context.fill(Path(CGRect(x: size.width * Double(i) / 8, y: 0, width: size.width / 8 + 1, height: size.height)), with: .color(colors[i])) }
            case .grayscale, .black, .white:
                let n = pattern == .grayscale ? 16 : 12
                context.fill(Path(rect), with: .color(pattern == .white ? .white : .black))
                for i in 0..<n {
                    let level: Double = pattern == .grayscale ? Double(i) / Double(n - 1) : pattern == .black ? Double(i) * 2 / 255 : (233 + Double(i) * 2) / 255
                    let inset: CGFloat = pattern == .grayscale ? 0 : size.height * 0.15
                    let block = CGRect(x: size.width * Double(i) / Double(n), y: inset, width: size.width / Double(n) + 0.5, height: size.height - inset * 2)
                    context.fill(Path(block), with: .color(Color(.sRGB, white: level, opacity: 1)))
                    if size.width > 700 {
                        context.draw(Text("\(Int((level * 255).rounded()))").font(.system(size: 13, design: .monospaced)).foregroundStyle(level > 0.5 ? .black : .white), at: CGPoint(x: block.midX, y: size.height - 25))
                    }
                }
            }
        }.drawingGroup(opaque: true, colorMode: .nonLinear)
    }
}

private final class PatternWindow: NSWindow { override var canBecomeKey: Bool { true } }

@MainActor
final class PatternPresenter {
    static let shared = PatternPresenter()
    private var window: NSWindow?
    func show(_ pattern: TestPattern, displayID: UInt32?) {
        guard let displayID, let screen = DisplayDetector.screen(for: displayID) else { return }
        window?.close()
        let w = PatternWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.setFrame(screen.frame, display: false)
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.contentView = NSHostingView(rootView: PatternCanvas(pattern: pattern).ignoresSafeArea().overlay(alignment: .topTrailing) {
            Button("Close pattern  ⎋") { [weak w] in w?.close() }.buttonStyle(.bordered).padding(20)
        }.onExitCommand { [weak w] in w?.close() })
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window = w
    }
}
