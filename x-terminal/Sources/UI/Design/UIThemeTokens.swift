import AppKit
import Foundation
import SwiftUI

enum XTUISurfaceState: String, Codable, CaseIterable {
    case ready = "ready"
    case inProgress = "in_progress"
    case grantRequired = "grant_required"
    case permissionDenied = "permission_denied"
    case blockedWaitingUpstream = "blocked_waiting_upstream"
    case releaseFrozen = "release_frozen"
    case diagnosticRequired = "diagnostic_required"

    var label: String {
        switch self {
        case .ready:
            return "Ready"
        case .inProgress:
            return "In progress"
        case .grantRequired:
            return "Grant required"
        case .permissionDenied:
            return "Permission denied"
        case .blockedWaitingUpstream:
            return "Blocked"
        case .releaseFrozen:
            return "Release frozen"
        case .diagnosticRequired:
            return "Diagnostic required"
        }
    }

    var iconName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .inProgress:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .grantRequired:
            return "exclamationmark.shield.fill"
        case .permissionDenied:
            return "hand.raised.fill"
        case .blockedWaitingUpstream:
            return "pause.circle.fill"
        case .releaseFrozen:
            return "checkmark.seal.fill"
        case .diagnosticRequired:
            return "stethoscope.circle.fill"
        }
    }

    var tint: Color {
        UIThemeTokens.color(for: self)
    }
}

struct XTUIInformationArchitectureContract: Codable, Equatable {
    let schemaVersion: String
    let surfaces: [String]
    let primaryActions: [String: [String]]
    let diagnosticEntrypoints: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case surfaces
        case primaryActions = "primary_actions"
        case diagnosticEntrypoints = "diagnostic_entrypoints"
        case auditRef = "audit_ref"
    }

    static let frozen = XTUIInformationArchitectureContract(
        schemaVersion: "xt.ui_information_architecture.v1",
        surfaces: [
            "xt.global_home",
            "xt.supervisor_cockpit",
            "xt.hub_setup_wizard",
            "xt.settings_center",
            "hub.settings_center"
        ],
        primaryActions: [
            "xt.global_home": ["start_big_task", "resume_project", "pair_hub"],
            "xt.supervisor_cockpit": ["submit_intake", "approve_risk", "review_delivery"],
            "hub.settings_center": ["pair_terminal", "configure_models", "review_grants", "run_diagnostics"]
        ],
        diagnosticEntrypoints: ["grant_center", "model_status", "pairing_health", "audit_logs"],
        auditRef: "audit-xt-w3-27-a"
    )
}

struct XTUIDesignTokenBundleContract: Codable, Equatable {
    struct ColorSemantics: Codable, Equatable {
        let success: String
        let warning: String
        let danger: String
        let info: String
    }

    struct SurfaceTokens: Codable, Equatable {
        let cardRadius: Int
        let sectionSpacing: Int
        let primaryButtonStyle: String
        let diagnosticChipStyle: String

        enum CodingKeys: String, CodingKey {
            case cardRadius = "card_radius"
            case sectionSpacing = "section_spacing"
            case primaryButtonStyle = "primary_button_style"
            case diagnosticChipStyle = "diagnostic_chip_style"
        }
    }

    let schemaVersion: String
    let colorSemantics: ColorSemantics
    let surfaceTokens: SurfaceTokens
    let typeScale: [String: String]
    let motionPolicy: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case colorSemantics = "color_semantics"
        case surfaceTokens = "surface_tokens"
        case typeScale = "type_scale"
        case motionPolicy = "motion_policy"
        case auditRef = "audit_ref"
    }

    static let frozen = XTUIDesignTokenBundleContract(
        schemaVersion: "xt.ui_design_token_bundle.v1",
        colorSemantics: ColorSemantics(
            success: "verified_green",
            warning: "grant_amber",
            danger: "fail_closed_red",
            info: "hub_blue"
        ),
        surfaceTokens: SurfaceTokens(
            cardRadius: 18,
            sectionSpacing: 20,
            primaryButtonStyle: "solid_prominent",
            diagnosticChipStyle: "outlined_dense"
        ),
        typeScale: [
            "hero": "32/40",
            "section": "20/26",
            "body": "14/20",
            "mono": "12/16"
        ],
        motionPolicy: "subtle_stateful_only",
        auditRef: "audit-xt-w3-27-b"
    )
}

