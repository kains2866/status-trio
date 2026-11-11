import AudioToolbox
import XCTest
@testable import StatusTrioCore

@MainActor
final class AudioPanelMapperTests: XCTestCase {
    func testNativeReadbackRevisionIsScopedAwayFromSelectedExternalBackend() {
        let localization = makeLocalization(.english)
        let devices = [
            AudioOutputDevice(id: 1, name: "Current", uid: "current", isCurrent: true),
            AudioOutputDevice(id: 2, name: "USB", uid: "usb", isCurrent: false)
        ]
        for source in [VolumeControlSource.native, .directDDC, .betterDisplay] {
            let state = AudioPanelMapper.volume(
                VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Current", currentDevice: devices[0],
                             outputDevices: devices, canSetVolume: true, canMute: true, controlSource: source,
                             nativeDeviceLevelReadbackRevision: 7),
                controllerAvailable: true, localization: localization)
            XCTAssertEqual(state.rows.first { $0.selected }?.nativeDeviceLevelReadbackRevision,
                           source == .native ? 7 : 0)
            XCTAssertEqual(state.rows.first { !$0.selected }?.nativeDeviceLevelReadbackRevision, 7)
        }
    }

    func testMissingOrBlankUIDKeepsReadableLevelsButDisablesTargetedControls() {
        let localization = makeLocalization(.english)
        let level = AudioDeviceLevel(scalar: 0.7, canAdjust: true, muteState: .unmuted, canMute: true)
        for uid: String? in [nil, "", "  \n\t"] {
            let outputDevices = [
                AudioOutputDevice(id: 1, name: "Current", uid: uid, isCurrent: true, level: level),
                AudioOutputDevice(id: 2, name: "Other", uid: uid, isCurrent: false, level: level)
            ]
            let output = AudioPanelMapper.volume(
                VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Current", currentDevice: outputDevices[0],
                             outputDevices: outputDevices, canSetVolume: true, canMute: true),
                controllerAvailable: true, localization: localization)
            let input = AudioPanelMapper.input(makeInputStatus(devices: [
                AudioInputDevice(id: 1, uid: uid, name: "Current", level: level),
                AudioInputDevice(id: 2, uid: uid, name: "Other", level: level)
            ], defaultDeviceID: 1, scalar: 0.4), localization: localization)
            for rows in [output.rows, input.rows] {
                XCTAssertEqual(rows.count, 2)
                XCTAssertTrue(rows.allSatisfy { $0.enabled }, "route selection remains available")
                XCTAssertTrue(rows.allSatisfy { $0.level?.scalar != nil })
                XCTAssertTrue(rows.allSatisfy { $0.level?.canAdjust == false && $0.level?.canMute == false })
            }
            XCTAssertTrue(output.canAdjust, "legacy current-route fallback stays supported")
            XCTAssertTrue(output.canMute)
            XCTAssertTrue(input.canAdjust)
            XCTAssertTrue(input.canMute)
        }
    }

    func testInputRowsKeepIndependentLevelsAndScopeAcknowledgementsByUID() {
        let request = UUID()
        let level = AudioDeviceLevel(scalar: 0.8, canAdjust: true, muteState: .muted, canMute: true)
        var status = makeInputStatus(devices: [
            AudioInputDevice(id: 1, uid: "current", name: "Built-in"),
            AudioInputDevice(id: 2, uid: "other", name: "USB", level: level)
        ], defaultDeviceID: 1, scalar: 0.4)
        status.completedDeviceScalarRequestID = request
        status.completedDeviceScalarDeviceID = 2
        status.completedDeviceScalarDeviceUID = "other"
        let state = AudioPanelMapper.input(status, localization: makeLocalization(.english))
        XCTAssertEqual(state.rows.first { $0.key.id == 1 }?.level?.scalar, 0.4)
        XCTAssertEqual(state.rows.first { $0.key.id == 2 }?.level, level)
        XCTAssertEqual(state.rows.first { $0.key.id == 2 }?.completedLevelRequestID, request)
        XCTAssertNil(state.rows.first { $0.key.id == 1 }?.completedLevelRequestID)
        status.completedDeviceScalarDeviceUID = "replaced"
        XCTAssertNil(AudioPanelMapper.input(status, localization: makeLocalization(.english))
            .rows.first { $0.key.id == 2 }?.completedLevelRequestID)
    }

    func testInputRowsKeepStableIdentityAndDisambiguateDuplicateNames() {
        let localization = makeLocalization(.english)
        let first = AudioInputDevice(id: AudioDeviceID(1), uid: "first", name: "Studio Mic")
        let second = AudioInputDevice(id: AudioDeviceID(2), uid: "second", name: "Studio Mic")
        for currentID in [first.id, second.id] {
            let status = makeInputStatus(devices: [first, second], defaultDeviceID: currentID)
            let state = AudioPanelMapper.input(status, localization: localization)

            XCTAssertEqual(state.rows.map(\.key.id), [1, 2])
            XCTAssertEqual(Set(state.rows.map(\.key)).count, 2)
            XCTAssertEqual(state.rows.map(\.name), ["Studio Mic", "Studio Mic"])
            XCTAssertTrue(state.rows.allSatisfy { $0.accessibilityLabel.contains("Studio Mic") })
            XCTAssertEqual(state.rows.filter(\.selected).map(\.key.id), [currentID])
        }
    }

    func testInputKeepsBusyAndCapabilitiesAsSeparateControlRules() {
        let localization = makeLocalization(.english)
        let busyButCapable = AudioPanelMapper.input(
            makeInputStatus(
                defaultDeviceID: AudioDeviceID(1),
                scalar: 0.4,
                canSetVolume: true,
                muteState: .unmuted,
                canSetMute: true,
                isBusy: true
            ),
            localization: localization
        )
        let readOnlyGain = AudioPanelMapper.input(
            makeInputStatus(
                defaultDeviceID: AudioDeviceID(1),
                scalar: 0.4,
                canSetVolume: false,
                muteState: .unmuted,
                canSetMute: true
            ),
            localization: localization
        )
        let muteUnavailable = AudioPanelMapper.input(
            makeInputStatus(
                defaultDeviceID: AudioDeviceID(1),
                scalar: 0.4,
                canSetVolume: true,
                muteState: .unmuted,
                canSetMute: false
            ),
            localization: localization
        )

        XCTAssertTrue(busyButCapable.isBusy)
        XCTAssertFalse(busyButCapable.canAdjust)
        XCTAssertFalse(busyButCapable.canMute)
        XCTAssertFalse(readOnlyGain.canAdjust)
        XCTAssertTrue(readOnlyGain.canMute)
        XCTAssertTrue(muteUnavailable.canAdjust)
        XCTAssertFalse(muteUnavailable.canMute)
    }

    func testInputPartialMuteAndUnavailableVolumeRemainVisibleWithoutInventedZero() {
        let localization = makeLocalization(.english)
        let partial = AudioPanelMapper.input(
            makeInputStatus(
                devices: [AudioInputDevice(id: AudioDeviceID(1), uid: "mic", name: "Mic")],
                defaultDeviceID: AudioDeviceID(1),
                scalar: nil,
                canSetVolume: true,
                muteState: .partial,
                canSetMute: true,
                isDefaultInputInUse: nil,
                error: .volumeFailed
            ),
            localization: localization
        )

        XCTAssertEqual(partial.scalar, nil)
        XCTAssertEqual(partial.percentageText, "—")
        XCTAssertFalse(partial.canAdjust)
        XCTAssertTrue(partial.canMute)
        XCTAssertEqual(partial.muteSymbol, "mic.fill")
        XCTAssertEqual(partial.muteTint, .secondary)
        XCTAssertEqual(partial.usageText, nil)
        XCTAssertEqual(partial.errorText, localization.string(.audioInputVolumeFailed))
        XCTAssertTrue(partial.showsDeviceList)
        XCTAssertEqual(partial.rows.map(\.name), ["Mic"])
    }

    func testInputUseMarkerAndErrorAreLocalizedInPanelState() {
        let english = makeLocalization(.english)
        let german = makeLocalization(.german)
        let status = makeInputStatus(
            devices: [AudioInputDevice(id: AudioDeviceID(1), uid: "mic", name: "Mic")],
            defaultDeviceID: AudioDeviceID(1),
            isDefaultInputInUse: true,
            error: .switchFailed
        )

        let englishState = AudioPanelMapper.input(status, localization: english)
        let germanState = AudioPanelMapper.input(status, localization: german)

        XCTAssertEqual(englishState.usageText, "In Use")
        XCTAssertEqual(englishState.errorText, "Could not switch input device.")
        XCTAssertEqual(germanState.usageText, "In Benutzung")
        XCTAssertEqual(germanState.errorText, "Eingabegerät konnte nicht gewechselt werden.")
    }

    func testVolumeUnavailableScalarStaysUnavailableAndControlsRespectCapabilities() {
        let localization = makeLocalization(.english)
        let status = VolumeStatus(
            scalar: nil,
            isMuted: false,
            deviceName: nil,
            canSetVolume: true,
            canMute: false
        )

        let state = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertNil(state.scalar)
        XCTAssertEqual(state.percentageText, "—")
        XCTAssertFalse(state.canAdjust)
        XCTAssertFalse(state.canMute)
        XCTAssertEqual(state.summary.title, "No default output device")
    }

    func testOutputSummaryRejectsCachedIconWhenLiveDeviceNameHasChanged() {
        let localization = makeLocalization(.english)
        let cachedDevice = AudioOutputDevice(
            id: AudioDeviceID(42),
            name: "Cached headphones",
            uid: "headphones",
            isCurrent: true,
            transport: .bluetooth
        )
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "Renamed output",
                outputDevices: [cachedDevice],
                canSetVolume: true,
                canMute: true
            ),
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertEqual(state.summary.title, "Renamed output")
        XCTAssertEqual(
            state.summary.symbol,
            .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil)
        )
    }

    func testOutputSummaryUsesStaticSpeakerFallbackWithoutDeviceMetadata() {
        let localization = makeLocalization(.english)
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.2,
                isMuted: true,
                deviceName: "Live output",
                outputDevices: [],
                canSetVolume: true,
                canMute: true
            ),
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertEqual(
            state.summary.symbol,
            .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil)
        )
        XCTAssertEqual(state.muteSymbol, "speaker.slash.fill")
    }

    func testOutputSummaryUsesMatchingCurrentDeviceIcon() {
        let localization = makeLocalization(.english)
        let device = AudioOutputDevice(
            id: AudioDeviceID(43),
            name: "Bluetooth Headphones",
            uid: "headphones",
            isCurrent: true,
            transport: .bluetooth
        )
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: device.name,
                outputDevices: [device],
                canSetVolume: true,
                canMute: true
            ),
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertNotEqual(
            state.summary.symbol,
            .symbol(name: "speaker.wave.2.fill", variableValue: nil, fallback: nil)
        )
    }

    func testOutputRowsUseStableUIDKeysOrderingAndLocalExpansionProjection() {
        let localization = makeLocalization(.english)
        let first = AudioOutputDevice(
            id: AudioDeviceID(1),
            name: "Studio Speaker",
            uid: "first",
            isCurrent: false
        )
        let second = AudioOutputDevice(
            id: AudioDeviceID(2),
            name: "Studio Speaker",
            uid: "second",
            isCurrent: true
        )
        let third = AudioOutputDevice(
            id: AudioDeviceID(3),
            name: nil,
            uid: nil,
            isCurrent: false
        )
        let status = VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: nil,
            currentDevice: second,
            outputDevices: [first, second, third],
            canSetVolume: true,
            canMute: true
        )

        let state = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(order: ["second"], visibleLimit: 1),
            localization: localization
        )

        XCTAssertEqual(state.rows.map(\.key), [
            PanelAudioDeviceID(id: 2, uid: "second"),
            PanelAudioDeviceID(id: 1, uid: "first"),
            PanelAudioDeviceID(id: 3, uid: nil)
        ])
        XCTAssertEqual(Set(state.rows.map(\.key)).count, 3)
        XCTAssertEqual(state.visibleRows(expanded: false).map(\.key.id), [2])
        XCTAssertEqual(state.visibleRows(expanded: true).map(\.key.id), [2, 1, 3])
        XCTAssertTrue(state.hasHiddenRows)
        XCTAssertTrue(state.rows[0].selected)
        XCTAssertNotEqual(state.rows[0].accessibilityLabel, state.rows[1].accessibilityLabel)
        XCTAssertEqual(state.rows[2].name, "Unknown output device")
    }

    func testHiddenOutputRowsAreDroppedExceptTheActiveOutput() {
        let localization = makeLocalization(.english)
        let speakers = AudioOutputDevice(id: 1, name: "Speakers", uid: "speakers", isCurrent: false)
        let display = AudioOutputDevice(id: 2, name: "Display", uid: "display", isCurrent: true)
        let airPods = AudioOutputDevice(id: 3, name: "AirPods", uid: "airpods", isCurrent: false)
        let status = VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: nil,
            currentDevice: display,
            outputDevices: [speakers, display, airPods],
            canSetVolume: true,
            canMute: true
        )

        let state = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(hiddenUIDs: ["speakers", "display"]),
            localization: localization
        )

        XCTAssertEqual(state.rows.map(\.key.uid), ["display", "airpods"])
        XCTAssertTrue(state.showsDeviceList)

        let single = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(hiddenUIDs: ["speakers", "airpods"]),
            localization: localization
        )

        XCTAssertEqual(single.rows.map(\.key.uid), ["display"])
        XCTAssertTrue(single.showsDeviceList, "one device retains its named level row")
    }

    func testHiddenActiveOutputKeepsTheListEvenWhenItIsTheOnlyRow() {
        let localization = makeLocalization(.english)
        let speakers = AudioOutputDevice(id: 1, name: "Speakers", uid: "speakers", isCurrent: false)
        let display = AudioOutputDevice(id: 2, name: "Display", uid: "display", isCurrent: true)
        let airPods = AudioOutputDevice(id: 3, name: "AirPods", uid: "airpods", isCurrent: false)
        let status = VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: nil,
            currentDevice: display,
            outputDevices: [speakers, display, airPods],
            canSetVolume: true,
            canMute: true
        )

        let state = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(hiddenUIDs: ["speakers", "display", "airpods"]),
            localization: localization
        )

        XCTAssertEqual(state.rows.map(\.key.uid), ["display"])
        XCTAssertTrue(
            state.showsDeviceList,
            "hiding every device must still show the active output the panel keeps"
        )
    }

    func testInputRowsFollowTheSavedOrderAndDropHiddenDevicesExceptTheCurrentInput() {
        let localization = makeLocalization(.english)
        let builtIn = AudioInputDevice(id: AudioDeviceID(1), uid: "built-in", name: "MacBook Pro Microphone")
        let airPods = AudioInputDevice(id: AudioDeviceID(2), uid: "airpods", name: "AirPods")
        let usb = AudioInputDevice(id: AudioDeviceID(3), uid: "usb", name: "USB Mic")
        let camera = AudioInputDevice(id: AudioDeviceID(4), uid: "camera", name: "Camera Mic")
        let status = makeInputStatus(
            devices: [builtIn, airPods, usb, camera],
            defaultDeviceID: builtIn.id
        )

        let unordered = AudioPanelMapper.input(status, localization: localization)
        XCTAssertEqual(
            unordered.rows.map(\.key.uid),
            ["airpods", "camera", "built-in", "usb"],
            "without a saved order names sort independently of the current input"
        )

        let state = AudioPanelMapper.input(
            status,
            deviceList: AudioInputListPreferences(
                order: ["usb", "airpods"],
                hiddenUIDs: ["airpods", "built-in"]
            ),
            localization: localization
        )

        // built-in is hidden but stays as the current input; camera is not in
        // the saved order, so it follows the ordered devices.
        XCTAssertEqual(state.rows.map(\.key.uid), ["usb", "camera", "built-in"])
        XCTAssertEqual(state.rows.filter(\.selected).map(\.key.uid), ["built-in"])
    }

    func testInputHidesTheDeviceListWhenNoDefaultExistsAndEveryDeviceIsHidden() {
        let localization = makeLocalization(.english)
        let devices = [
            AudioInputDevice(id: AudioDeviceID(1), uid: "built-in", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: AudioDeviceID(2), uid: "usb", name: "USB Mic")
        ]
        let status = makeInputStatus(devices: devices, defaultDeviceID: nil)

        let state = AudioPanelMapper.input(
            status,
            deviceList: AudioInputListPreferences(hiddenUIDs: ["built-in", "usb"]),
            localization: localization
        )

        XCTAssertTrue(state.rows.isEmpty)
        XCTAssertFalse(state.showsDeviceList, "an empty list has nothing to show")
    }

    func testInputKeepsTheDeviceListWhenOneUnhiddenRowRemains() {
        let localization = makeLocalization(.english)
        let devices = [
            AudioInputDevice(id: AudioDeviceID(1), uid: "built-in", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: AudioDeviceID(2), uid: "usb", name: "USB Mic")
        ]
        let status = makeInputStatus(devices: devices, defaultDeviceID: nil)

        let state = AudioPanelMapper.input(
            status,
            deviceList: AudioInputListPreferences(hiddenUIDs: ["usb"]),
            localization: localization
        )

        XCTAssertEqual(state.rows.map(\.key.uid), ["built-in"])
        XCTAssertTrue(state.showsDeviceList, "input keeps the list for a single row")
    }

    func testInputRowsHonorTheVisibleLimitWithLocalExpansion() {
        let localization = makeLocalization(.english)
        let devices = (1...4).map {
            AudioInputDevice(id: AudioDeviceID($0), uid: "mic-\($0)", name: "Mic \($0)")
        }
        let status = makeInputStatus(devices: devices, defaultDeviceID: devices[0].id)

        let limited = AudioPanelMapper.input(
            status,
            deviceList: AudioInputListPreferences(visibleLimit: 2),
            localization: localization
        )

        XCTAssertEqual(limited.rows.count, 4, "rows stay complete; only the view collapses them")
        XCTAssertTrue(limited.hasHiddenRows)
        XCTAssertEqual(limited.visibleRows(expanded: false).map(\.key.uid), ["mic-1", "mic-2"])
        XCTAssertEqual(limited.visibleRows(expanded: true).count, 4)
        XCTAssertEqual(limited.expandLabel, "Expand")
        XCTAssertEqual(limited.collapseLabel, "Collapse")

        let unlimited = AudioPanelMapper.input(
            status,
            deviceList: AudioInputListPreferences(visibleLimit: nil),
            localization: localization
        )

        XCTAssertFalse(unlimited.hasHiddenRows)
        XCTAssertEqual(unlimited.visibleRows(expanded: false).count, 4)
    }

    func testInputSettingsListKeepsTheSavedOrderForHiddenDevices() {
        let devices = [
            AudioInputDevice(id: AudioDeviceID(1), uid: "a", name: "A"),
            AudioInputDevice(id: AudioDeviceID(2), uid: "b", name: "B"),
            AudioInputDevice(id: AudioDeviceID(3), uid: nil, name: "C")
        ]

        let listed = AudioInputPresentation.ordered(
            devices,
            currentID: AudioDeviceID(1),
            order: ["b", "a"],
            locale: Locale(identifier: "en_US"),
            unknownName: "Unknown"
        )

        XCTAssertEqual(
            listed.map(\.id),
            [2, 1, 3],
            "the Settings list follows the saved order whether or not a device is hidden"
        )
    }

    func testInputSwitchKeepsTheOrderAndCollapsedRowsStable() {
        let localization = makeLocalization(.english)
        let devices = (1...4).map {
            AudioInputDevice(id: AudioDeviceID($0), uid: "mic-\($0)", name: "Mic \($0)")
        }

        for order in [[], ["mic-4", "mic-1"]] {
            let expected = order.isEmpty
                ? ["mic-1", "mic-2", "mic-3", "mic-4"]
                : ["mic-4", "mic-1", "mic-2", "mic-3"]
            for limit: Int? in [0, 3, nil] {
                for device in devices {
                    let state = AudioPanelMapper.input(
                        makeInputStatus(devices: devices, defaultDeviceID: device.id),
                        deviceList: AudioInputListPreferences(order: order, visibleLimit: limit),
                        localization: localization
                    )

                    XCTAssertEqual(state.rows.map(\.key.uid), expected)
                    XCTAssertEqual(state.rows.filter(\.selected).map(\.key.uid), [device.uid])
                    XCTAssertEqual(state.visibleRows(expanded: false).map(\.key.uid), Array(expected.prefix(limit ?? expected.count)))
                    XCTAssertEqual(state.overflowRows.map(\.key.uid), Array(expected.dropFirst(limit ?? expected.count)))
                    XCTAssertEqual(state.visibleRows(expanded: true).map(\.key.uid), expected)
                    XCTAssertEqual(state.hasHiddenRows, limit.map { $0 < devices.count } ?? false)
                }
            }
        }
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "AudioPanelMapperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }

    private func makeInputStatus(
        devices: [AudioInputDevice] = [],
        defaultDeviceID: AudioDeviceID? = nil,
        scalar: Double? = 0.4,
        canSetVolume: Bool = true,
        muteState: AudioInputMuteState? = .unmuted,
        canSetMute: Bool = true,
        isBusy: Bool = false,
        isDefaultInputInUse: Bool? = false,
        error: AudioInputError? = nil
    ) -> AudioInputStatus {
        AudioInputStatus(
            devices: devices,
            defaultDeviceID: defaultDeviceID,
            deviceName: nil,
            scalar: scalar,
            canSetVolume: canSetVolume,
            muteState: muteState,
            canSetMute: canSetMute,
            isRefreshing: false,
            isBusy: isBusy,
            error: error,
            isDefaultInputInUse: isDefaultInputInUse
        )
    }
}

