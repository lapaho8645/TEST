import Foundation

public struct DiscoveryResult: Sendable {
    public let projects: [Project]
    public let globalConfigs: [ConfigFile]
    public let scannedRoots: [URL]
    public let duration: TimeInterval
}

public struct ProjectScanner: Sendable {
    public init() {}

    public func scan(roots: [URL]) -> DiscoveryResult {
        let started = Date()
        let fileManager = FileManager.default
        let normalizedRoots = roots.map { $0.standardizedFileURL }
        let candidates = discoverMarkerFiles(in: normalizedRoots, fileManager: fileManager)
        var grouped: [String: [ConfigFile]] = [:]

        for url in candidates {
            if let projectRoot = projectRoot(for: url, roots: normalizedRoots, fileManager: fileManager) {
                let configs = configsForMarker(url, projectRoot: projectRoot, fileManager: fileManager)
                grouped[projectRoot.path, default: []].append(contentsOf: configs)
            }
        }

        var projects: [Project] = []
        for (path, files) in grouped {
            let projectURL = URL(fileURLWithPath: path).standardizedFileURL
            let unique = uniqueConfigs(files).sorted { $0.url.path < $1.url.path }
            projects.append(Project(url: projectURL, configFiles: unique))
        }

        projects.sort { lhs, rhs in
            let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return byName == .orderedSame ? lhs.url.path < rhs.url.path : byName == .orderedAscending
        }

        let globals = discoverGlobalConfigs(fileManager: fileManager).sorted { $0.url.path < $1.url.path }
        return DiscoveryResult(projects: projects, globalConfigs: globals, scannedRoots: normalizedRoots, duration: Date().timeIntervalSince(started))
    }

