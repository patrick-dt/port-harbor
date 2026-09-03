import Foundation

enum Framework: String, CaseIterable {
    case nextjs = "Next.js"
    case vite = "Vite"
    case nuxt = "Nuxt"
    case astro = "Astro"
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
    case unknown = "Server"

    /// SF Symbol name for each framework.
    var iconName: String {
        switch self {
        case .nextjs:    return "n.circle.fill"
        case .vite:      return "bolt.fill"
        case .nuxt:      return "arrowtriangle.up.fill"
        case .astro:     return "sparkles"
        case .remix:     return "arrow.triangle.2.circlepath"
        case .express:   return "shippingbox.fill"
        case .django:    return "d.circle.fill"
        case .flask:     return "flask.fill"
        case .rails:     return "tram.fill"
        case .hugo:      return "h.circle.fill"
        case .gatsby:    return "g.circle.fill"
        case .angular:   return "a.circle.fill"
        case .svelte:    return "s.circle.fill"
        case .webpack:   return "cube.fill"
        case .esbuild:   return "bolt.circle.fill"
        case .parcel:    return "shippingbox"
        case .php:       return "p.circle.fill"
        case .uvicorn, .fastapi: return "u.circle.fill"
        case .node:      return "n.circle"
        case .python:    return "p.circle"
        case .ruby:      return "r.circle"
        case .unknown:   return "circle.fill"
        }
    }
}

struct FrameworkDetector {
    /// Detect framework from the full command line string returned by `ps`.
    static func detect(from command: String) -> Framework {
        let lower = command.lowercased()

        // Order matters: more specific patterns first.

        // Next.js
        if lower.contains("next") && (lower.contains("dev") || lower.contains("start") || lower.contains("node")) {
            return .nextjs
        }

        // Nuxt
        if lower.contains("nuxt") || lower.contains("nuxi") {
            return .nuxt
        }

        // Astro
        if lower.contains("astro") {
            return .astro
        }

        // Remix
        if lower.contains("remix") {
            return .remix
        }

        // SvelteKit
        if lower.contains("svelte") {
            return .svelte
        }

        // Vite (check after framework-specific ones since many use Vite under the hood)
        if lower.contains("vite") {
            return .vite
        }

        // Angular
        if lower.contains("ng serve") || lower.contains("@angular") {
            return .angular
        }

        // Gatsby
        if lower.contains("gatsby") {
            return .gatsby
        }

        // Hugo
        if lower.contains("hugo") {
            return .hugo
        }

        // Webpack dev server
        if lower.contains("webpack") {
            return .webpack
        }

        // esbuild
        if lower.contains("esbuild") {
            return .esbuild
        }

        // Parcel
        if lower.contains("parcel") {
            return .parcel
        }

        // Express
        if lower.contains("express") || (lower.contains("node") && lower.contains("server")) {
            return .express
        }

        // Django
        if lower.contains("manage.py") && lower.contains("runserver") {
            return .django
        }

        // Flask
        if lower.contains("flask") {
            return .flask
        }

        // FastAPI / Uvicorn
        if lower.contains("uvicorn") {
            return lower.contains("fastapi") ? .fastapi : .uvicorn
        }

        // PHP built-in server
        if lower.contains("php") && lower.contains("-s") {
            return .php
        }

        // Rails
        if lower.contains("rails") || lower.contains("puma") {
            return .rails
        }

        // Generic fallbacks
        if lower.contains("node") || lower.contains("npm") || lower.contains("npx") || lower.contains("tsx") || lower.contains("ts-node") {
            return .node
        }

        if lower.contains("python") || lower.contains("python3") {
            return .python
        }

        if lower.contains("ruby") || lower.contains("bundle exec") {
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

    /// Build a concise subtitle like "Next.js · npm run dev · PID 41732"
    static func subtitle(framework: Framework, fullCommand: String, pid: Int) -> String {
        let shortCmd = shortCommand(fullCommand)
        return "\(framework.rawValue) · \(shortCmd) · PID \(pid)"
    }

    private static func shortCommand(_ cmd: String) -> String {
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
}
