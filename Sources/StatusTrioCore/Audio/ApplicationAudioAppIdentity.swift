import AppKit
import Darwin
import Foundation

struct ApplicationAudioProcessIdentityEvidence: Sendable {
    let pid: Int32
    let executableURL: URL
    let instanceID: String

    static func isAlive(instanceID: String) -> Bool {
        guard let pidPart = instanceID.split(separator: ":").first,
              let pid = Int32(pidPart) else { return false }
        return read(pid: pid)?.instanceID == instanceID
    }

    static func read(pid: Int32) -> Self? {
        func startToken() -> String? {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return "\(pid):\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
        }
        guard pid > 0, let before = startToken() else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard count > 0, before == startToken() else { return nil }
        return Self(pid: pid, executableURL: URL(fileURLWithPath: String(cString: path)), instanceID: before)
    }
}

struct ApplicationAudioRunningAppEvidence {
    let pid: Int32
    let bundleURL: URL
    let bundleID: String
    let name: String
}

struct ApplicationAudioAppIdentity: Equatable {
    let name: String
    let bundleID: String?
    let appURL: URL?
    /// Process launch evidence distinguishes a reused PID from its previous owner.
    let instanceID: String
    /// Helpers share a verified main application instance while retaining distinct process identities.
    let ownerInstanceID: String

    init(name: String, bundleID: String?, appURL: URL?, instanceID: String, ownerInstanceID: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.appURL = appURL
        self.instanceID = instanceID
        self.ownerInstanceID = ownerInstanceID ?? instanceID
    }

    @MainActor
    static func resolve(pid: Int32) -> Self? {
        guard let process = ApplicationAudioProcessIdentityEvidence.read(pid: pid) else { return nil }
        let owners = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationAudioRunningAppEvidence? in
            guard !app.isTerminated, let url = app.bundleURL, let bundle = app.bundleIdentifier else { return nil }
            return ApplicationAudioRunningAppEvidence(pid: app.processIdentifier, bundleURL: url,
                bundleID: bundle, name: app.localizedName ?? bundle)
        }
        return resolve(process: process, owners: owners,
            evidence: { ApplicationAudioProcessIdentityEvidence.read(pid: $0) },
            bundleID: { Bundle(url: $0)?.bundleIdentifier })
    }

    @MainActor
    static func resolve(
        process: ApplicationAudioProcessIdentityEvidence, owners: [ApplicationAudioRunningAppEvidence],
        evidence: (Int32) -> ApplicationAudioProcessIdentityEvidence?, bundleID: (URL) -> String?
    ) -> Self? {
        guard let url = outermostApplicationURL(process.executableURL), let bundle = bundleID(url) else { return nil }
        let matches = owners.filter { $0.bundleURL.standardizedFileURL == url && $0.bundleID == bundle }
        // The helper path alone cannot choose between multiple independent instances of the same app.
        let owner: ApplicationAudioRunningAppEvidence
        if let direct = matches.first(where: { $0.pid == process.pid }) { owner = direct }
        else if matches.count == 1 { owner = matches[0] }
        else { return nil }
        guard let ownerProcess = evidence(owner.pid), outermostApplicationURL(ownerProcess.executableURL) == url else { return nil }
        return Self(name: owner.name, bundleID: bundle, appURL: url,
                    instanceID: process.instanceID, ownerInstanceID: ownerProcess.instanceID)
    }

    private static func outermostApplicationURL(_ executable: URL) -> URL? {
        var candidate = executable.standardizedFileURL
        var outermost: URL?
        while candidate.path != "/" {
            if candidate.pathExtension == "app" { outermost = candidate }
            candidate = candidate.deletingLastPathComponent()
        }
        return outermost
    }
}
