@preconcurrency import ScreenCaptureKit
@preconcurrency import CoreMedia
import CoreAudio
import Foundation

@MainActor
final class AudioRhythmMonitor: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var captureStream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.islandnook.audio-rhythm", qos: .userInteractive)
    private let levelLock = NSLock()
    nonisolated(unsafe) private var storedLevels: [Double] = [0.28, 0.42, 0.34, 0.48, 0.3]

    func start() {
        guard captureStream == nil else { return }
        Task { await beginCapture() }
    }

    func stop() {
        guard let stream = captureStream else { return }
        captureStream = nil
        Task { try? await stream.stopCapture() }
    }

    nonisolated func levels() -> [Double] {
        levelLock.lock()
        defer { levelLock.unlock() }
        return storedLevels
    }

    private func beginCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            configuration.showsCursor = false
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
            captureStream = stream
        } catch {
            captureStream = nil
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid,
              let format = sampleBuffer.formatDescription,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return }

        var requiredSize = 0
        var blockBuffer: CMBlockBuffer?
        let sizingStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard sizingStatus == noErr, requiredSize > 0 else { return }

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: requiredSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }
        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        var sumSquares = 0.0
        var peak = 0.0
        var sampleCount = 0
        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            guard let data = buffer.mData else { continue }
            if description.mFormatFlags & kAudioFormatFlagIsFloat != 0, description.mBitsPerChannel == 32 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<count {
                    let value = Double(samples[index])
                    sumSquares += value * value
                    peak = max(peak, abs(value))
                }
                sampleCount += count
            } else if description.mBitsPerChannel == 16 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = data.assumingMemoryBound(to: Int16.self)
                for index in 0..<count {
                    let value = Double(samples[index]) / Double(Int16.max)
                    sumSquares += value * value
                    peak = max(peak, abs(value))
                }
                sampleCount += count
            }
        }
        guard sampleCount > 0 else { return }

        let rms = sqrt(sumSquares / Double(sampleCount))
        let energy = min(1, max(0.045, rms * 5.8))
        let transient = min(1, max(energy, peak * 1.7))
        let incoming = [energy * 0.78, transient, energy, transient * 0.82, energy * 0.68]
        levelLock.lock()
        storedLevels = zip(storedLevels, incoming).map { previous, next in previous * 0.52 + next * 0.48 }
        levelLock.unlock()
    }
}