@MainActor
final class AudioPanelMapperListeningControlTests: XCTestCase {
    private final class EndpointProvider: CoreAudioBluetoothEndpointProviding {
        let endpoints: [BluetoothListeningModeEndpoint]
        init(_ endpoints: [BluetoothListeningModeEndpoint]) { self.endpoints = endpoints }
        func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] { endpoints }
    }

    private func makeLocalization() -> Localization {
        let suiteName = "AudioPanelMapperListeningControlTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    func testHidingOtherOutputsKeepsCurrentAirPodsListeningControls() {
        let localization = makeLocalization()
        let endpoint = BluetoothListeningModeEndpoint(
            audioDeviceID: 42,
            capability: BluetoothListeningModeCapability(
                audioDeviceID: 42,
                availableModes: [.noiseCancellation, .transparency],
                currentMode: .noiseCancellation,
                canSet: true
            ),
            isDefaultOutput: true,
            bluetoothAddress: "aa:bb:cc:dd:ee:ff"
        )
        let controller = BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: FakeListeningModeBackend(),
                sleeper: ImmediateListeningModeSleeper(),
                retryAttempts: 1,
                retryDelay: .milliseconds(1)
            ),
            endpointProvider: EndpointProvider([endpoint]),
            listenerBackend: FakeListeningModeListenerBackend(),
            failureClearDelay: .milliseconds(1)
        )
        controller.refresh(devices: [BluetoothDevice(
            id: "AA:BB:CC:DD:EE:FF", name: "AirPods Pro", kind: .audio, isConnected: true
        )])
        defer { controller.stop() }

        let airPods = AudioOutputDevice(id: 42, name: "AirPods Pro", uid: "pods", isCurrent: true, transport: .bluetooth)
        let speakers = AudioOutputDevice(id: 1, name: "Speakers", uid: "speaker", isCurrent: false)
        let status = VolumeStatus(
            scalar: 0.5, isMuted: false, deviceName: "AirPods Pro",
            currentDevice: airPods, outputDevices: [speakers, airPods],
            canSetVolume: true, canMute: true
        )

        let state = AudioPanelMapper.volume(
            status,
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(hiddenUIDs: ["speaker"]),
            listeningModes: controller,
            localization: localization
        )

        XCTAssertEqual(state.rows.count, 1, "Only the current AirPods remain after hiding others")
        XCTAssertEqual(state.rows.first?.listeningMode?.isControllable, true)
        XCTAssertTrue(state.showsDeviceList,
                      "The list must stay visible so the surviving listening-mode control is reachable")
    }
}
