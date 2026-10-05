import Foundation

public enum ConfigScope: String, CaseIterable, Sendable {
    case global = "Global"
    case project = "Project"
    case local = "Local"
    case pathSpecific = "Path"
    case directory = "Directory"
}

public enum ConfigKind: String, Sendable {
    case markdown
    case json
    case toml
    case yaml
    case other

    public var label: String { rawValue.uppercased() }
}

public struct ConfigFile: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let agent: AgentType
    public let scope: ConfigScope
    public let kind: ConfigKind
    public let rulePatterns: [String]

    public init(url: URL, agent: AgentType, scope: ConfigScope, rulePatterns: [String] = []) {
        self.url = url
        self.id = url.standardizedFileURL.path
        self.agent = agent
        self.scope = scope
        self.kind = Self.kind(for: url)
        self.rulePatterns = rulePatterns
    }

    public var name: String { url.lastPathComponent }

    private static func kind(for url: URL) -> ConfigKind {
        switch url.pathExtension.lowercased() {
        case "md": .markdown
        case "json": .json
        case "toml": .toml
        case "yaml", "yml": .yaml
        default: .other
        }
    }
}

public struct InstructionNode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let config: ConfigFile
    public let applies: Bool
    public let reason: String
    public let order: Int

    public init(id: UUID = UUID(), config: ConfigFile, applies: Bool, reason: String, order: Int) {
        self.id = id
        self.config = config
        self.applies = applies
        self.reason = reason
        self.order = order
    }
}
