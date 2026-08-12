import SwiftUI

/// Penpot's animated pencil loader, rebuilt natively from the web app's own SVG
/// (`icon-loader`, viewBox 677.348 × 182.154) and its CSS animation: the middle bar
/// translates upward by 150 units in a 0.8 s linear infinite loop. The bar starts and
/// ends inside the pencil's solid frame bands, so the loop's jump-back is invisible —
/// it reads as an endless line sweeping through the hollow pencil body.
struct PencilLoaderView: View {
    var color: Color = .penpotIconGray

    @State private var sweeping = false

    private static let viewBox = CGSize(width: 677.348, height: 182.154)

    var body: some View {
        ZStack {
            PencilShape()
                // Even-odd keeps the body hollow and the tip cut out regardless of
                // subpath winding.
                .fill(color, style: FillStyle(eoFill: true))
            SweepLineShape(phase: sweeping ? 1 : 0)
                .fill(color)
        }
        .aspectRatio(Self.viewBox.width / Self.viewBox.height, contentMode: .fit)
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                sweeping = true
            }
        }
        .accessibilityLabel("Loading…")
    }

    private static func scale(for rect: CGRect) -> CGFloat {
        min(rect.width / viewBox.width, rect.height / viewBox.height)
    }
}

/// The pencil loader inside the floating material badge used by busy overlays
/// ("Loading page…", "Preparing download…", "Importing…").
struct PencilLoadingBadge: View {
    let message: Text

    var body: some View {
        VStack(spacing: 12) {
            PencilLoaderView()
                .frame(width: 90)
            message
                .font(.workSans(.callout))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension PencilLoaderView {

    /// The pencil outline: outer frame incl. the tip, with the body's hollow and the
    /// tip cutout as inner subpaths. Coordinates are the SVG's, mapped into `rect`.
    /// (`SwiftUI.Shape` spelled out — the API models define their own `Shape` type.)
    private struct PencilShape: SwiftUI.Shape {
        func path(in rect: CGRect) -> Path {
            let s = PencilLoaderView.scale(for: rect)
            var path = Path()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
            }
            // Outer frame with tip (m128.273 0 … z).
            path.move(to: point(128.273, 0))
            path.addLine(to: point(124.373, 2.77))
            path.addLine(to: point(0, 91.078))
            path.addLine(to: point(128.273, 182.154))
            path.addLine(to: point(677.348, 182.148))
            path.addLine(to: point(677.348, 0.008))
            path.closeSubpath()
            // Hollow body (m20.852 30 … z).
            path.move(to: point(149.125, 30))
            path.addLine(to: point(647.348, 30.006))
            path.addLine(to: point(647.348, 152.15))
            path.addLine(to: point(149.125, 152.157))
            path.closeSubpath()
            // Tip cutout (m-25 9.74 … z).
            path.move(to: point(124.125, 39.74))
            path.addLine(to: point(124.125, 142.418))
            path.addLine(to: point(75.092, 107.605))
            path.addLine(to: point(74.514, 74.965))
            path.closeSubpath()
            return path
        }
    }

    /// The sweeping bar (M134.482 157.147 v25 h~518.57 z), shifted up by up to 150
    /// viewBox units as `phase` goes 0 → 1 — the exact web keyframes.
    private struct SweepLineShape: SwiftUI.Shape {
        var phase: CGFloat

        var animatableData: CGFloat {
            get { phase }
            set { phase = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let s = PencilLoaderView.scale(for: rect)
            let offset = -150 * phase
            var path = Path()
            path.addRect(CGRect(x: rect.minX + 134.482 * s,
                                y: rect.minY + (157.147 + offset) * s,
                                width: (653.052 - 134.482) * s,
                                height: 25 * s))
            return path
        }
    }
}
