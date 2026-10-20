import Foundation

func makePCM16WAV(
    sampleRate: Int = 48_000,
    channelCount: Int = 2,
    frames: Int = 480
) -> Data {
    var channels = Array(
        repeating: [Float](),
        count: channelCount
    )

    for index in channels.indices {
        channels[index].reserveCapacity(
            frames
        )
    }

    for frame in 0..<frames {
        let phase = 2
            * Double.pi
            * 440
            * Double(
                frame
            )
            / Double(
                sampleRate
            )

        let value = Float(
            sin(
                phase
            ) * 0.25
        )

        for channel in channels.indices {
            channels[channel].append(
                channel.isMultiple(
                    of: 2
                )
                    ? value
                    : -value
            )
        }
    }

    return makePCM16WAV(
        sampleRate: sampleRate,
        channels: channels
    )
}

func makePCM16WAV(
    sampleRate: Int = 48_000,
    channels: [[Float]]
) -> Data {
    let channelCount = channels.count

    let frameCount = channels
        .map(\.count)
        .min()
        ?? 0

    let bytesPerSample = MemoryLayout<Int16>.size
    let blockAlign = channelCount * bytesPerSample
    let dataSize = frameCount * blockAlign
    let byteRate = sampleRate * blockAlign

    var data = Data()

    data.appendASCII(
        "RIFF"
    )

    data.appendLittleEndian(
        UInt32(
            36 + dataSize
        )
    )

    data.appendASCII(
        "WAVE"
    )

    data.appendASCII(
        "fmt "
    )

    data.appendLittleEndian(
        UInt32(16)
    )

    data.appendLittleEndian(
        UInt16(1)
    )

    data.appendLittleEndian(
        UInt16(
            channelCount
        )
    )

    data.appendLittleEndian(
        UInt32(
            sampleRate
        )
    )

    data.appendLittleEndian(
        UInt32(
            byteRate
        )
    )

    data.appendLittleEndian(
        UInt16(
            blockAlign
        )
    )

    data.appendLittleEndian(
        UInt16(16)
    )

    data.appendASCII(
        "data"
    )

    data.appendLittleEndian(
        UInt32(
            dataSize
        )
    )

    for frame in 0..<frameCount {
        for channel in 0..<channelCount {
            let sample = max(
                -1,
                min(
                    1,
                    channels[channel][frame]
                )
            )

            let value = Int16(
                clamping: Int(
                    (
                        sample
                        * Float(
                            Int16.max
                        )
                    ).rounded()
                )
            )

            data.appendLittleEndian(
                UInt16(
                    bitPattern: value
                )
            )
        }
    }

    return data
}

private extension Data {
    mutating func appendASCII(
        _ string: String
    ) {
        append(
            contentsOf: string.utf8
        )
    }

    mutating func appendLittleEndian(
        _ value: UInt16
    ) {
        var value = value.littleEndian

        Swift.withUnsafeBytes(
            of: &value
        ) {
            append(
                contentsOf: $0
            )
        }
    }

    mutating func appendLittleEndian(
        _ value: UInt32
    ) {
        var value = value.littleEndian

        Swift.withUnsafeBytes(
            of: &value
        ) {
            append(
                contentsOf: $0
            )
        }
    }
}
