import Arguments

@main
enum CodecsCommand: ArgumentCommand {
    static let name = "codecs"
    static let defaultChild = Help.self
    static let children: [ArgumentCommandType] = [
        Help.self,
        ConvertCommand.self,
    ]

    enum Help: RunnableArgumentCommand {
        static let name = "help"
        static func run(_ invocation: ParsedInvocation) async throws {
            print(ArgumentHelpRenderer().render(command: try CodecsCommand.spec()))
        }
    }

    static func main() async {
        await ArgumentProgram.main(command: Self.self)
    }
}
