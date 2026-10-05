import Foundation

public enum AgentType: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case copilot
    case gemini
    case cursor
    case windsurf
    case aider
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .copilot: "GitHub Copilot"
        case .gemini: "Gemini CLI"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .aider: "Aider"
        case .unknown: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .gemini: "wand.and.stars"
        case .cursor: "cursorarrow.rays"
        case .windsurf: "wind"
        case .aider: "text.badge.checkmark"
        case .unknown: "questionmark"
        }
    }
}
