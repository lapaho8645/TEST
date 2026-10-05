import Foundation

public struct AgentSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let agent: AgentType
    public let fileCount: Int

    public init(agent: AgentType, fileCount: Int) {
        self.id = agent.rawValue
        self.agent = agent
        self.fileCount = fileCount
    }
}

public struct Project: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public var configFiles: [ConfigFile]

    public init(url: URL, configFiles: [ConfigFile] = []) {
        self.id = url.standardizedFileURL.path
        self.url = url.standardizedFileURL
        self.configFiles = configFiles
    }

    public var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }

    public var agents: [AgentSummary] {
        let counts = Dictionary(grouping: configFiles, by: { $0.agent })
        return AgentType.allCases
            .filter { counts[$0] != nil }
            .map { AgentSummary(agent: $0, fileCount: counts[$0]?.count ?? 0) }
    }
}
