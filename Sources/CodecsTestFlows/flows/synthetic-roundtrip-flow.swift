import Foundation
import MediaCore
import MediaAV
import MediaTranscoding
import CodecsLAME
import TestFlows

extension CodecsFlowSuite {
    static var syntheticRoundtripFlow: TestFlow {
        TestFlow("synthetic-audio-roundtrip", tags: ["audio", "wav", "pcm", "mp3", "roundtrip"]) {
            Step("PCM16, PCM24 and Float32 WAV transcode across supported sample rates") {
                let cases: [(rate: Int, frequencies: [Double])] = [
                    (32_000, [440]),
                    (44_100, [440, 880]),
                    (48_000, [440, 880]),
                ]
                for audio in cases {
                    for encoding in SyntheticWAVEncoding.allCases {
                        let name = "\(audio.rate)-\(audio.frequencies.count)-\(encoding.rawValue)"
                        try await with_synthetic_workspace(name) { workspace in
                            let source = workspace.file("original.wav")
                            let output = workspace.file("encoded.mp3")
                            let source_bytes = make_synthetic_wav(
                                sample_rate: audio.rate,
                                channel_frequencies: audio.frequencies,
                                duration_seconds: 2,
                                encoding: encoding
                            )
                            try source_bytes.write(to: source)
                            let result = try await MediaAudioTranscoder().transcode(
                                source, to: output, using: LAMEEncoder()
                            )
                            try Expect.equal(result.sampleRate, audio.rate, "\(name).sample-rate")
                            try Expect.equal(result.channelCount, audio.frequencies.count, "\(name).channels")
                            try Expect.equal(result.sourceFrames, Int64(audio.rate * 2), "\(name).source-frames")
                            try Expect.true(result.outputBytes > 0, "\(name).output-bytes")
                            try Expect.true(
                                abs(result.decodedFrames - result.sourceFrames) <= Int64(audio.rate / 10),
                                "\(name).decoded-duration"
                            )
                            let decoded = try await read_synthetic_mp3(output)
                            try Expect.equal(decoded.rate, audio.rate, "\(name).decoded-rate")
                            try Expect.equal(decoded.channels.count, audio.frequencies.count, "\(name).decoded-channels")
                            for channel in audio.frequencies.indices {
                                let samples = decoded.channels[channel]
                                let rms = synthetic_rms(samples)
                                let expected = 0.35 / Double(2).squareRoot()
                                try Expect.true(
                                    rms > expected * 0.65 && rms < expected * 1.35,
                                    "\(name).channel-\(channel).amplitude"
                                )
                            }
                            if audio.frequencies.count == 2 {
                                let left_440 = synthetic_tone_amplitude(decoded.channels[0], rate: audio.rate, frequency: 440)
                                let left_880 = synthetic_tone_amplitude(decoded.channels[0], rate: audio.rate, frequency: 880)
                                let right_440 = synthetic_tone_amplitude(decoded.channels[1], rate: audio.rate, frequency: 440)
                                let right_880 = synthetic_tone_amplitude(decoded.channels[1], rate: audio.rate, frequency: 880)
                                try Expect.true(left_440 > 0.18 && left_440 > left_880 * 6, "\(name).left-identity")
                                try Expect.true(right_880 > 0.18 && right_880 > right_440 * 6, "\(name).right-identity")
                            }
                            try Expect.equal(try Data(contentsOf: source), source_bytes, "\(name).source-preserved")
                        }
                    }
                }
            }
            Step("Every LAME VBR quality preset produces a decodable MP3") {
                for quality in LAMEVBRQuality.allCases {
                    try await with_synthetic_workspace("vbr-\(quality.rawValue)") { workspace in
                        let source = workspace.file("source.wav")
                        let output = workspace.file("output.mp3")
                        try make_synthetic_wav(
                            sample_rate: 48_000,
                            channel_frequencies: [440, 880],
                            duration_seconds: 2,
                            encoding: .pcm16
                        ).write(to: source)
                        let result = try await MediaAudioTranscoder().transcode(
                            source, to: output, using: LAMEEncoder(quality: quality)
                        )
                        let decoded = try await read_synthetic_mp3(output)
                        try Expect.true(result.outputBytes > 0, "vbr-\(quality.rawValue).bytes")
                        try Expect.true(synthetic_rms(decoded.channels[0]) > 0.15, "vbr-\(quality.rawValue).audible")
                    }
                }
            }
            Step("Silence and longer streaming input remain valid") {
                try await with_synthetic_workspace("silence") { workspace in
                    let source = workspace.file("silence.wav")
                    let output = workspace.file("silence.mp3")
                    try make_synthetic_wav(
                        sample_rate: 44_100, channel_frequencies: [0, 0],
                        duration_seconds: 2, encoding: .pcm16
                    ).write(to: source)
                    _ = try await MediaAudioTranscoder().transcode(source, to: output, using: LAMEEncoder())
                    let decoded = try await read_synthetic_mp3(output)
                    try Expect.true(decoded.channels.allSatisfy { synthetic_rms($0) < 0.002 }, "silence.stays-silent")
                }
                try await with_synthetic_workspace("short-recording") { workspace in
                    let source = workspace.file("short.wav")
                    let output = workspace.file("short.mp3")
                    try make_synthetic_wav(
                        sample_rate: 44_100, channel_frequencies: [440],
                        duration_seconds: 0.04, encoding: .pcm16
                    ).write(to: source)
                    let result = try await MediaAudioTranscoder().transcode(source, to: output, using: LAMEEncoder())
                    let decoded = try await read_synthetic_mp3(output)
                    try Expect.equal(result.sourceFrames, Int64((0.04 * 44_100).rounded()), "short.source-frames")
                    try Expect.true(!decoded.channels.isEmpty && synthetic_rms(decoded.channels[0]) > 0.015, "short.audio-present")
                }
                try await with_synthetic_workspace("long-recording") { workspace in
                    let source = workspace.file("long.wav")
                    let output = workspace.file("long.mp3")
                    try make_synthetic_wav(
                        sample_rate: 48_000, channel_frequencies: [440, 880],
                        duration_seconds: 30, encoding: .pcm16
                    ).write(to: source)
                    let result = try await MediaAudioTranscoder().transcode(source, to: output, using: LAMEEncoder())
                    let decoded = try await read_synthetic_mp3(output)
                    try Expect.equal(result.sourceFrames, Int64(30 * 48_000), "long.source-frames")
                    try Expect.true(abs(result.decodedFrames - result.sourceFrames) < 4_800, "long.decoded-duration")
                    try Expect.true(synthetic_rms(decoded.channels[0]) > 0.15, "long.audio-present")
                }
            }
            Step("Unsupported sample rate fails without any output or leftovers") {
                try await with_synthetic_workspace("unsupported-rate") { workspace in
                    let source = workspace.file("unsupported.wav")
                    let output = workspace.file("output.mp3")
                    let original = make_synthetic_wav(
                        sample_rate: 22_050, channel_frequencies: [440],
                        duration_seconds: 2, encoding: .pcm16
                    )
                    try original.write(to: source)
                    var rejected = false
                    do {
                        _ = try await MediaAudioTranscoder().transcode(source, to: output, using: LAMEEncoder())
                    } catch MediaAudioTranscodeError.unsupportedBuffer {
                        rejected = true
                    }
                    try Expect.true(rejected, "unsupported.rate-rejected")
                    try Expect.true(!FileManager.default.fileExists(atPath: output.path), "unsupported.no-output")
                    try Expect.equal(try Data(contentsOf: source), original, "unsupported.source-preserved")
                    let remaining = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path)
                    try Expect.equal(remaining.sorted(), ["unsupported.wav"], "unsupported.no-temporary-files")
                }
            }
        }
    }
}

