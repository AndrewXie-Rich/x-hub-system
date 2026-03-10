import Foundation

struct AXUsageSummary: Equatable {
    var todayTokensEst: Int
    var totalTokensEst: Int
    var todayRequests: Int
    var totalRequests: Int

    static func empty() -> AXUsageSummary {
        AXUsageSummary(todayTokensEst: 0, totalTokensEst: 0, todayRequests: 0, totalRequests: 0)
    }
}
