import Foundation

enum SyntheticWAVEncoding: String, CaseIterable {
    case pcm16
    case pcm24
    case float32

    var format_code: UInt16 { self == .float32 ? 3 : 1 }
    var bits_per_sample: UInt16 {
        switch self {
        case .pcm16: 16
        case .pcm24: 24
        case .float32: 32
        }
    }
    var bytes_per_sample: Int { Int(bits_per_sample / 8) }
}

// Deterministic fixtures; never retained on disk outside a test workspace.
func make_synthetic_wav(
    sample_rate: Int,
    channel_frequencies: [Double],
    duration_seconds: Double,
    encoding: SyntheticWAVEncoding,
    amplitude: Double = 0.35
) -> Data {
    let channels = channel_frequencies.count
    let frames = Int((duration_seconds * Double(sample_rate)).rounded())
    let block_align = channels * encoding.bytes_per_sample
    let pcm_bytes = frames * block_align
    let has_fact = encoding == .float32
    let riff_size = 4 + (8 + 16) + (has_fact ? 12 : 0) + (8 + pcm_bytes)
    var data = Data()
    data.reserveCapacity(8 + riff_size)
    data.append(contentsOf: "RIFF".utf8)
    data.append_le(UInt32(riff_size))
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.append_le(UInt32(16))
    data.append_le(encoding.format_code)
    data.append_le(UInt16(channels))
    data.append_le(UInt32(sample_rate))
    data.append_le(UInt32(sample_rate * block_align))
    data.append_le(UInt16(block_align))
    data.append_le(encoding.bits_per_sample)
    if has_fact {
        data.append(contentsOf: "fact".utf8)
        data.append_le(UInt32(4))
        data.append_le(UInt32(frames))
    }
    data.append(contentsOf: "data".utf8)
    data.append_le(UInt32(pcm_bytes))
    for frame in 0..<frames {
        for frequency in channel_frequencies {
            let sample = frequency == 0 ? 0 : amplitude * sin(
                2 * Double.pi * frequency * Double(frame) / Double(sample_rate)
            )
            switch encoding {
            case .pcm16:
                let value = Int16(clamping: Int((sample * Double(Int16.max)).rounded()))
                data.append_le(UInt16(bitPattern: value))
            case .pcm24:
                let value = Int32((sample * 8_388_607).rounded())
                data.append(UInt8(truncatingIfNeeded: value))
                data.append(UInt8(truncatingIfNeeded: value >> 8))
                data.append(UInt8(truncatingIfNeeded: value >> 16))
            case .float32:
                data.append_le(Float(sample).bitPattern)
            }
        }
    }
    return data
}

private extension Data {
    mutating func append_le(_ value: UInt16) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    mutating func append_le(_ value: UInt32) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
