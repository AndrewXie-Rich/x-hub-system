import Darwin
import GoldenProject

let checks = [
    ("testNonemptyGreeting", !Greeting.message.isEmpty),
    ("testTaskGreeting", Greeting.message == "Hello from X-Terminal"),
]
for (testID, passed) in checks {
    print("XT_R1_TEST \(testID) \(passed ? "pass" : "fail")")
}
exit(checks.allSatisfy { $0.1 } ? 0 : 1)
