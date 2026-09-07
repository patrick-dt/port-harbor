import Foundation
import AppKit
import SwiftUI

enum Framework: String, CaseIterable {
    case nextjs = "Next.js"
    case vite = "Vite"
    case nuxt = "Nuxt"
    case astro = "Astro"
    case sanity = "Sanity"
    case remix = "Remix"
    case express = "Express"
    case django = "Django"
    case flask = "Flask"
    case rails = "Rails"
    case hugo = "Hugo"
    case gatsby = "Gatsby"
    case angular = "Angular"
    case svelte = "SvelteKit"
    case webpack = "Webpack"
    case esbuild = "esbuild"
    case parcel = "Parcel"
    case php = "PHP"
    case uvicorn = "Uvicorn"
    case fastapi = "FastAPI"
    case node = "Node"
    case python = "Python"
    case ruby = "Ruby"
    case unknown = "Unknown"

    /// Framework name for display, or `nil` when detection did not identify one.
    /// Callers omit the segment entirely rather than labelling a row "Unknown".
    var label: String? {
        self == .unknown ? nil : rawValue
    }

    /// Single-letter (or short) mark for the colored badge. `nil` for unknown —
    /// no placeholder glyph that would outweigh the port number.
    var monogram: String? {
        switch self {
        case .nextjs:  return "N"
        case .vite:    return "V"
        case .nuxt:    return "N"
        case .astro:   return "A"
        case .sanity:  return "S"
        case .remix:   return "R"
        case .express: return "E"
        case .django:  return "D"
        case .flask:   return "F"
        case .rails:   return "R"
        case .hugo:    return "H"
        case .gatsby:  return "G"
        case .angular: return "A"
        case .svelte:  return "S"
        case .webpack: return "W"
        case .esbuild: return "es"
        case .parcel:  return "P"
        case .php:     return "P"
        case .uvicorn: return "U"
        case .fastapi: return "F"
        case .node:    return "JS"
        case .python:  return "Py"
        case .ruby:    return "Rb"
        case .unknown: return nil
        }
    }

    /// Brand-tint fill for the monogram badge (appearance-aware where needed).
    var badgeBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch self {
            case .nextjs:
                // Next mark is black-on-white / white-on-black.
                return dark ? NSColor.white : NSColor.black
            case .vite:    return NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1) // #646CFF
            case .nuxt:    return NSColor(srgbRed: 0.00, green: 0.86, blue: 0.51, alpha: 1) // #00DC82
            case .astro:   return NSColor(srgbRed: 1.00, green: 0.36, blue: 0.01, alpha: 1) // #FF5D01
            case .sanity:  return NSColor(srgbRed: 0.94, green: 0.24, blue: 0.18, alpha: 1) // #F03E2F
            case .remix:   return dark
                ? NSColor(srgbRed: 0.85, green: 0.85, blue: 0.88, alpha: 1)
                : NSColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1)
            case .express: return NSColor(srgbRed: 0.26, green: 0.26, blue: 0.26, alpha: 1)
            case .django:  return NSColor(srgbRed: 0.04, green: 0.18, blue: 0.13, alpha: 1)
            case .flask:   return NSColor(srgbRed: 0.22, green: 0.22, blue: 0.24, alpha: 1)
            case .rails:   return NSColor(srgbRed: 0.80, green: 0.00, blue: 0.00, alpha: 1)
            case .hugo:    return NSColor(srgbRed: 1.00, green: 0.25, blue: 0.53, alpha: 1)
            case .gatsby:  return NSColor(srgbRed: 0.40, green: 0.20, blue: 0.60, alpha: 1)
            case .angular: return NSColor(srgbRed: 0.87, green: 0.00, blue: 0.19, alpha: 1)
            case .svelte:  return NSColor(srgbRed: 1.00, green: 0.24, blue: 0.00, alpha: 1)
            case .webpack: return NSColor(srgbRed: 0.55, green: 0.84, blue: 0.98, alpha: 1)
            case .esbuild: return NSColor(srgbRed: 1.00, green: 0.81, blue: 0.00, alpha: 1)
            case .parcel:  return NSColor(srgbRed: 0.13, green: 0.22, blue: 0.29, alpha: 1)
            case .php:     return NSColor(srgbRed: 0.47, green: 0.48, blue: 0.71, alpha: 1)
            case .uvicorn, .fastapi:
                return NSColor(srgbRed: 0.00, green: 0.59, blue: 0.53, alpha: 1)
            case .node:    return NSColor(srgbRed: 0.27, green: 0.69, blue: 0.29, alpha: 1)
            case .python:  return NSColor(srgbRed: 0.22, green: 0.46, blue: 0.67, alpha: 1)
            case .ruby:    return NSColor(srgbRed: 0.80, green: 0.20, blue: 0.18, alpha: 1)
            case .unknown: return NSColor.secondaryLabelColor
            }
        })
    }

    var badgeForeground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch self {
            case .nextjs:
                return dark ? NSColor.black : NSColor.white
            case .nuxt, .webpack, .esbuild:
                // Light fills need dark ink for contrast.
                return NSColor(srgbRed: 0.08, green: 0.10, blue: 0.12, alpha: 1)
            case .remix:
                return dark
                    ? NSColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1)
                    : NSColor.white
            default:
                return NSColor.white
            }
        })
    }
}

