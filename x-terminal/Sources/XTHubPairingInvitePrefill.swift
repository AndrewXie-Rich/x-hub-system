import Foundation

struct XTHubPairingInvitePrefill: Equatable {
    var hubAlias: String?
    var internetHost: String?
    var pairingPort: Int?
    var grpcPort: Int?
    var inviteToken: String?
    var hubInstanceID: String?
}
