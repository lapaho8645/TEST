import Foundation
import SwiftUI

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var globalConfigs: [ConfigFile] = []
    @Published public var selectedProjectID: String?
    @Published public var selectedAgent: AgentType = .claude
    @Published public var selectedConfigID: String?
    @Published public var searchText = ""
    @Published public var workingDirectoryPath = ""
    @Published public var targetFilePath = ""
    @Published public var editorText = ""
    @Published public var isScanning = false
    @Published public var lastScanText = "Never scanned"
    @Published public var errorMessage: String?

    private var scanner = ProjectScanner()
    private let store = ProjectStore()

    public init() {
        workingDirectoryPath = FileManager.default.homeDirectoryForCurrentUser.path
    }

    public var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    public var selectedProjectFiles: [ConfigFile] {
        guard let project = selectedProject else { return [] }
        let files = project.configFiles.filter { $0.agent == selectedAgent }
        if searchText.isEmpty { return files }
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.url.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    public func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let roots = store.scanRoots
        Task.detached(priority: .userInitiated) { [scanner] in
            let result = scanner.scan(roots: roots)
            await MainActor.run {
                self.projects = result.projects
                self.globalConfigs = result.globalConfigs
                self.lastScanText = "\(result.projects.count) projects • \(result.globalConfigs.count) global configs • \(String(format: "%.1fs", result.duration))"
                if self.selectedProjectID == nil || !result.projects.contains(where: { $0.id == self.selectedProjectID }) {
                    self.selectedProjectID = result.projects.first?.id
                }
                self.selectedAgent = result.projects.first?.agents.first?.agent ?? .claude
                self.selectedConfigID = nil
                self.editorText = ""
                self.isScanning = false
            }
        }
    }

    public func addScanRoot(_ url: URL) {
        store.addScanRoot(url)
        scan()
    }

    public func selectConfig(_ config: ConfigFile?) {
        selectedConfigID = config?.id
        guard let config else {
            editorText = ""
            return
        }
        do {
            editorText = try String(contentsOf: config.url, encoding: .utf8)
        } catch {
            editorText = ""
            errorMessage = error.localizedDescription
        }
    }

    public func saveSelectedConfig() {
        guard let id = selectedConfigID, let project = selectedProject,
              let config = project.configFiles.first(where: { $0.id == id }) else { return }
        do {
            try FileService.backupAndWrite(text: editorText, to: config.url)
            errorMessage = nil
            scanKeepingSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scanKeepingSelection() {
        let projectID = selectedProjectID
        let configID = selectedConfigID
        let roots = store.scanRoots
        Task.detached(priority: .utility) { [scanner] in
            let result = scanner.scan(roots: roots)
            await MainActor.run {
                self.projects = result.projects
                self.globalConfigs = result.globalConfigs
                self.lastScanText = "\(result.projects.count) projects • \(result.globalConfigs.count) global configs • \(String(format: "%.1fs", result.duration))"
                self.selectedProjectID = projectID
                self.selectedConfigID = configID
            }
        }
    }
}