/// Compact colored monogram so frameworks are recognizable at a glance —
/// SF Symbols like `sparkles` read as generic chrome, not Astro/Next/Sanity.
struct FrameworkBadge: View {
    let framework: Framework

    var body: some View {
        if let monogram = framework.monogram {
            Text(monogram)
                .font(.system(size: monogram.count > 1 ? 7.5 : 9, weight: .heavy, design: .rounded))
                .foregroundStyle(framework.badgeForeground)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(framework.badgeBackground)
                )
                .accessibilityHidden(true)
                .help(framework.label ?? "")
        }
    }
}

struct FrameworkDetector {
    /// Detect framework from the full command line string returned by `ps`.
    ///
    /// Matching prefers path segments and whitespace-delimited tokens over raw
    /// substrings, so a project path containing `next` does not become Next.js.
    static func detect(from command: String) -> Framework {
        let lower = command.lowercased()

        // Order matters: more specific patterns first.

        // Next.js — require CLI/server markers, not merely the letters "next".
        if mentions(lower, "next-server")
            || mentions(lower, "next/dist")
            || hasPhrase(lower, "next dev")
            || hasPhrase(lower, "next start")
            || (mentions(lower, "next") && (hasPhrase(lower, "dev") || hasPhrase(lower, "start"))
                && mentionsAny(lower, "node", "npm", "npx", "yarn", "pnpm", "bun"))
        {
            return .nextjs
        }

        if mentionsAny(lower, "nuxt", "nuxi") {
            return .nuxt
        }

        if mentions(lower, "astro") {
            return .astro
        }

        // Sanity Studio / CLI (`sanity dev`, `@sanity/…`).
        if mentions(lower, "sanity") {
            return .sanity
        }

        if mentions(lower, "remix") {
            return .remix
        }

        if mentionsAny(lower, "svelte-kit", "sveltekit") || mentions(lower, "svelte") {
            return .svelte
        }

        // Vite — path/token only (after framework-specific detectors).
        if mentions(lower, "vite") {
            return .vite
        }

        if hasPhrase(lower, "ng serve") || mentions(lower, "@angular") {
            return .angular
        }

        if mentions(lower, "gatsby") {
            return .gatsby
        }

        if mentions(lower, "hugo") {
            return .hugo
        }

        if mentions(lower, "webpack") {
            return .webpack
        }

        if mentions(lower, "esbuild") {
            return .esbuild
        }

        if mentions(lower, "parcel") {
            return .parcel
        }

        // Express: require the package/module name, not merely "server".
        if mentions(lower, "express") {
            return .express
        }

        if mentions(lower, "manage.py") && hasPhrase(lower, "runserver") {
            return .django
        }

        if mentions(lower, "flask") {
            return .flask
        }

        if mentions(lower, "uvicorn") {
            return mentions(lower, "fastapi") ? .fastapi : .uvicorn
        }

        if mentions(lower, "php") && hasPhrase(lower, "-s") {
            return .php
        }

        if mentionsAny(lower, "rails", "puma") {
            return .rails
        }

        if mentionsAny(lower, "node", "npm", "npx", "tsx", "ts-node") {
            return .node
        }

        if mentionsAny(lower, "python", "python3") {
            return .python
        }

        if mentions(lower, "ruby") || hasPhrase(lower, "bundle exec") {
            return .ruby
        }

        return .unknown
    }

