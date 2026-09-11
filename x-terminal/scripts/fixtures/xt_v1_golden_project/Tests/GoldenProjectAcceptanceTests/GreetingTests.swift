import Testing
import GoldenProject

@Suite
struct GreetingTests {
    @Test
    func testNonemptyGreeting() {
        let passed = !Greeting.message.isEmpty
        print("XT_R1_TEST testNonemptyGreeting \(passed ? "pass" : "fail")")
        #expect(passed)
    }

    @Test
    func testTaskGreeting() {
        let passed = Greeting.message == "Hello from X-Terminal"
        print("XT_R1_TEST testTaskGreeting \(passed ? "pass" : "fail")")
        #expect(passed)
    }
}
