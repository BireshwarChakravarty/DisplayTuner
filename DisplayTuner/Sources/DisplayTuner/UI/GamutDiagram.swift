import SwiftUI
import TunerCore

/// CIE 1931 xy chromaticity diagram: the spectral locus, the sRGB and Display
/// P3 triangles, and the display's own gamut (from its active profile).
struct GamutDiagram: View {
    let primaries: Primaries?

    /// The spectral locus, 380–700 nm (CIE 1931 2° observer).
    private static let locus: [(Double, Double)] = [
        (0.1741, 0.0050), (0.1733, 0.0048), (0.1714, 0.0051), (0.1644, 0.0109), (0.1566, 0.0177),
        (0.1440, 0.0297), (0.1241, 0.0578), (0.1096, 0.0868), (0.0913, 0.1327), (0.0687, 0.2007),
        (0.0454, 0.2950), (0.0235, 0.4127), (0.0082, 0.5384), (0.0039, 0.6548), (0.0139, 0.7502),
        (0.0389, 0.8120), (0.0743, 0.8338), (0.1142, 0.8262), (0.1547, 0.8059), (0.2296, 0.7543),
        (0.3016, 0.6923), (0.3731, 0.6245), (0.4441, 0.5547), (0.5125, 0.4866), (0.5752, 0.4242),
        (0.6270, 0.3725), (0.6915, 0.3083), (0.7190, 0.2809), (0.7347, 0.2653)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                func point(_ x: Double, _ y: Double) -> CGPoint {
                    CGPoint(x: 8 + x / 0.8 * (size.width - 16), y: size.height - 8 - y / 0.9 * (size.height - 16))
                }
                func triangle(_ p: Primaries) -> Path {
                    Path { path in
                        path.move(to: point(p.red.x, p.red.y))
                        path.addLine(to: point(p.green.x, p.green.y))
                        path.addLine(to: point(p.blue.x, p.blue.y))
                        path.closeSubpath()
                    }
                }

                // Spectral locus, filled with a soft spectrum.
                let locus = Path { path in
                    for (index, sample) in Self.locus.enumerated() {
                        let p = point(sample.0, sample.1)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                }
                context.fill(locus, with: .conicGradient(
                    Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red].map { $0.opacity(0.28) }),
                    center: point(0.33, 0.33), angle: .degrees(-20)))
                context.stroke(locus, with: .color(.secondary.opacity(0.6)), lineWidth: 1)

                context.stroke(triangle(.displayP3), with: .color(.orange), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                context.stroke(triangle(.sRGB), with: .color(.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                if let primaries {
                    context.fill(triangle(primaries), with: .color(.accentColor.opacity(0.18)))
                    context.stroke(triangle(primaries), with: .color(.accentColor), lineWidth: 2)
                    if let white = primaries.white {
                        context.fill(Path(ellipseIn: CGRect(origin: point(white.x, white.y), size: .zero).insetBy(dx: -2.5, dy: -2.5)),
                                     with: .color(.primary))
                    }
                }
            }
            .aspectRatio(0.95, contentMode: .fit)
            .accessibilityLabel(accessibilityText)

            HStack(spacing: 12) {
                legend("This display", .accentColor, dash: false)
                legend("sRGB", .primary.opacity(0.7), dash: true)
                legend("P3", .orange, dash: true)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(_ title: String, _ color: Color, dash: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: dash ? 8 : 12, height: 2)
            Text(title)
        }
    }

    private var accessibilityText: String {
        guard let primaries else { return "Colour gamut diagram. This display's gamut is unknown." }
        return "Colour gamut diagram. This display covers \(Int((primaries.coverage(of: .sRGB) * 100).rounded())) percent of sRGB and \(Int((primaries.coverage(of: .displayP3) * 100).rounded())) percent of Display P3."
    }
}
