# X-Terminal R1 Golden Task

Update `Sources/GoldenProject/Greeting.swift` so `Greeting.message` returns the
required greeting below. Do not change the test or package manifest.

Acceptance criteria:

1. `Greeting.message` returns exactly `Hello from X-Terminal`.
2. `swift test` passes using a toolchain with Swift Testing.
3. Only `Sources/GoldenProject/Greeting.swift` changes.

The initial test is intentionally red. The Project Coder must read this task
and discover the source seam through the test failure; the prepare runner never
applies the reference repair to the formal project.

This package has no external dependencies. On a Command Line Tools installation
without Swift Testing, `swift run GoldenProjectTests` checks the same acceptance
conditions as a standalone diagnostic. That diagnostic does not satisfy the
standard test-toolchain or live Hub/XT readiness requirements.