private func with_synthetic_workspace(
    _ name: String,
    _ body: (CodecsTestWorkspace) async throws -> Void
) async throws {
    let workspace = try CodecsTestWorkspace(name)
    var failure: Error?
    do {
        try await body(workspace)
    } catch {
        failure = error
    }
    // Always clean, including assertion/encoding failures. Surface cleanup errors.
    try FileManager.default.removeItem(at: workspace.root)
    if let failure { throw failure }
}

private final class SyntheticMP3Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var sample_rate = 0
    private var channel_data: [[Float]] = []

    func consume(_ buffer: MediaAudioBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard buffer.sample == .float32,
              buffer.frameCount > 0,
              buffer.channelCount > 0,
              buffer.frameCount <= Int.max / (buffer.channelCount * 4),
              buffer.data.count >= buffer.frameCount * buffer.channelCount * 4 else {
            throw MediaAudioTranscodeError.unsupportedBuffer
        }
        if sample_rate == 0 {
            sample_rate = buffer.sampleRate
            channel_data = (0..<buffer.channelCount).map { _ in [Float]() }
        }
        guard sample_rate == buffer.sampleRate, channel_data.count == buffer.channelCount else {
            throw MediaAudioTranscodeError.inconsistentFormat
        }
        buffer.data.withUnsafeBytes { bytes in
            for frame in 0..<buffer.frameCount {
                for channel in 0..<buffer.channelCount {
                    channel_data[channel].append(bytes.loadUnaligned(
                        fromByteOffset: (frame * buffer.channelCount + channel) * 4,
                        as: Float.self
                    ))
                }
            }
        }
    }

    func snapshot() -> (rate: Int, channels: [[Float]]) {
        lock.lock()
        defer { lock.unlock() }
        return (sample_rate, channel_data)
    }
}

private func read_synthetic_mp3(_ file: URL) async throws -> (rate: Int, channels: [[Float]]) {
    let collector = SyntheticMP3Collector()
    try await MediaAssetAudioReader().read(file) { chunk in
        try collector.consume(chunk.buffer)
    }
    return collector.snapshot()
}

private func synthetic_rms(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }
    return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
}

// Goertzel amplitude measurement on a one-second interior window. Magnitude
// is phase-independent, so MP3 encoder delay does not invalidate the test.
private func synthetic_tone_amplitude(_ samples: [Float], rate: Int, frequency: Double) -> Double {
    let start = rate / 4
    guard samples.count >= start + rate else { return 0 }
    let coefficient = 2 * cos(2 * Double.pi * frequency / Double(rate))
    var previous = 0.0
    var previous_previous = 0.0
    for index in start..<(start + rate) {
        let current = Double(samples[index]) + coefficient * previous - previous_previous
        previous_previous = previous
        previous = current
    }
    let energy = max(0, previous * previous + previous_previous * previous_previous
                     - coefficient * previous * previous_previous)
    return 2 * energy.squareRoot() / Double(rate)
}
