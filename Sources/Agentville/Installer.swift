// Connect and Disconnect's file and process work (docs/architecture/installation.md): the helper
// link (ADR 0007), Path B's edit of ~/.claude/settings.json with its backup, and running the
// `claude` CLI for Path A. The decisions are pure and tested in Core (`HelperLink`,
// `ClaudeSettingsHooks`, `ClaudeCLI`); this file only touches the disk and processes, and only
// when the user asks (Connect, Disconnect), except repairing a dangling link at launch.
// One of the two files `scripts/check-no-disk-writes.sh` allows to write (non-negotiable #8).
import AgentvilleCore
import Foundation

enum Installer {
    enum Failure: Error, CustomStringConvertible {
        case settings(ClaudeSettingsHooks.Failure)
        /// settings.json changed between the preview and the write.
        case changedMeanwhile
        case io(String)

        var description: String {
            switch self {
            case .settings(let f): f.description
            case .changedMeanwhile: "settings.json changed while Agentville was preparing its edit. Nothing was written; try again."
            case .io(let s): s
            }
        }
    }

    static var home: String { NSHomeDirectory() }

    // MARK: - Helper link

    /// This copy's helper: in the bundle, or next to the executable in a development build.
    static var ourHelper: String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/agentville-hook").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        return Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("agentville-hook").path
    }

    static var linkPath: String { HelperLink.path(home: home) }

    static func linkState() -> HelperLink.State {
        let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)
        let exists = destination.map { FileManager.default.fileExists(atPath: resolve($0, relativeTo: linkPath)) } ?? false
        return HelperLink.state(destination: destination.map { resolve($0, relativeTo: linkPath) }, targetExists: exists, ours: ourHelper)
    }

    private static func resolve(_ destination: String, relativeTo link: String) -> String {
        destination.hasPrefix("/") ? destination : ((link as NSString).deletingLastPathComponent as NSString).appendingPathComponent(destination)
    }

    /// Points the link at this copy's helper.
    static func link(_ action: HelperLink.Action) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: (linkPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if action == .replace { try? fm.removeItem(atPath: linkPath) }
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: ourHelper)
        } catch {
            throw Failure.io("Couldn't create the helper link: \(error.localizedDescription)")
        }
    }

    /// Removes the link, then `bin` and `Agentville` in Application Support if they're empty.
    static func unlink() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: linkPath)
        let bin = (linkPath as NSString).deletingLastPathComponent
        for dir in [bin, (bin as NSString).deletingLastPathComponent] {
            if (try? fm.contentsOfDirectory(atPath: dir))?.isEmpty == true { try? fm.removeItem(atPath: dir) }
        }
    }

    /// At launch: repair a link left dangling by a moved app; recreate a missing one if connected.
    /// Returns what it did, for diagnostics.
    static func repairLinkAtLaunch(connected: Bool) -> String? {
        let state = linkState()
        guard let action = HelperLink.launchAction(state, connected: connected) else { return nil }
        do {
            try link(action)
            return "helper link \(action == .create ? "created" : "repaired")"
        } catch {
            return "helper link not repaired: \(error)"
        }
    }

    // MARK: - Path B: ~/.claude/settings.json

    static var settingsPath: String { home + "/.claude/settings.json" }

    /// What Connect will write, shown to the user before anything changes.
    struct SettingsPlan {
        /// nil when there's no file yet.
        let original: String?
        let patched: String
    }

    static func readSettings() throws -> String? {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return nil }
        do { return try String(contentsOfFile: settingsPath, encoding: .utf8) } catch {
            throw Failure.io("Couldn't read \(settingsPath): \(error.localizedDescription)")
        }
    }

    static func planConnect() throws -> SettingsPlan {
        let original = try readSettings()
        do { return SettingsPlan(original: original, patched: try ClaudeSettingsHooks.connect(original)) } catch let f as ClaudeSettingsHooks.Failure {
            throw Failure.settings(f)
        }
    }

    /// Backs up the current file (if any) next to it, then writes the plan. Refuses if the file
    /// changed since the plan was made. Returns the backup's path.
    @discardableResult
    static func apply(_ plan: SettingsPlan, now: Date = Date()) throws -> String? {
        guard try readSettings() == plan.original else { throw Failure.changedMeanwhile }
        var backup: String?
        if let original = plan.original {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let path = settingsPath + ".agentville-backup-" + f.string(from: now)
            do { try original.write(toFile: path, atomically: true, encoding: .utf8) } catch {
                throw Failure.io("Couldn't write the backup \(path): \(error.localizedDescription)")
            }
            backup = path
        }
        try write(plan.patched)
        return backup
    }

    /// Removes only our marked hooks.
    static func disconnectSettings() throws {
        guard let original = try readSettings() else { return }
        let patched: String
        do { patched = try ClaudeSettingsHooks.disconnect(original) } catch let f as ClaudeSettingsHooks.Failure {
            throw Failure.settings(f)
        }
        if patched != original { try write(patched) }
    }

    /// Writes through a symlinked settings.json (dotfiles) instead of replacing the link, and keeps
    /// the file's permissions.
    private static func write(_ text: String) throws {
        let fm = FileManager.default
        let target = (settingsPath as NSString).resolvingSymlinksInPath
        let permissions = (try? fm.attributesOfItem(atPath: target))?[.posixPermissions]
        do {
            try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: target, atomically: true, encoding: .utf8)
            if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target) }
        } catch {
            throw Failure.io("Couldn't write \(target): \(error.localizedDescription)")
        }
    }

    // MARK: - Path A: the claude CLI

    /// The login shell's answer first, then the usual locations.
    static func findClaude() async -> String? {
        let (status, out) = await run(ClaudeCLI.shellLookup[0], Array(ClaudeCLI.shellLookup.dropFirst()), timeout: 10)
        if status == 0, let p = ClaudeCLI.parseShellLookup(out), FileManager.default.isExecutableFile(atPath: p) { return p }
        return ClaudeCLI.candidates(home: home).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a process and returns its exit status and combined output. Never blocks the main thread.
    static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 180) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    continuation.resume(returning: (-1, "Couldn't run \(executable): \(error.localizedDescription)"))
                    return
                }
                let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: (p.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