struct XTUISurfaceStateContract: Codable, Equatable {
    let schemaVersion: String
    let stateTypes: [XTUISurfaceState]
    let requiredFields: [String]
    let mustNotHide: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case stateTypes = "state_types"
        case requiredFields = "required_fields"
        case mustNotHide = "must_not_hide"
    }

    static let frozen = XTUISurfaceStateContract(
        schemaVersion: "xt.ui_surface_state_contract.v1",
        stateTypes: XTUISurfaceState.allCases,
        requiredFields: [
            "headline",
            "why_it_happened",
            "user_action",
            "machine_status_ref"
        ],
        mustNotHide: [
            "grant_fail_closed",
            "scope_not_validated",
            "remote_secret_blocked"
        ]
    )
}

struct XTUIReleaseScopeBadgeContract: Codable, Equatable {
    let schemaVersion: String
    let currentReleaseScope: String
    let validatedPaths: [String]
    let mustWarnForUnvalidatedSurfaces: Bool
    let badgeText: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case currentReleaseScope = "current_release_scope"
        case validatedPaths = "validated_paths"
        case mustWarnForUnvalidatedSurfaces = "must_warn_for_unvalidated_surfaces"
        case badgeText = "badge_text"
        case auditRef = "audit_ref"
    }

    static let frozen = XTUIReleaseScopeBadgeContract(
        schemaVersion: "xt.ui_release_scope_badge.v1",
        currentReleaseScope: "validated-mainline-only",
        validatedPaths: ["XT-W3-23", "XT-W3-24", "XT-W3-25"],
        mustWarnForUnvalidatedSurfaces: true,
        badgeText: "Validated mainline only",
        auditRef: "audit-xt-w3-27-release-scope"
    )
}

struct ValidatedScopePresentation: Codable, Equatable {
    let currentReleaseScope: String
    let badgeText: String
    let validatedPaths: [String]
    let hardLine: String

    enum CodingKeys: String, CodingKey {
        case currentReleaseScope = "current_release_scope"
        case badgeText = "badge_text"
        case validatedPaths = "validated_paths"
        case hardLine = "hard_line"
    }

    static let validatedMainlineOnly = ValidatedScopePresentation(
        currentReleaseScope: XTUIReleaseScopeBadgeContract.frozen.currentReleaseScope,
        badgeText: XTUIReleaseScopeBadgeContract.frozen.badgeText,
        validatedPaths: XTUIReleaseScopeBadgeContract.frozen.validatedPaths,
        hardLine: "validated-mainline-only; scope_not_validated remains blocked"
    )
}

enum UIThemeTokens {
    static let verifiedGreen = Color(nsColor: NSColor(srgbRed: 0.20, green: 0.66, blue: 0.38, alpha: 1.0))
    static let grantAmber = Color(nsColor: NSColor(srgbRed: 0.90, green: 0.61, blue: 0.12, alpha: 1.0))
    static let failClosedRed = Color(nsColor: NSColor(srgbRed: 0.78, green: 0.22, blue: 0.19, alpha: 1.0))
    static let hubBlue = Color(nsColor: NSColor(srgbRed: 0.20, green: 0.47, blue: 0.85, alpha: 1.0))
    static let cardBackground = Color(nsColor: .windowBackgroundColor)
    static let secondaryCardBackground = Color.primary.opacity(0.035)
    static let subtleBorder = Color.primary.opacity(0.08)

    static let cardRadius = CGFloat(XTUIDesignTokenBundleContract.frozen.surfaceTokens.cardRadius)
    static let sectionSpacing = CGFloat(XTUIDesignTokenBundleContract.frozen.surfaceTokens.sectionSpacing)

    static func color(for state: XTUISurfaceState) -> Color {
        switch state {
        case .ready:
            return verifiedGreen
        case .inProgress:
            return hubBlue
        case .grantRequired:
            return grantAmber
        case .permissionDenied, .blockedWaitingUpstream, .diagnosticRequired:
            return failClosedRed
        case .releaseFrozen:
            return hubBlue
        }
    }

    static func stateBackground(for state: XTUISurfaceState) -> Color {
        switch state {
        case .ready:
            return verifiedGreen.opacity(0.10)
        case .inProgress:
            return hubBlue.opacity(0.10)
        case .grantRequired:
            return grantAmber.opacity(0.12)
        case .permissionDenied, .blockedWaitingUpstream, .diagnosticRequired:
            return failClosedRed.opacity(0.09)
        case .releaseFrozen:
            return hubBlue.opacity(0.08)
        }
    }

    static func heroFont() -> Font {
        .system(size: 32, weight: .bold)
    }

    static func sectionFont() -> Font {
        .system(size: 20, weight: .semibold)
    }

    static func bodyFont() -> Font {
        .system(size: 14, weight: .regular)
    }

    static func monoFont() -> Font {
        .system(size: 12, weight: .medium, design: .monospaced)
    }
}
