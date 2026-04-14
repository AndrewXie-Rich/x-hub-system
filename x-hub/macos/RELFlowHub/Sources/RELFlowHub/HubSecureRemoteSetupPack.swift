import Foundation

enum HubSecureRemoteSetupPackBuilder {
    static func build(
        externalHost: String?,
        alias: String?,
        inviteToken: String?,
        pairingPort: Int,
        grpcPort: Int,
        hubInstanceID: String?
    ) -> String? {
        guard let host = HubExternalAccessInviteSupport.normalizedStableNamedExternalHost(externalHost),
              let inviteToken = normalizedNonEmpty(inviteToken),
              let inviteURL = HubExternalAccessInviteSupport.externalInviteURL(
                alias: alias,
                externalHost: host,
                inviteToken: inviteToken,
                pairingPort: pairingPort,
                grpcPort: grpcPort,
                hubInstanceID: hubInstanceID
              ) else {
            return nil
        }

        let command = secureBootstrapCommand(
            host: host,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            inviteToken: inviteToken
        )

        return """
REL Flow Hub Secure Remote Setup

Recommended path:
1. On the XT device, open the invite link below. This is the preferred secure path.
2. If that device already has `axhubctl`, you can run the bootstrap command below instead.
3. XT will keep using this stable host for future network switches instead of falling back to raw IP.

Invite link:
\(inviteURL.absoluteString)

Bootstrap command (existing XT / axhubctl only):
\(command)

Security notes:
- Uses stable named host only: \(host)
- External pairing requires invite token validation
- Fails closed if the required client kit cannot be installed
- Does not fetch `axhubctl` over unauthenticated remote HTTP
"""
    }

    private static func secureBootstrapCommand(
        host: String,
        pairingPort: Int,
        grpcPort: Int,
        inviteToken: String
    ) -> String {
        let escapedHost = shellSingleQuoted(host)
        let escapedPairingPort = shellSingleQuoted(String(max(1, min(65_535, pairingPort))))
        let escapedGRPCPort = shellSingleQuoted(String(max(1, min(65_535, grpcPort))))
        let escapedInviteToken = shellSingleQuoted(inviteToken)
        let escapedScopes = shellSingleQuoted("models,events,memory,skills,ai.generate.local")

        return """
AXHUBCTL="${AXHUBCTL:-$HOME/.local/bin/axhubctl}"
if [ ! -x "$AXHUBCTL" ]; then
  echo "axhubctl not found. Open the invite link in X-Terminal, or install XT first." >&2
  exit 1
fi
"$AXHUBCTL" bootstrap --hub \(escapedHost) --pairing-port \(escapedPairingPort) --grpc-port \(escapedGRPCPort) \\
  --invite-token \(escapedInviteToken) \\
  --device-name "<device_name>" \\
  --requested-scopes \(escapedScopes) \\
  --require-client-kit
"""
    }

    private static func normalizedNonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}
