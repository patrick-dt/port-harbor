/// Official-style framework marks as vectors (Astro, Next.js) plus Sanity raster.
///
/// Chat image drops land as PNG; Astro/Next ship as SwiftUI paths (true vectors at
/// any scale) with matching `.svg` sources under Resources/FrameworkIcons for
/// editing. Sanity is raster-only (provided as PNG).
import AppKit
import SwiftUI

// MARK: - Badge

struct FrameworkBadge: View {
    let framework: Framework

    private let side: CGFloat = 16

    var body: some View {
        Group {
            if framework.hasVectorMark {
                framework.vectorMark
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else if let image = framework.rasterImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else if let monogram = framework.monogram {
                Text(monogram)
                    .font(.system(size: monogram.count > 1 ? 7.5 : 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(framework.badgeForeground)
                    .frame(width: side, height: side)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(framework.badgeBackground)
                    )
            }
        }
        .accessibilityHidden(true)
        .help(framework.label ?? "")
    }
}

extension Framework {
    /// Vector SwiftUI mark when we have a path-based logo.
    @ViewBuilder
    var vectorMark: some View {
        switch self {
        case .nextjs:
            NextJSLogoMark()
        case .astro:
            AstroLogoMark()
        default:
            EmptyView()
        }
    }

    var hasVectorMark: Bool {
        switch self {
        case .nextjs, .astro: return true
        default: return false
        }
    }

    /// Bundled PNG for frameworks without a vector mark (Sanity).
    var rasterImage: NSImage? {
        guard let name = rasterResourceName else { return nil }
        return FrameworkIconResources.image(named: name)
    }

    var rasterResourceName: String? {
        switch self {
        case .sanity: return "framework-sanity"
        default: return nil
        }
    }
}

// MARK: - Resource loading

enum FrameworkIconResources {
    static func image(named name: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "FrameworkIcons")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        {
            return NSImage(contentsOf: url)
        }
        // Packaged .app: resources copied next to the executable as SPM bundle,
        // or flat into Contents/Resources.
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "FrameworkIcons")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: name)
    }
}

// MARK: - Next.js (vector)

/// Black tile + white Next.js “N” (diagonal overhang), drawn as paths.
struct NextJSLogoMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                    .fill(Color.black)
                NextJSLetterN()
                    .fill(Color.white)
                    .padding(s * 0.18)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct NextJSLetterN: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let t = w * 0.22 // stem thickness
        var path = Path()

        // Left stem
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: t, height: h))
        // Right stem
        path.addRect(CGRect(x: rect.maxX - t, y: rect.minY, width: t, height: h))

        // Diagonal (top of left stem → bottom of right stem, with overhang)
        var d = Path()
        d.move(to: CGPoint(x: rect.minX + t * 0.85, y: rect.minY))
        d.addLine(to: CGPoint(x: rect.minX + t * 1.35, y: rect.minY))
        d.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - t * 0.35))
        d.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        d.addLine(to: CGPoint(x: rect.maxX - t * 0.9, y: rect.maxY))
        d.addLine(to: CGPoint(x: rect.minX + t * 0.85, y: rect.minY + t * 1.1))
        d.closeSubpath()
        path.addPath(d)
        return path
    }
}

// MARK: - Astro (vector)

/// Astro rocket-“A” with gradient exhaust — approximate brand mark as paths.
struct AstroLogoMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.18, style: .continuous)
                    .fill(Color.black)
                AstroMarkPaths()
                    .padding(s * 0.14)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct AstroMarkPaths: View {
    var body: some View {
        GeometryReader { geo in
            let r = geo.size
            ZStack {
                // White rocket body / “A” without crossbar
                AstroBodyShape()
                    .fill(Color.white)
                // Pink → orange exhaust
                AstroFlameShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.15, blue: 0.75),
                                Color(red: 1.0, green: 0.36, blue: 0.20),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .frame(width: r.width, height: r.height)
        }
    }
}

/// Upper white chevron / rocket body in a 0…1 viewBox mapped to `rect`.
private struct AstroBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        // Coordinates relative to Astro’s tall mark (body sits in upper ~62%).
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.50, y: y + h * 0.02))
        path.addLine(to: CGPoint(x: x + w * 0.86, y: y + h * 0.58))
        path.addLine(to: CGPoint(x: x + w * 0.70, y: y + h * 0.58))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.40),
            control: CGPoint(x: x + w * 0.58, y: y + h * 0.56)
        )
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.30, y: y + h * 0.58),
            control: CGPoint(x: x + w * 0.42, y: y + h * 0.56)
        )
        path.addLine(to: CGPoint(x: x + w * 0.14, y: y + h * 0.58))
        path.closeSubpath()
        return path
    }
}

private struct AstroFlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        var path = Path()
        // Two-lobed flame under the body gap
        path.move(to: CGPoint(x: x + w * 0.34, y: y + h * 0.62))
        path.addLine(to: CGPoint(x: x + w * 0.42, y: y + h * 0.62))
        path.addCurve(
            to: CGPoint(x: x + w * 0.36, y: y + h * 0.92),
            control1: CGPoint(x: x + w * 0.40, y: y + h * 0.72),
            control2: CGPoint(x: x + w * 0.28, y: y + h * 0.84)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.78),
            control1: CGPoint(x: x + w * 0.42, y: y + h * 0.96),
            control2: CGPoint(x: x + w * 0.48, y: y + h * 0.86)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.64, y: y + h * 0.92),
            control1: CGPoint(x: x + w * 0.52, y: y + h * 0.86),
            control2: CGPoint(x: x + w * 0.58, y: y + h * 0.96)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.58, y: y + h * 0.62),
            control1: CGPoint(x: x + w * 0.72, y: y + h * 0.84),
            control2: CGPoint(x: x + w * 0.60, y: y + h * 0.72)
        )
        path.addLine(to: CGPoint(x: x + w * 0.66, y: y + h * 0.62))
        path.addLine(to: CGPoint(x: x + w * 0.34, y: y + h * 0.62))
        path.closeSubpath()
        return path
    }
}
