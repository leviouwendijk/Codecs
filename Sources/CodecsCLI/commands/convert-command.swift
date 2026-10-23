import Arguments
import Foundation
import MediaTranscoding
import CodecsLAME

enum ConvertCommand: RunnableArgumentCommand {
    static let name = "convert"

    static func components() throws -> [CommandComponentLowerable] {
        [
            arg("source", as: String.self, help: "Existing source WAV or supported audio asset."),
            opt("output", as: String.self, help: "Destination MP3. Must not exist."),
            opt("quality", as: String.self, help: "VBR maximum, high, or balanced (default maximum)."),
            opt("bitrate", as: Int.self, help: "CBR bitrate in kbps; currently 320. Conflicts with --quality."),
        ]
    }

    static func run(_ invocation: ParsedInvocation) async throws {
        guard let source = try invocation.value("source", as: String.self),
              let output = try invocation.value("output", as: String.self) else {
            throw ConvertCommandError.missingPath
        }
        let explicitQuality = try invocation.value("quality", as: String.self)
        let requestedBitrate = try invocation.value("bitrate", as: Int.self)
        guard explicitQuality == nil || requestedBitrate == nil else {
            throw ConvertCommandError.conflictingEncodingOptions
        }
        let encoder: LAMEEncoder
        if let requestedBitrate {
            guard requestedBitrate == LAMECBRBitrate.kbps320.rawValue else {
                throw ConvertCommandError.invalidBitrate
            }
            encoder = LAMEEncoder(bitrate: .kbps320)
        } else {
            let quality: LAMEVBRQuality
            switch explicitQuality ?? "maximum" {
            case "maximum": quality = .maximum
            case "high": quality = .high
            case "balanced": quality = .balanced
            default: throw ConvertCommandError.invalidQuality
            }
            encoder = LAMEEncoder(quality: quality)
        }
        func resolve(_ path: String) -> URL {
            URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        }
        let result = try await MediaAudioTranscoder().transcode(
            resolve(source), to: resolve(output), using: encoder
        )
        let json_encoder = JSONEncoder()
        json_encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try json_encoder.encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ConvertCommandError.outputEncodingFailed
        }
        print(json)
    }
}

enum ConvertCommandError: Error {
    case missingPath
    case invalidQuality
    case invalidBitrate
    case conflictingEncodingOptions
    case outputEncodingFailed
}
