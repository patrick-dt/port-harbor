/// Bundled framework marks shown in the listener list.
///
/// Artwork lives in `Resources/FrameworkIcons/` and is drawn as-is. Astro’s
/// mark is white-on-transparent, so the badge sits it on a dark tile; Next.js
/// and Sanity already include their own background.
import AppKit
import SwiftUI

// MARK: - Badge

struct FrameworkBadge: View {
    let framework: Framework

    private let side: CGFloat = 16

    var body: some View {
        Group {
            if let image = framework.bundledMarkImage {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .padding(framework.markPadding)
                    .frame(width: side, height: side)
                    .background {
                        if framework.needsDarkMarkBacking {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.black)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: framework.markCornerRadius, style: .continuous))
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
    /// True when we ship a logo file for this framework (even if loading fails
    /// and the badge falls back to the monogram).
    var hasBundledMark: Bool { bundledMarkResource != nil }

    var bundledMarkImage: NSImage? {
        guard let resource = bundledMarkResource else { return nil }
        return FrameworkIconResources.image(named: resource.name, extension: resource.ext)
    }

    var bundledMarkResource: (name: String, ext: String)? {
        switch self {
        case .nextjs: return ("framework-nextjs", "svg")
        case .astro: return ("framework-astro", "svg")
        case .sanity: return ("framework-sanity", "png")
        default: return nil
        }
    }

    /// Astro’s SVG is a white mark with no fill behind it.
    var needsDarkMarkBacking: Bool { self == .astro }

    var markPadding: CGFloat {
        switch self {
        case .astro: return 1.5
        default: return 0
        }
    }

    /// Next.js is already a circle; rounding it again clips the mark.
    var markCornerRadius: CGFloat {
        switch self {
        case .nextjs: return 0
        default: return 4
        }
    }
}

// MARK: - Resource loading

enum FrameworkIconResources {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String, extension ext: String) -> NSImage? {
        let key = "\(name).\(ext)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = url(named: name, extension: ext) else { return nil }
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        image.isTemplate = false
        cache.setObject(image, forKey: key)
        return image
    }

    static func url(named name: String, extension ext: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "FrameworkIcons")
            ?? Bundle.module.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "FrameworkIcons")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