    /// Extract a human-readable project name from the working directory.
    static func projectName(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let url = URL(fileURLWithPath: cwd)
        let last = url.lastPathComponent
        guard !last.isEmpty, last != "/" else { return nil }
        return last
    }

    /// Build a concise subtitle like "Next.js · npm run dev".
    ///
    /// The PID is deliberately not part of this string: the subtitle is
    /// truncated to one line, and the PID is the identifier the confirmation
    /// dialogs refer to, so it gets its own slot in the row instead.
    static func subtitle(framework: Framework, fullCommand: String) -> String {
        let segments = [framework.label, shortCommand(fullCommand)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return segments.joined(separator: " · ")
    }

    static func shortCommand(_ cmd: String) -> String {
        // Try to extract the npm/yarn/pnpm script portion if present.
        // e.g. "/usr/local/bin/node /path/to/next dev" -> "next dev"
        // e.g. "npm run dev" -> "npm run dev"
        let parts = cmd.components(separatedBy: " ")

        // If command starts with npm/yarn/pnpm, keep it short
        if let first = parts.first {
            let base = URL(fileURLWithPath: first).lastPathComponent
            if ["npm", "yarn", "pnpm", "bun"].contains(base) {
                return parts.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // For node commands, try to show the script name
        if let first = parts.first {
            let base = URL(fileURLWithPath: first).lastPathComponent
            if base == "node", parts.count > 1 {
                let script = URL(fileURLWithPath: parts[1]).lastPathComponent
                let rest = parts.dropFirst(2).joined(separator: " ")
                let result = rest.isEmpty ? "\(base) \(script)" : "\(base) \(script) \(rest)"
                return String(result.prefix(50))
            }
        }

        // For python commands
        if let first = parts.first {
            let base = URL(fileURLWithPath: first).lastPathComponent
            if ["python", "python3"].contains(base) {
                return parts.map { URL(fileURLWithPath: $0).lastPathComponent }
                    .joined(separator: " ")
            }
        }

        // Generic: just truncate
        return String(cmd.prefix(50))
    }

    // MARK: - Token / path helpers

    /// True when `token` appears as a path segment or whitespace-delimited word.
    static func mentions(_ command: String, _ token: String) -> Bool {
        let t = token.lowercased()
        guard !t.isEmpty else { return false }

        if command == t { return true }
        if command.hasPrefix(t + " ") || command.hasSuffix(" " + t) { return true }
        if command.contains(" " + t + " ") { return true }
        if command.contains("/" + t + "/") { return true }
        if command.contains("/" + t + " ") { return true }
        if command.hasSuffix("/" + t) { return true }
        if command.hasPrefix(t + "/") { return true }

        // Scoped packages: @scope/token
        if command.contains("/" + t + "@") || command.contains("@" + t) {
            return command.contains(t)
        }

        // Dotted module paths ending in the token (express/lib → still need /express)
        return false
    }

    static func mentionsAny(_ command: String, _ tokens: String...) -> Bool {
        tokens.contains { mentions(command, $0) }
    }

    static func hasPhrase(_ command: String, _ phrase: String) -> Bool {
        command.contains(phrase.lowercased())
    }
}
