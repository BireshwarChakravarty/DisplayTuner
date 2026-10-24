import AppKit
import SwiftUI
import TunerCore

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

    private var targets: [DisplayFacts] { model.displays.filter { $0.mirrorOf == nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Visual checks for banding, black and white clipping, sharpness and colour. They show through your current settings and don't change anything.")
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    ForEach(TestPattern.allCases) { pattern in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                PatternCanvas(pattern: pattern).frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                                Label(pattern.rawValue, systemImage: pattern.symbol).font(.headline)
                                Text(pattern.explanation).font(.callout).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                                Button("Show Full Screen") { PatternPresenter.shared.show(pattern, displayID: model.selectedID) }
                                    .disabled(model.isDemo || model.selectedDisplay?.mirrorOf != nil || model.selectedID == nil)
                            }
                            .padding(4)
                        }
                    }
                }
                Text("Press Esc to close a full-screen pattern. These are visual checks, not a substitute for a colorimeter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Test Patterns")
        .toolbar {
            ToolbarItem {
                Picker("Show on", selection: $model.selectedID) {
                    ForEach(targets) { display in Text(display.name).tag(Optional(display.id)) }
                }
                .help("The display to show patterns on")
            }
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

private final class PatternWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    // A borderless window has nothing focused for SwiftUI's exit command, so
    // handle Esc here.
    override func cancelOperation(_ sender: Any?) { close() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }
}

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
