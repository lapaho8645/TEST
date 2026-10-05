import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @State private var activeTab: MainTab = .overview
    @State private var isInspectorVisible = true
    @State private var showAddRoot = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, activeTab: $activeTab) {
                showAddRoot = true
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 360)
        } detail: {
            MainWorkspaceView(model: model, activeTab: $activeTab, isInspectorVisible: $isInspectorVisible)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.scan()
                } label: {
                    Label(model.isScanning ? "Scanning…" : "Scan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)

                Button {
                    showAddRoot = true
                } label: {
                    Label("Scan Location", systemImage: "folder.badge.plus")
                }

                Button {
                    isInspectorVisible.toggle()
                } label: {
                    Image(systemName: isInspectorVisible ? "sidebar.trailing" : "sidebar.trailing")
                }
                .help("Toggle inspector")
            }
        }
        .sheet(isPresented: $showAddRoot) {
            FolderPickerSheet { url in
                showAddRoot = false
                model.addScanRoot(url)
            }
        }
        .task {
            if model.projects.isEmpty && !model.isScanning {
                model.scan()
            }
        }
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case effective = "Effective"
    case files = "Files"
    case compare = "Compare"
    var id: String { rawValue }
}

struct SidebarView: View {
    @ObservedObject var model: AppViewModel
    @Binding var activeTab: MainTab
    let addRoot: () -> Void

