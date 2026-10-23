import Foundation
import MediaAV
import MediaTranscoding
import CodecsLAME
import TestFlows

extension CodecsFlowSuite {
    static var cbr320Flow: TestFlow {
        TestFlow("cbr-320-mp3", tags: ["audio", "mp3", "cbr", "bitrate"]) {
            Step("320 kbps CBR preserves stereo and mono and emits 320 kbps MPEG frames") {
                for channels in [1, 2] {
                    let workspace = try CodecsTestWorkspace("cbr320-\(channels)")
                    defer { workspace.remove() }
                    let source = workspace.file("source.wav")
                    let destination = workspace.file("output.mp3")
                    let original = make_synthetic_wav(
                        sample_rate: 48_000,
                        channel_frequencies: channels == 1 ? [440] : [440, 880],
                        duration_seconds: 2,
                        encoding: .pcm16
                    )
                    try original.write(to: source)
                    let result = try await MediaAudioTranscoder().transcode(
                        source, to: destination, using: LAMEEncoder(bitrate: .kbps320)
                    )
                    try Expect.equal(result.channelCount, channels, "cbr320.channel-count")
                    try Expect.equal(result.sampleRate, 48_000, "cbr320.sample-rate")
                    try Expect.true(result.outputBytes > 0, "cbr320.nonempty")
                    let frames = parse_cbr_320_mpeg_frames(try Data(contentsOf: destination))
                    try Expect.true(frames >= 15, "cbr320.frame-headers")
                    try Expect.equal(try Data(contentsOf: source), original, "cbr320.source-preserved")
                }
            }
        }
    }
}

// Walk consecutive MPEG-1 Layer III frames (not an average-bitrate metadata estimate).
// ID3v2 is skipped when present. MPEG-1 Layer III uses a 144000 * kbps / Hz frame size.
private func parse_cbr_320_mpeg_frames(_ data: Data) -> Int {
    let bytes = [UInt8](data)
    var offset = 0
    if bytes.count >= 10, Array(bytes[0..<3]) == Array("ID3".utf8) {
        let tag_size = (Int(bytes[6] & 0x7f) << 21)
                     | (Int(bytes[7] & 0x7f) << 14)
                     | (Int(bytes[8] & 0x7f) << 7)
                     | Int(bytes[9] & 0x7f)
        offset = 10 + tag_size + ((bytes[5] & 0x10) != 0 ? 10 : 0)
    }
    var frames = 0
    while offset + 4 <= bytes.count {
        if offset + 128 == bytes.count,
           Array(bytes[offset..<(offset + 3)]) == Array("TAG".utf8) {
            offset = bytes.count
            break
        }
        let b0 = bytes[offset]
        let b1 = bytes[offset + 1]
        let b2 = bytes[offset + 2]
        let b3 = bytes[offset + 3]
        guard b0 == 0xff,
              (b1 & 0xfe) == 0xfa,             // MPEG-1, Layer III, sync
              (b2 >> 4) == 14,               // MPEG-1 Layer III 320 kbps index
              ((b2 >> 2) & 3) != 3 else { return 0 }
        let rate_index = Int((b2 >> 2) & 3)
        let rates = [44_100, 48_000, 32_000]
        let padding = Int((b2 >> 1) & 1)
        let frame_bytes = 144_000 * 320 / rates[rate_index] + padding
        guard frame_bytes > 4, offset + frame_bytes <= bytes.count else { return 0 }
        offset += frame_bytes
        _ = b3
        frames += 1
    }
    return offset == bytes.count ? frames : 0
}
