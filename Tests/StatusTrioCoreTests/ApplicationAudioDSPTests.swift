import CoreAudio
import ApplicationAudioDSP
import XCTest

final class ApplicationAudioDSPTests: XCTestCase {
    func testGainClampsAndMuteProducesSilence() throws {
        let context = try XCTUnwrap(STAudioDSPCreate(0.5))
        defer { STAudioDSPDestroy(context) }
        XCTAssertEqual(STAudioDSPGetGain(context), 0.5)
        STAudioDSPSetGain(context, -1)
        XCTAssertEqual(STAudioDSPGetGain(context), 0)
        STAudioDSPSetGain(context, 2)
        XCTAssertEqual(STAudioDSPGetGain(context), 1)
        STAudioDSPSetGain(context, .nan)
        XCTAssertEqual(STAudioDSPGetGain(context), 1)
        STAudioDSPSetGain(context, 0)
        XCTAssertEqual(render(context, samples: [0.4, -0.8, 1, -1]), [0, 0, 0, 0])
    }

    func testSynchronousGainChangesOnlyOutputSamples() throws {
        let context = try XCTUnwrap(STAudioDSPCreate(0.25))
        defer { STAudioDSPDestroy(context) }
        XCTAssertEqual(render(context, samples: [1, -1, 0.5, -0.5]), [0.25, -0.25, 0.125, -0.125])
        STAudioDSPSetGain(context, 1)
        XCTAssertEqual(render(context, samples: [1, -1]), [1, -1])
    }

    func testPlanarInputPreservesChannelOrderInInterleavedOutput() throws {
        let context = try XCTUnwrap(STAudioDSPCreate(0.5))
        defer { STAudioDSPDestroy(context) }
        var left: [Float] = [1, -1]
        var right: [Float] = [0.5, -0.5]
        var result = Array(repeating: Float(42), count: 4)
        left.withUnsafeMutableBytes { leftBytes in
            right.withUnsafeMutableBytes { rightBytes in
                result.withUnsafeMutableBytes { outputBytes in
                    let input = AudioBufferList.allocate(maximumBuffers: 2)
                    defer { input.unsafeMutablePointer.deallocate() }
                    input.unsafeMutablePointer.pointee.mNumberBuffers = 2
                    input[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftBytes.count), mData: leftBytes.baseAddress)
                    input[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightBytes.count), mData: rightBytes.baseAddress)
                    var output = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                        mNumberChannels: 2, mDataByteSize: UInt32(outputBytes.count), mData: outputBytes.baseAddress))
                    STAudioDSPProcess(context, input.unsafePointer, &output)
                }
            }
        }
        XCTAssertEqual(result, [0.5, 0.25, -0.5, -0.25])
        XCTAssertEqual(left, [1, -1])
        XCTAssertEqual(right, [0.5, -0.5])
    }

    func testShortInputSilencesOutputWithoutReadingPastTheAvailableFrames() throws {
        let context = try XCTUnwrap(STAudioDSPCreate(1))
        defer { STAudioDSPDestroy(context) }
        XCTAssertEqual(render(context, samples: [1, -1, 0.5, -0.5], inputByteSize: 8), [0, 0, 0, 0])
    }

    func testOnlyPackedFloat32StereoFormatsAreAccepted() {
        var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        XCTAssertTrue(STAudioDSPSupportsFormat(&format))
        format.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
        format.mBytesPerFrame = 4
        format.mBytesPerPacket = 4
        XCTAssertTrue(STAudioDSPSupportsFormat(&format))
        format.mChannelsPerFrame = 6
        XCTAssertFalse(STAudioDSPSupportsFormat(&format))
        format.mChannelsPerFrame = 2
        format.mBitsPerChannel = 16
        XCTAssertFalse(STAudioDSPSupportsFormat(&format))
        format.mBitsPerChannel = 32
        format.mSampleRate = .nan
        XCTAssertFalse(STAudioDSPSupportsFormat(&format))
    }

    private func render(_ context: OpaquePointer, samples: [Float], inputByteSize: UInt32? = nil) -> [Float] {
        var inputSamples = samples
        var outputSamples = Array(repeating: Float(42), count: samples.count)
        inputSamples.withUnsafeMutableBytes { input in
            outputSamples.withUnsafeMutableBytes { output in
                var inputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 2, mDataByteSize: inputByteSize ?? UInt32(input.count), mData: input.baseAddress))
                var outputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 2, mDataByteSize: UInt32(output.count), mData: output.baseAddress))
                STAudioDSPProcess(context, &inputList, &outputList)
            }
        }
        XCTAssertEqual(inputSamples, samples)
        return outputSamples
    }
}
