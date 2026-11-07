import XCTest
@testable import StatusTrioCore

final class AudioDeviceLevelDraftTests: XCTestCase {
    private let first = PanelAudioDeviceID(id: 1, uid: "first")
    private let replacement = PanelAudioDeviceID(id: 1, uid: "replacement")

    func testGestureCapturesUIDAndDoesNotWriteReplacement() {
        var draft = AudioDeviceLevelDraft()
        draft.receive(key: first, scalar: 0.3, canAdjust: true)
        draft.setEditing(true, key: first)
        XCTAssertEqual(draft.change(0.8, key: first)?.key, first)
        draft.receive(key: replacement, scalar: 0.2, canAdjust: true)
        XCTAssertNil(draft.change(0.9, key: replacement))
        XCTAssertEqual(draft.value, 0.2)
    }

    func testOutputMouseUpKeepsDraftUntilReadbackAfterTheWrite() {
        var draft = AudioDeviceLevelDraft()
        draft.receive(key: first, scalar: 0.3, canAdjust: true, nativeDeviceLevelReadbackRevision: 4)
        draft.setEditing(true, key: first)
        _ = draft.change(0.8, key: first)
        draft.setEditing(false, key: first)
        XCTAssertEqual(draft.value, 0.8, "mouseup must not restore the pre-write scalar")
        draft.receive(key: first, scalar: 0.3, canAdjust: true, nativeDeviceLevelReadbackRevision: 4)
        XCTAssertEqual(draft.value, 0.8, "an unrelated render with the old revision is not a new readback")
        draft.receive(key: first, scalar: 0.8, canAdjust: true, nativeDeviceLevelReadbackRevision: 5)
        XCTAssertEqual(draft.value, 0.8)
    }

    func testOutputSameValueFailureReadbackReleasesDraftWithoutTimeout() {
        var draft = AudioDeviceLevelDraft()
        draft.receive(key: first, scalar: 0.3, canAdjust: true, nativeDeviceLevelReadbackRevision: 4)
        draft.setEditing(true, key: first)
        _ = draft.change(0.8, key: first)
        draft.setEditing(false, key: first)
        XCTAssertEqual(draft.value, 0.8)
        draft.receive(key: first, scalar: 0.3, canAdjust: true, nativeDeviceLevelReadbackRevision: 5)
        XCTAssertEqual(draft.value, 0.3, "fresh unchanged readback rejects the optimistic value")
    }

    func testOutputFreshReadbackBeforeMouseUpBecomesTheFinalValue() {
        var draft = AudioDeviceLevelDraft()
        draft.receive(key: first, scalar: 0.3, canAdjust: true, nativeDeviceLevelReadbackRevision: 4)
        draft.setEditing(true, key: first)
        _ = draft.change(0.8, key: first)
        draft.receive(key: first, scalar: 0.6, canAdjust: true, nativeDeviceLevelReadbackRevision: 5)
        XCTAssertEqual(draft.value, 0.8, "the pointer owns presentation during the gesture")
        draft.setEditing(false, key: first)
        XCTAssertEqual(draft.value, 0.6)
    }

    func testOutputExternalAuthoritativeScalarChangeReleasesDraftWithoutNativeRevision() {
        var draft = AudioDeviceLevelDraft()
        draft.receive(key: first, scalar: 0.3, canAdjust: true)
        draft.setEditing(true, key: first)
        _ = draft.change(0.8, key: first)
        draft.setEditing(false, key: first)
        XCTAssertEqual(draft.value, 0.8)
        draft.receive(key: first, scalar: 0.6, canAdjust: true)
        XCTAssertEqual(draft.value, 0.6)
    }

    func testInputOnlyMatchingAcknowledgementReleasesPendingDraft() throws {
        var draft = AudioDeviceLevelDraft(waitsForAcknowledgement: true)
        draft.receive(key: first, scalar: 0.3, canAdjust: true)
        draft.setEditing(true, key: first)
        let request = try XCTUnwrap(draft.change(0.8, key: first))
        draft.setEditing(false, key: first)
        draft.receive(key: first, scalar: 0.3, canAdjust: true, completedRequestID: UUID())
        XCTAssertEqual(draft.value, 0.8)
        draft.receive(key: first, scalar: 0.6, canAdjust: true, completedRequestID: request.requestID)
        XCTAssertEqual(draft.value, 0.6)
    }

    func testBackendTransitionCancelsGestureEvenWhenDeviceIdentityIsStable() {
        var draft = AudioDeviceLevelDraft()
        let old = VolumeControlInteractionIdentity(output: first, configuration: .default, transitionGeneration: 1)
        let new = VolumeControlInteractionIdentity(output: first, configuration: .default, transitionGeneration: 2)
        draft.receive(key: first, scalar: 0.3, canAdjust: true, controlIdentity: old)
        draft.setEditing(true, key: first)
        _ = draft.change(0.8, key: first)
        draft.receive(key: first, scalar: 0.5, canAdjust: true, controlIdentity: new)
        XCTAssertFalse(draft.isEditing)
        XCTAssertNil(draft.change(0.9, key: first))
        XCTAssertEqual(draft.value, 0.5)
    }

    func testFailureAndUnreadableValueReleasePendingDraft() {
        var draft = AudioDeviceLevelDraft(waitsForAcknowledgement: true)
        draft.receive(key: first, scalar: 0.3, canAdjust: true)
        draft.setEditing(true, key: first)
        _ = draft.change(0.8, key: first)
        draft.receive(key: first, scalar: 0.3, canAdjust: true, hasError: true)
        XCTAssertFalse(draft.isEditing)
        XCTAssertEqual(draft.value, 0.3)
        draft.receive(key: first, scalar: nil, canAdjust: false)
        XCTAssertNil(draft.change(0.8, key: first))
    }
}