    private func discoverMarkerFiles(in roots: [URL], fileManager: FileManager) -> [URL] {
        var results: [URL] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: []
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                let name = item.lastPathComponent
                if skipDirectory(name, url: item, enumerator: enumerator, fileManager: fileManager) { continue }
                if isMarker(url: item) && !isHomeLevelGlobalMarker(item, roots: roots) { results.append(item) }
            }
        }
        return results
    }

    private func skipDirectory(_ name: String, url: URL, enumerator: FileManager.DirectoryEnumerator, fileManager: FileManager) -> Bool {
        let alwaysSkip = [
            ".git", "node_modules", "DerivedData", ".Trash", "Caches", "cache",
            ".build", "build", "dist", "target",
            "Pods", "vendor", ".venv", "venv", "__pycache__"
        ]
        guard fileManager.fileExists(atPath: url.path) else { return false }
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard isDirectory.boolValue else { return false }
        if alwaysSkip.contains(name) || name.hasPrefix("DerivedData") {
            enumerator.skipDescendants()
            return true
        }
        return false
    }

    private func isMarker(url: URL) -> Bool {
        let name = url.lastPathComponent
        if ["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md", "AGENTS.override.md", "GEMINI.md", ".cursorrules", ".windsurfrules", "CONVENTIONS.md"].contains(name) {
            return true
        }
        if name == "copilot-instructions.md" && url.path.contains("/.github/") { return true }
        if name.hasSuffix(".instructions.md") && url.path.contains("/.github/instructions/") { return true }
        if name.hasSuffix(".md") && url.path.contains("/.claude/rules/") { return true }
        if name.hasSuffix(".mdc") && url.path.contains("/.cursor/rules/") { return true }
        if name == "settings.json" && url.path.contains("/.claude/") { return true }
        if name == "config.toml" && url.path.contains("/.codex/") { return true }
        return false
    }

    private func isHomeLevelGlobalMarker(_ url: URL, roots: [URL]) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let globalRoots = [
            home + "/.claude/",
            home + "/.codex/",
            home + "/.gemini/",
            home + "/.copilot/"
        ]
        return globalRoots.contains { url.path.hasPrefix($0) }
    }

    private func projectRoot(for marker: URL, roots: [URL], fileManager: FileManager) -> URL? {
        var current = marker.deletingLastPathComponent().standardizedFileURL
        let rootPaths = Set(roots.map { $0.standardizedFileURL.path })
        let configFolders = [".claude", ".github", ".cursor", ".codex", ".gemini", ".windsurf"]
        let projectMarkers = ["package.json", "package-lock.json", "pnpm-workspace.yaml", "pom.xml", "build.gradle", "build.gradle.kts", "Cargo.toml", "go.mod", "pyproject.toml", "Package.swift"]

        while current.path != "/" {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            if let children = try? fileManager.contentsOfDirectory(at: current, includingPropertiesForKeys: nil, options: []) {
                if children.contains(where: { projectMarkers.contains($0.lastPathComponent) }) {
                    return current
                }
            }
            if current.path != marker.path && configFolders.contains(current.lastPathComponent) {
                return current.deletingLastPathComponent()
            }
            if rootPaths.contains(current.path) {
                return marker.deletingLastPathComponent().standardizedFileURL
            }
            current.deleteLastPathComponent()
        }
        return marker.deletingLastPathComponent().standardizedFileURL
    }

    private func configsForMarker(_ marker: URL, projectRoot: URL, fileManager: FileManager) -> [ConfigFile] {
        let relative = marker.path.hasPrefix(projectRoot.path) ? String(marker.path.dropFirst(projectRoot.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : marker.lastPathComponent
        let components = relative.split(separator: "/").map(String.init)
        let fileName = marker.lastPathComponent
        let agent = agentFor(marker)

        var scope: ConfigScope = .project
        var patterns: [String] = []

        if fileName == "settings.local.json" { scope = .local }
        if fileName.hasSuffix(".instructions.md") || marker.path.contains("/.claude/rules/") || marker.path.contains("/.cursor/rules/") {
            scope = .pathSpecific
            patterns = readPatterns(from: marker)
        }
        if components.count > 1 && (components[0] == ".claude" || components[0] == ".cursor" || components[0] == ".github") {
            scope = scope == .pathSpecific ? .pathSpecific : .directory
        }

        return [ConfigFile(url: marker, agent: agent, scope: scope, rulePatterns: patterns)]
    }

    private func agentFor(_ url: URL) -> AgentType {
        let path = url.path
        let name = url.lastPathComponent
        if name.hasPrefix("CLAUDE") || path.contains("/.claude/") { return .claude }
        if name.hasPrefix("AGENTS") || path.contains("/.codex/") { return .codex }
        if name == "GEMINI.md" || path.contains("/.gemini/") { return .gemini }
        if name == "copilot-instructions.md" || path.contains("/.github/instructions/") { return .copilot }
        if name == ".cursorrules" || path.contains("/.cursor/") { return .cursor }
        if name == ".windsurfrules" || path.contains("/.windsurf/") { return .windsurf }
        if name == "CONVENTIONS.md" { return .aider }
        return .unknown
    }

    private func readPatterns(from url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var values: [String] = []
        let keys = ["applyTo", "paths"]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for key in keys where raw.hasPrefix(key + ":") {
                let value = raw.replacingOccurrences(of: key + ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]\\\"'"))
                if !clean.isEmpty { values.append(contentsOf: clean.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) }
            }
        }
        return Array(Set(values))
    }

    private func discoverGlobalConfigs(fileManager: FileManager) -> [ConfigFile] {
        let home = fileManager.homeDirectoryForCurrentUser
        var result: [ConfigFile] = []
        let paths: [(String, AgentType)] = [
            (".claude/CLAUDE.md", .claude),
            (".codex/AGENTS.md", .codex),
            (".codex/config.toml", .codex),
            (".gemini/GEMINI.md", .gemini),
            (".copilot/instructions.md", .copilot)
        ]
        for (relative, agent) in paths {
            let url = home.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: url.path) {
                result.append(ConfigFile(url: url, agent: agent, scope: .global))
            }
        }
        return result
    }

    private func uniqueConfigs(_ files: [ConfigFile]) -> [ConfigFile] {
        var seen = Set<String>()
        return files.filter { seen.insert($0.id).inserted }
    }
}
