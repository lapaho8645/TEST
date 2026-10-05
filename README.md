# AgentLens v0.4

A macOS SwiftUI AI configuration manager inspired by the best parts of ClaudeMDEditor, with automatic discovery and effective-instruction resolution.

## Open in Xcode

This release intentionally uses Swift Package Manager instead of a hand-written `.xcodeproj`, so Xcode manages the project metadata and there is no `project.pbxproj` to corrupt.

1. Unzip the folder.
2. Open `Package.swift` in Xcode.
3. Select the `AgentLens` scheme and `My Mac`.
4. Run with `⌘R`.

Minimum deployment target: macOS 14.

## What this version does

- Automatically scans `~` on first launch.
- Shows only projects where AI configuration markers were found.
- Supports Claude Code, Codex, GitHub Copilot, Gemini CLI, Cursor, Windsurf and Aider markers.
- Separates global configs from project configs.
- Shows Overview / Effective / Files / Compare tabs.
- Resolves global → project → directory → local → path-specific rules.
- Parses `applyTo:` and `paths:` for basic glob matching.
- Visual inspector for Markdown structure, code blocks, frontmatter and TODO/FIXME markers.
- Raw editor with save and automatic backup.
- Reveal in Finder / Open in VS Code.
- Add extra scan locations without registering individual projects.

## Design principle

The real source of truth stays in the original config files on disk. AgentLens does not copy project instructions into its own database.
