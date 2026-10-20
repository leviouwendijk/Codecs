import TestFlows

enum CodecsFlowSuite: TestFlowRegistry {
    static let title = "Codecs"
    static let flows: [TestFlow] = [
        lameFlow,
    ]
}
