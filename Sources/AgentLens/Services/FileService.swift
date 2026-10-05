import Foundation
import AppKit

public enum FileService {
    public static func backupAndWrite(text: String, to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let backupDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AgentLens/Backups", isDirectory: true)
                .appendingPathComponent(url.lastPathComponent, isDirectory: true)
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try text.data(using: .utf8)?.write(to: backupDir.appendingPathComponent("\(stamp).backup"), options: .atomic)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func openInVSCode(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["code", url.path]
        try? process.run()
    }
}
