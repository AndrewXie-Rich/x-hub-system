import Foundation

enum HubGRPCClientSupport {
    static func validateTransport(host: String, mode: String) throws {
        let mode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["tls", "mtls", "insecure"].contains(mode) else {
            throw HubPairingTransport.TransportError(message: "grpc_tls_mode_invalid: expected tls, mtls, or explicit loopback-only insecure")
        }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if mode == "insecure", !HubPairingTransport.isLoopbackHost(normalizedHost) || normalizedHost == "localhost" {
            throw HubPairingTransport.TransportError(message: "grpc_plaintext_remote_denied: use TLS or an authenticated numeric loopback tunnel")
        }
    }

    static let makeClientCredentialsScript = #"""
async function makeClientCreds() {
  const mode = String(process.env.HUB_GRPC_TLS_MODE || process.env.HUB_TLS_MODE || 'tls').trim().toLowerCase() || 'tls';
  if (!['tls', 'mtls', 'insecure'].includes(mode)) throw new Error('grpc_tls_mode_invalid');
  if (mode === 'insecure') {
    const host = String(process.env.HUB_HOST || '127.0.0.1').trim().toLowerCase();
    const { isIP } = await import('node:net');
    if (!(host === '::1' || (isIP(host) === 4 && host.startsWith('127.')))) {
      throw new Error('grpc_plaintext_remote_denied');
    }
  }
  const helper = path.resolve(process.cwd(), 'src', 'client_credentials.js');
  if (!fs.existsSync(helper)) throw new Error('grpc_credentials_helper_missing: reinstall the current Hub client kit');
  const mod = await import(pathToFileURL(helper).href);
  if (typeof mod.makeClientCredentials !== 'function') throw new Error('grpc_credentials_helper_invalid');
  const built = mod.makeClientCredentials(process.env);
  if (!built?.creds || built.mode !== mode) throw new Error('grpc_credentials_mode_mismatch');
  return { creds: built.creds, options: built.options || {} };
}
"""#
}
