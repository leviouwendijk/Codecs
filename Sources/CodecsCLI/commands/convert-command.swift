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
            opt("quality", as: String.self, help: "maximum, high, or balanced (default maximum)."),
        ]
    }

    static func run(_ invocation: ParsedInvocation) async throws {
        guard let source = try invocation.value("source", as: String.self),
              let output = try invocation.value("output", as: String.self) else {
            throw ConvertCommandError.missingPath
        }
        let raw = try invocation.value("quality", as: String.self) ?? "maximum"
        let requested: LAMEVBRQuality?
        switch raw {
        case "maximum": requested = .maximum
        case "high": requested = .high
        case "balanced": requested = .balanced
        default: requested = nil
        }
        guard let quality = requested else {
            throw ConvertCommandError.invalidQuality
        }
        func resolve(_ path: String) -> URL {
            URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        }
        let result = try await MediaAudioTranscoder().transcode(
            resolve(source), to: resolve(output), using: LAMEEncoder(quality: quality)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ConvertCommandError.outputEncodingFailed
        }
        print(json)
    }
}

enum ConvertCommandError: Error {
    case missingPath
    case invalidQuality
    case outputEncodingFailed
}
