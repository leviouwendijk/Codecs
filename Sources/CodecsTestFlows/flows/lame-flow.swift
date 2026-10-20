import Foundation
import MediaCore
import MediaAV
import MediaTranscoding
import CodecsLAME
import TestFlows

extension CodecsFlowSuite {
    static var lameFlow: TestFlow {
        TestFlow("audio-codec", tags: ["audio", "codec", "mp3"]) {
            Step("WAV mono and stereo transcode to verified MP3 without deleting originals") {
                for channels in [1, 2] {
                    let workspace = try CodecsTestWorkspace("mp3-\(channels)")
                    defer { workspace.remove() }
                    let source = workspace.file("original.wav")
                    let output = workspace.file("encoded.mp3")
                    try makePCM16WAV(channelCount: channels, frames: 48_000).write(to: source)
                    let result = try await MediaAudioTranscoder().transcode(
                        source, to: output, using: LAMEEncoder()
                    )
                    try Expect.true(FileManager.default.fileExists(atPath: source.path), "codecs.original.exists")
                    try Expect.true(FileManager.default.fileExists(atPath: output.path), "codecs.mp3.exists")
                    try Expect.equal(result.channelCount, channels, "codecs.channels")
                    try Expect.equal(result.sampleRate, 48_000, "codecs.sample-rate")
                    try Expect.true(result.outputBytes > 0, "codecs.output-bytes")
                    let collector = CodecsAudioLevelCollector()
                    try await MediaAssetAudioReader().read(output) { chunk in
                        try collector.consume(chunk.buffer)
                    }
                    try Expect.true(collector.rms > 0.025, "codecs.audible-output")
                }
            }
            Step("Existing output is never replaced") {
                let workspace = try CodecsTestWorkspace("mp3-collision")
                defer { workspace.remove() }
                let source = workspace.file("original.wav")
                let output = workspace.file("encoded.mp3")
                try makePCM16WAV(frames: 48_000).write(to: source)
                let protected = Data("untouched".utf8)
                try protected.write(to: output)
                do {
                    _ = try await MediaAudioTranscoder().transcode(source, to: output, using: LAMEEncoder())
                    throw MediaAudioTranscodeError.verificationFailed
                } catch MediaAudioTranscodeError.destinationExists {
                    try Expect.equal(try Data(contentsOf: output), protected, "codecs.no-overwrite")
                }
            }
        }
    }
}

private final class CodecsAudioLevelCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var total_frames: Int64 = 0
    private var total_power: Double = 0

    func consume(_ buffer: MediaAudioBuffer) throws {
        guard buffer.sample == .float32, buffer.frameCount > 0,
              buffer.channelCount > 0,
              buffer.frameCount <= Int.max / (buffer.channelCount * 4),
              buffer.data.count >= buffer.frameCount * buffer.channelCount * 4 else {
            throw MediaAudioTranscodeError.unsupportedBuffer
        }
        let count = buffer.frameCount * buffer.channelCount
        let power = buffer.data.withUnsafeBytes { bytes -> Double in
            var sum: Double = 0
            for index in 0..<count {
                let sample = Double(bytes.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<Float>.size,
                    as: Float.self
                ))
                sum += sample * sample
            }
            return sum / Double(count)
        }
        lock.lock()
        defer { lock.unlock() }
        total_power += power * Double(buffer.frameCount)
        total_frames += Int64(buffer.frameCount)
    }

    var rms: Double {
        lock.lock()
        defer { lock.unlock() }
        guard total_frames > 0 else { return 0 }
        return (total_power / Double(total_frames)).squareRoot()
    }
}
