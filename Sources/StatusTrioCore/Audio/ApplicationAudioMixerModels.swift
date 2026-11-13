import AppKit
import CoreAudio
import Foundation

struct ApplicationAudioDeviceSnapshot: Equatable, Sendable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let routeFingerprint: String

    init(id: AudioObjectID, uid: String, name: String, routeFingerprint: String = "") {
        self.id = id
        self.uid = uid
        self.name = name
        self.routeFingerprint = routeFingerprint
    }
}

struct ApplicationAudioProcessSnapshot: Equatable, Sendable {
    let objectID: AudioObjectID
    let pid: Int32
    let bundleID: String?
    let isRunningInput: Bool
    let isRunningOutput: Bool
    let inputDevices: [ApplicationAudioDeviceSnapshot]
    let outputDevices: [ApplicationAudioDeviceSnapshot]
    let outputRouteIsComplete: Bool
}

struct ApplicationAudioMixerRow: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleID: String?
    let appURL: URL?
    /// CoreAudio process object IDs, not Unix PIDs.
    let processIDs: [AudioObjectID]
    let outputDeviceUID: String?
    let outputDeviceName: String?
    let isInput: Bool
    let gain: Double
    let isMuted: Bool
    let canAdjust: Bool
    let instanceFingerprint: [String]
    let ownerInstanceID: String?
    let routeFingerprint: [String]

    func with(gain: Double, isMuted: Bool, canAdjust: Bool) -> Self {
        Self(id: id, name: name, bundleID: bundleID, appURL: appURL, processIDs: processIDs,
             outputDeviceUID: outputDeviceUID, outputDeviceName: outputDeviceName,
             isInput: isInput, gain: gain, isMuted: isMuted, canAdjust: canAdjust,
             instanceFingerprint: instanceFingerprint, ownerInstanceID: ownerInstanceID,
             routeFingerprint: routeFingerprint)
    }
}

@MainActor
protocol ApplicationAudioProcessDiscovering: AnyObject {
    func start(_ receive: @escaping @MainActor @Sendable (Result<[ApplicationAudioProcessSnapshot], Error>) -> Void)
    func stop()
}

@MainActor
protocol ApplicationAudioSessionControlling: AnyObject {
    var cleanupErrors: [OSStatus] { get }
    var hasUnreleasedResources: Bool { get }
    func start(processIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws
    func setGain(_ gain: Float)
    func stop()
}

@MainActor
enum ApplicationAudioMixerRows {
    static func make(
        _ snapshots: [ApplicationAudioProcessSnapshot], enabled: Bool,
        resolve: (Int32) -> ApplicationAudioAppIdentity?
    ) -> [ApplicationAudioMixerRow] {
        struct Member {
            let process: ApplicationAudioProcessSnapshot
            let identity: ApplicationAudioAppIdentity?
        }
        var grouped: [String: [Member]] = [:]
        for process in snapshots {
            let identity = resolve(process.pid)
            // Only a resolved bundle URL + identifier is trustworthy enough to group helpers.
            let appKey: String
            if let identity, let bundle = identity.bundleID, let url = identity.appURL {
                appKey = "app:\(bundle):\(url.standardizedFileURL.path)"
            } else {
                appKey = "process:\(process.objectID):\(process.pid)"
            }
            if process.isRunningOutput { grouped["output:\(appKey)", default: []].append(Member(process: process, identity: identity)) }
            if process.isRunningInput { grouped["input:\(appKey)", default: []].append(Member(process: process, identity: identity)) }
        }
        return grouped.map { id, unsorted in
            let members = unsorted.sorted { $0.process.objectID < $1.process.objectID }
            let isInput = id.hasPrefix("input:")
            let identity = members.compactMap(\.identity).first
            let devices = members.flatMap { isInput ? $0.process.inputDevices : $0.process.outputDevices }
            let uids = Set(devices.map(\.uid))
            let uniqueRoute = uids.count == 1
                && members.allSatisfy { isInput || ($0.process.outputRouteIsComplete && !$0.process.outputDevices.isEmpty) }
            let uid = uniqueRoute ? uids.first : nil
            let owners = Set(members.compactMap { $0.identity?.ownerInstanceID })
            let owner = owners.count == 1 ? owners.first : nil
            let route = Array(Set(devices.map { "route:\($0.id):\($0.uid):\($0.routeFingerprint)" })).sorted()
            return ApplicationAudioMixerRow(
                id: id, name: identity?.name ?? members.first?.process.bundleID ?? "\(members[0].process.pid)",
                bundleID: identity?.bundleID ?? members.first?.process.bundleID, appURL: identity?.appURL,
                processIDs: members.map { $0.process.objectID }, outputDeviceUID: uid,
                outputDeviceName: uniqueRoute ? devices.first?.name : nil, isInput: isInput,
                gain: 1, isMuted: false,
                canAdjust: enabled && !isInput && uniqueRoute && owner != nil && members.allSatisfy { $0.identity != nil },
                instanceFingerprint: members.map { "\($0.process.objectID):\($0.process.pid):\($0.identity?.instanceID ?? "unknown")" }
                    + route, ownerInstanceID: owner, routeFingerprint: route
            )
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
}

@MainActor
extension ApplicationAudioSessionControlling {
    var cleanupErrors: [OSStatus] { [] }
    var hasUnreleasedResources: Bool { false }
}
