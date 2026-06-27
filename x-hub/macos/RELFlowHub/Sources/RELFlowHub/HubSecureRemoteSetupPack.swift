import Foundation

enum HubSecureRemoteSetupPackBuilder {
    static func build(
        externalHost: String?,
        alias: String?,
        inviteToken: String?,
        pairingPort: Int,
        grpcPort: Int,
        hubInstanceID: String?,
        allowPrivateVPNIP: Bool = false
    ) -> String? {
        guard let host = HubExternalAccessInviteSupport.normalizedSecureRemoteHost(
            externalHost,
            allowPrivateVPNIP: allowPrivateVPNIP
        ),
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
X-Hub Remote Setup

Choose one remote entry:
- Secure non-Tailscale path: stable DNS name -> Cloudflare Spectrum or your VPS raw TCP relay -> Hub 50051/50052, with mTLS enabled.
- Convenient path: public IP/DDNS + router port forwarding to Hub 50051/50052. Use only when you accept lower network exposure.
- Private-network path: Tailscale/MagicDNS or another private TCP route, if the user chooses to install it.

How to use:
1. On the XT device, open the invite link below. This is the preferred path after the remote entry is reachable.
2. If that device already has `axhubctl`, you can run the bootstrap command below instead.
3. XT will keep using this configured remote entry for future network switches instead of falling back to blind LAN scans.

Invite link:
\(inviteURL.absoluteString)

Bootstrap command (existing XT / axhubctl only):
\(command)

Security notes:
- Uses configured remote host: \(host)
- External pairing requires invite token validation
- First pairing is still limited to the same Wi-Fi/LAN by Hub policy; after pairing, roaming relies on issued credentials and mTLS
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
