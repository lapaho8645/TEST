import Foundation

@MainActor
final class ProjectStore {
    private let defaults = UserDefaults.standard
    private let key = "AgentLens.scanRoots.v1"

    var scanRoots: [URL] {
        if let values = defaults.array(forKey: key) as? [String], !values.isEmpty {
            return values.map { URL(fileURLWithPath: $0) }
        }
        return [FileManager.default.homeDirectoryForCurrentUser]
    }

    func addScanRoot(_ url: URL) {
        var current = scanRoots.map(\.standardizedFileURL.path)
        let value = url.standardizedFileURL.path
        if !current.contains(value) { current.append(value) }
        defaults.set(current, forKey: key)
    }
}
