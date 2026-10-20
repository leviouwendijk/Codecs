import Foundation

struct CodecsTestWorkspace {
    let root: URL

    init(
        _ name: String
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codecs-test-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func directory(
        _ name: String
    ) -> URL {
        root.appendingPathComponent(
            name,
            isDirectory: true
        )
    }

    func file(
        _ name: String
    ) -> URL {
        root.appendingPathComponent(
            name
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}
