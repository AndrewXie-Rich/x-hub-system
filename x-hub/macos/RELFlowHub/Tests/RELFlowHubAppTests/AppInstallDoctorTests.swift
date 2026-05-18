import XCTest
@testable import RELFlowHub

final class AppInstallDoctorTests: XCTestCase {
    private let allowRunOutsideApplicationsKey = "relflowhub_allow_run_outside_applications"

    @MainActor
    func testOnlyCanonicalApplicationsBundleIsAccepted() {
        withInstallDoctorOverrideCleared {
            XCTAssertFalse(AppInstallDoctor.shouldWarn(bundleURL: URL(fileURLWithPath: "/Applications/X-Hub.app")))
            XCTAssertTrue(AppInstallDoctor.shouldWarn(bundleURL: URL(fileURLWithPath: "/Applications/RELFlowHub.app")))
            XCTAssertTrue(AppInstallDoctor.shouldWarn(bundleURL: URL(fileURLWithPath: "/Applications/Hub.app")))
        }
    }

    @MainActor
    func testOnlyCanonicalBuildOutputIsAccepted() {
        withInstallDoctorOverrideCleared {
            XCTAssertFalse(AppInstallDoctor.shouldWarn(bundleURL: URL(fileURLWithPath: "/tmp/project/build/X-Hub.app")))
            XCTAssertTrue(AppInstallDoctor.shouldWarn(bundleURL: URL(fileURLWithPath: "/tmp/project/build/RELFlowHub.app")))
        }
    }

    @MainActor
    func testHomeApplicationsStillRequiresCanonicalBundleName() {
        let homeApplications = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")

        withInstallDoctorOverrideCleared {
            XCTAssertFalse(
                AppInstallDoctor.shouldWarn(
                    bundleURL: URL(fileURLWithPath: (homeApplications as NSString).appendingPathComponent("X-Hub.app"))
                )
            )
            XCTAssertTrue(
                AppInstallDoctor.shouldWarn(
                    bundleURL: URL(fileURLWithPath: (homeApplications as NSString).appendingPathComponent("RELFlowHub.app"))
                )
            )
        }
    }

    func testAppTemplateUsesCanonicalExecutableName() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = packageRoot
            .deletingLastPathComponent()
            .appendingPathComponent("app_template/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleName"] as? String, "X-Hub")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "X-Hub")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "XHub")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.rel.flowhub")
    }

    private func withInstallDoctorOverrideCleared(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: allowRunOutsideApplicationsKey)
        defaults.removeObject(forKey: allowRunOutsideApplicationsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: allowRunOutsideApplicationsKey)
            } else {
                defaults.removeObject(forKey: allowRunOutsideApplicationsKey)
            }
        }
        body()
    }
}
