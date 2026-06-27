import SwiftUI
import AppKit
import RELFlowHubCore

extension EditGRPCClientSheet {
var parsedDailyTokenLimit: Int? {
        let trimmed = dailyTokenLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    var policyProfileIsValid: Bool {
        guard policyMode == .newProfile else { return true }
        guard parsedDailyTokenLimit != nil else { return false }
        if paidModelSelectionMode == .customSelectedModels {
            return !parseList(allowedPaidModelsText).isEmpty
        }
        return true
    }
}
