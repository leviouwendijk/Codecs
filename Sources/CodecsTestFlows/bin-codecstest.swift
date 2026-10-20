import TestFlows

@main
enum CodecsTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(suite: CodecsFlowSuite.self)
    }
}
