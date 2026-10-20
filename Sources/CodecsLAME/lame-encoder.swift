import Foundation
import MediaCore
import MediaTranscoding
import CodecsLAMEBridge

public enum LAMEVBRQuality: Int, Sendable, CaseIterable, Codable {
    case maximum = 0
    case high = 2
    case balanced = 4
}

public struct LAMEEncoder: MediaAudioEncoder {
    public let quality: LAMEVBRQuality
    public var name: String { "LAME VBR \(quality.rawValue)" }
    public var fileExtension: String { "mp3" }

    public init(quality: LAMEVBRQuality = .maximum) {
        self.quality = quality
    }

    public func makeSink(at url: URL, sampleRate: Int, channelCount: Int) throws -> any MediaAudioEncodingSink {
        guard [32_000, 44_100, 48_000].contains(sampleRate),
              (1...2).contains(channelCount) else {
            throw MediaAudioTranscodeError.unsupportedBuffer
        }
        return try LAMEOutput(url: url, sampleRate: sampleRate,
                                   channelCount: channelCount, quality: quality)
    }
}

private final class LAMEOutput: MediaAudioEncodingSink, @unchecked Sendable {
    private let lock = NSLock()
    private let handle: OpaquePointer
    private let sampleRate: Int
    private let channelCount: Int
    private var finished = false

    init(url: URL, sampleRate: Int, channelCount: Int, quality: LAMEVBRQuality) throws {
        guard let opened = url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return Optional<OpaquePointer>.none }
            return codecs_lame_open(path, Int32(sampleRate), Int32(channelCount), Int32(quality.rawValue))
        }) else {
            throw MediaAudioTranscodeError.backendFailure(-1)
        }
        self.handle = opened
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    deinit { codecs_lame_destroy(handle) }

    func append(_ buffer: MediaAudioBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, buffer.sample == .float32,
              buffer.sampleRate == sampleRate, buffer.channelCount == channelCount,
              buffer.frameCount <= Int(Int32.max),
              buffer.data.count >= buffer.frameCount * channelCount * 4 else {
            throw MediaAudioTranscodeError.inconsistentFormat
        }
        let count = buffer.frameCount * channelCount
        let samples = buffer.data.withUnsafeBytes { bytes in
            (0..<count).map { index in
                bytes.loadUnaligned(fromByteOffset: index * 4, as: Float.self)
            }
        }
        let result = samples.withUnsafeBufferPointer { pointer in
            codecs_lame_append(handle, pointer.baseAddress, Int32(buffer.frameCount))
        }
        guard result == 0 else { throw MediaAudioTranscodeError.backendFailure(result) }
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { throw MediaAudioTranscodeError.backendFailure(-1) }
        finished = true
        let result = codecs_lame_finish(handle)
        guard result == 0 else { throw MediaAudioTranscodeError.backendFailure(result) }
    }
}