    var filteredProjects: [Project] {
        if model.searchText.isEmpty { return model.projects }
        return model.projects.filter { project in
            project.name.localizedCaseInsensitiveContains(model.searchText) ||
            project.url.path.localizedCaseInsensitiveContains(model.searchText) ||
            project.agents.contains { $0.agent.title.localizedCaseInsensitiveContains(model.searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AgentLens")
                        .font(.headline)
                    Text("AI configuration explorer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            TextField("Search projects", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            List {
                Section {
                    HStack {
                        Label("AI-configured projects", systemImage: "folder.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(filteredProjects.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    ForEach(filteredProjects) { project in
                        ProjectSidebarRow(project: project, isSelected: model.selectedProjectID == project.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedProjectID = project.id
                                activeTab = .overview
                                let preferred = project.agents.first?.agent ?? .claude
                                model.selectedAgent = preferred
                                model.selectedConfigID = nil
                            }
                            .contextMenu {
                                Button("Reveal in Finder") { FileService.reveal(project.url) }
                                Button("Open Folder in VS Code") { FileService.openInVSCode(project.url) }
                            }
                    }
                }

                Section("Global") {
                    if model.globalConfigs.isEmpty {
                        Text("No global configs discovered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.globalConfigs) { config in
                            HStack(spacing: 8) {
                                Image(systemName: config.agent.symbol)
                                    .frame(width: 18)
                                    .foregroundStyle(.secondary)
                                Text(config.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedProjectID = nil
                                model.selectGlobalConfig(config)
                                activeTab = .files
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button(action: addRoot) {
                    Label("Add scan location", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)

            HStack {
                Image(systemName: "magnifyingglass.circle")
                    .foregroundStyle(.secondary)
                Text(model.lastScanText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
}

extension AppViewModel {
    fileprivate func selectGlobalConfig(_ config: ConfigFile?) {
        selectedConfigID = config?.id
        guard let config else { editorText = ""; return }
        editorText = (try? String(contentsOf: config.url, encoding: .utf8)) ?? ""
    }
}

struct ProjectSidebarRow: View {
    let project: Project
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "folder")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(project.agents.prefix(4)) { summary in
                        Text(summary.agent.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text("\(project.configFiles.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct MainWorkspaceView: View {
    @ObservedObject var model: AppViewModel
    @Binding var activeTab: MainTab
    @Binding var isInspectorVisible: Bool

    var body: some View {
        if let project = model.selectedProject {
            VStack(spacing: 0) {
                ProjectHeader(model: model, project: project)
                Divider()

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Picker("", selection: $activeTab) {
                            ForEach(MainTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(14)

                        Divider()

                        Group {
                            switch activeTab {
                            case .overview:
                                OverviewView(model: model, project: project)
                            case .effective:
                                EffectiveView(model: model, project: project)
                            case .files:
                                FilesView(model: model, project: project)
                            case .compare:
                                CompareView(model: model, project: project)
                            }
                        }
                    }

                    if isInspectorVisible, activeTab == .files {
                        Divider()
                        InspectorEditorView(model: model, project: project)
                            .frame(minWidth: 480, idealWidth: 600, maxWidth: 760)
                    }
                }
            }
        } else {
            GlobalConfigWorkspace(model: model)
        }
    }
}

struct ProjectHeader: View {
    @ObservedObject var model: AppViewModel
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.title2.weight(.bold))
                    Text(project.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(project.agents) { summary in
                        AgentBadge(agent: summary.agent, count: summary.fileCount)
                    }
                }
            }
        }
        .padding(18)
    }
}

struct AgentBadge: View {
    let agent: AgentType
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: agent.symbol)
            Text(agent.title)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppViewModel
    let project: Project

    var warnings: [String] {
        let names = Set(project.configFiles.map(\.name))
        var result: [String] = []
        if names.contains("CLAUDE.md") && names.contains("AGENTS.md") { result.append("Both CLAUDE.md and AGENTS.md exist; keep shared rules aligned.") }
        let pathRules = project.configFiles.filter { !$0.rulePatterns.isEmpty && $0.scope == .pathSpecific }
        if !pathRules.isEmpty { result.append("\(pathRules.count) path-specific rules depend on target-file matching.") }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    StatCard(title: "AI tools", value: "\(project.agents.count)", subtitle: "detected")
                    StatCard(title: "Config files", value: "\(project.configFiles.count)", subtitle: "discovered")
                    StatCard(title: "Path rules", value: "\(project.configFiles.filter { $0.scope == .pathSpecific }.count)", subtitle: "conditional")
                }

                GroupBox("Configuration map") {
                    VStack(spacing: 0) {
                        ForEach(project.agents) { summary in
                            HStack {
                                Image(systemName: summary.agent.symbol)
                                    .frame(width: 24)
                                Text(summary.agent.title)
                                    .frame(width: 150, alignment: .leading)
                                ProgressView(value: Double(summary.fileCount), total: Double(max(project.configFiles.count, 1)))
                                Text("\(summary.fileCount) files")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(4)
                }

                GroupBox("Health") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Auto-discovered project", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Configuration files are edited in place", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        ForEach(warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(4)
                }

                HStack {
                    Button("Reveal in Finder") { FileService.reveal(project.url) }
                    Button("Open in VS Code") { FileService.openInVSCode(project.url) }
                    Spacer()
                }
            }
            .padding(18)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EffectiveView: View {
    @ObservedObject var model: AppViewModel
    let project: Project
    private let resolver = InstructionResolver()

    var targetURL: URL? {
        let value = model.targetFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return project.url.appendingPathComponent(value)
    }

    var nodes: [InstructionNode] {
        resolver.resolve(project: project, agent: model.selectedAgent, workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath), targetFile: targetURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Resolution context") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Agent") {
                        Picker("", selection: $model.selectedAgent) {
                            ForEach(project.agents.map(\.agent)) { agent in
                                Label(agent.title, systemImage: agent.symbol).tag(agent)
                            }
                        }
                        .labelsHidden()
                    }
                    LabeledContent("Working directory") {
                        TextField("Absolute path", text: $model.workingDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Target file") {
                        TextField("e.g. Sources/App.swift", text: $model.targetFilePath)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(4)
            }

            Text("Effective Instruction Chain")
                .font(.headline)

            if nodes.isEmpty {
                ContentUnavailableView("No configurations", systemImage: "doc.text.magnifyingglass", description: Text("No supported config files were discovered for this agent."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(nodes) { node in
                            EffectiveRow(node: node)
                                .onTapGesture {
                                    model.selectConfig(node.config)
                                }
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

struct EffectiveRow: View {
    let node: InstructionNode

    var body: some View {
        HStack(spacing: 12) {
            Text("\(node.order)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Image(systemName: node.applies ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(node.applies ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(node.config.name)
                        .font(.subheadline.weight(.semibold))
                    Text(node.config.scope.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                Text(node.config.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(node.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary)
        }
    }
}

struct FilesView: View {
    @ObservedObject var model: AppViewModel
    let project: Project

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Agent", selection: $model.selectedAgent) {
                        ForEach(project.agents.map(\.agent)) { agent in
                            Label(agent.title, systemImage: agent.symbol).tag(agent)
                        }
                    }
                    .labelsHidden()
                    Spacer()
                }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.selectedProjectFiles) { config in
                            ConfigRow(config: config, selected: model.selectedConfigID == config.id)
                                .onTapGesture {
                                    model.selectConfig(config)
                                }
                        }
                    }
                }
            }
            .padding(14)
            .frame(minWidth: 330, idealWidth: 380, maxWidth: 460)

            Spacer(minLength: 0)
        }
    }
}

struct ConfigRow: View {
    let config: ConfigFile
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon(config))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(config.name)
                    .font(.subheadline.weight(.medium))
                Text(config.scope.rawValue + (config.rulePatterns.isEmpty ? "" : " • \(config.rulePatterns.joined(separator: ", "))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(config.kind.label)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private func fileIcon(_ config: ConfigFile) -> String {
        switch config.kind {
        case .markdown: "doc.richtext"
        case .json: "curlybraces"
        case .toml, .yaml: "list.bullet.rectangle"
        case .other: "doc"
        }
    }
}

struct InspectorEditorView: View {
    @ObservedObject var model: AppViewModel
    let project: Project
    @State private var mode: EditorMode = .visual

    enum EditorMode: String, CaseIterable, Identifiable {
        case visual = "Visual"
        case raw = "Raw"
        var id: String { rawValue }
    }

    var selectedConfig: ConfigFile? {
        project.configFiles.first { $0.id == model.selectedConfigID }
    }

    var headings: [String] {
        let values: [String] = model.editorText
            .split(separator: "\n")
            .compactMap { line in
                let value = line.trimmingCharacters(in: .whitespaces)
                return value.hasPrefix("#") ? String(value) : nil
            }
        return Array(values.prefix(24))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedConfig?.name ?? "No file selected")
                        .font(.headline)
                    if let url = selectedConfig?.url {
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Picker("Mode", selection: $mode) {
                    ForEach(EditorMode.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Button("Save") { model.saveSelectedConfig() }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(selectedConfig == nil)
            }
            .padding(14)

            Divider()

            if selectedConfig == nil {
                ContentUnavailableView("Select a configuration", systemImage: "doc.text", description: Text("Choose a file from the Files tab."))
            } else {
                if mode == .visual {
                    VisualInspector(text: model.editorText, headings: headings)
                } else {
                    TextEditor(text: $model.editorText)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                }

                Divider()
                HStack {
                    if let config = selectedConfig {
                        Button("Reveal") { FileService.reveal(config.url) }
                        Button("VS Code") { FileService.openInVSCode(config.url) }
                        Spacer()
                        Text("Editing in place • Backup on save")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
            }
        }
    }
}

struct VisualInspector: View {
    let text: String
    let headings: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    InspectorStat(title: "Lines", value: "\(text.split(separator: "\n", omittingEmptySubsequences: false).count)")
                    InspectorStat(title: "Words", value: "\(text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count)")
                    InspectorStat(title: "Code blocks", value: "\(text.components(separatedBy: "```").count > 1 ? (text.components(separatedBy: "```").count - 1) / 2 : 0)")
                }

                GroupBox("Outline") {
                    if headings.isEmpty {
                        Text("No Markdown headings found.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(headings, id: \.self) { heading in
                                Text(heading)
                                    .font(.callout)
                                    .foregroundStyle(heading.hasPrefix("# ") ? .primary : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Smart inspector") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") ? "Frontmatter detected" : "No frontmatter", systemImage: "doc.text.magnifyingglass")
                        Label(text.contains("applyTo:") || text.contains("paths:") ? "Conditional path rules detected" : "No explicit path rule metadata", systemImage: "arrow.triangle.branch")
                        Label(text.contains("TODO") || text.contains("FIXME") ? "TODO/FIXME markers present" : "No TODO/FIXME markers detected", systemImage: "checkmark.seal")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }
}

struct InspectorStat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CompareView: View {
    @ObservedObject var model: AppViewModel
    let project: Project
    @State private var leftID: String?
    @State private var rightID: String?

    var body: some View {
        let files = project.configFiles
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Left", selection: $leftID) {
                    Text("Select").tag(String?.none)
                    ForEach(files) { file in Text(file.name).tag(Optional(file.id)) }
                }
                Picker("Right", selection: $rightID) {
                    Text("Select").tag(String?.none)
                    ForEach(files) { file in Text(file.name).tag(Optional(file.id)) }
                }
            }

            HStack(spacing: 0) {
                ComparePane(title: fileName(leftID, files: files), content: text(leftID, files: files))
                Divider()
                ComparePane(title: fileName(rightID, files: files), content: text(rightID, files: files))
            }
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
    }

    private func fileName(_ id: String?, files: [ConfigFile]) -> String { files.first { $0.id == id }?.name ?? "Select a file" }
    private func text(_ id: String?, files: [ConfigFile]) -> String {
        guard let url = files.first(where: { $0.id == id })?.url else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

struct ComparePane: View {
    let title: String
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.subheadline.weight(.semibold)).padding(10)
            Divider()
            ScrollView {
                Text(content.isEmpty ? "No content" : content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GlobalConfigWorkspace: View {
    @ObservedObject var model: AppViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Global configuration")
                        .font(.title2.weight(.bold))
                    Text("Personal AI settings discovered from your home directory")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            if let configID = model.selectedConfigID,
               let config = model.globalConfigs.first(where: { $0.id == configID }) {
                HStack(spacing: 8) {
                    Image(systemName: config.agent.symbol)
                    Text(config.agent.title)
                    Text(config.scope.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $model.editorText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(.quaternary)
                HStack {
                    Button("Save") { saveGlobal(config) }
                    Button("Reveal") { FileService.reveal(config.url) }
                    Spacer()
                }
            } else {
                ContentUnavailableView("Select a global config", systemImage: "globe", description: Text("Choose a file from the Global section in the sidebar."))
            }
        }
        .padding(22)
    }

    private func saveGlobal(_ config: ConfigFile) {
        try? FileService.backupAndWrite(text: model.editorText, to: config.url)
        model.scan()
    }
}

struct FolderPickerSheet: View {
    let completion: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("Add a scan location")
                .font(.title2.weight(.bold))
            Text("AgentLens will search this directory for projects containing AI configuration files.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Button("Choose Folder") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        completion(url)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}
