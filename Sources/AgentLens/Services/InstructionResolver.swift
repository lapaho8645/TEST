import Foundation

public struct InstructionResolver: Sendable {
    public init() {}

    public func resolve(project: Project, agent: AgentType, workingDirectory: URL, targetFile: URL?) -> [InstructionNode] {
        let files = project.configFiles.filter { $0.agent == agent }
        let sorted = files.sorted { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.url.path.count < rhs.url.path.count
        }

        var nodes: [InstructionNode] = []
        var index = 1
        for file in sorted {
            let applies = file.scope != .pathSpecific || targetFile == nil || matches(file.rulePatterns, targetFile: targetFile!, project: project)
            let reason: String
            if file.scope == .pathSpecific {
                reason = file.rulePatterns.isEmpty ? "Path rule (no pattern found → treated as broad)" : (applies ? "Matches target path" : "Does not match target path")
            } else {
                reason = file.scope.rawValue + " instruction"
            }
            nodes.append(InstructionNode(config: file, applies: applies, reason: reason, order: index))
            index += 1
        }
        return nodes
    }

    private func rank(_ file: ConfigFile) -> Int {
        switch file.scope {
        case .global: 0
        case .project: 1
        case .directory: 2
        case .local: 3
        case .pathSpecific: 4
        }
    }

    private func matches(_ patterns: [String], targetFile: URL, project: Project) -> Bool {
        guard !patterns.isEmpty else { return true }
        let relative = targetFile.path.hasPrefix(project.url.path)
            ? String(targetFile.path.dropFirst(project.url.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : targetFile.lastPathComponent
        for pattern in patterns {
            if glob(pattern, matches: relative) { return true }
        }
        return false
    }

    private func glob(_ pattern: String, matches value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "\\?", with: ".")
        return (try? NSRegularExpression(pattern: "^" + escaped + "$"))?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
