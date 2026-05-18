import Foundation
import Network

enum HubProviderOAuthLoopbackError: LocalizedError {
    case invalidRedirectURI
    case listenerFailed(String)
    case timedOut
    case requestDecodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidRedirectURI:
            return "Hub OAuth redirect URI 无效。"
        case .listenerFailed(let reason):
            return reason
        case .timedOut:
            return "等待 OAuth 回调超时。"
        case .requestDecodeFailed:
            return "OAuth 回调请求解析失败。"
        }
    }
}

actor HubProviderOAuthLoopbackCallbackServer {
    private let redirectURI: URL
    private let expectedPath: String
    private let baseURL: URL
    private let queue = DispatchQueue(label: "hub.provider-oauth-loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var finished = false

    init(redirectURI: URL) throws {
        guard let scheme = redirectURI.scheme?.lowercased(),
              scheme == "http",
              let host = redirectURI.host,
              ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()),
              let port = redirectURI.port else {
            throw HubProviderOAuthLoopbackError.invalidRedirectURI
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/"
        guard let baseURL = components.url else {
            throw HubProviderOAuthLoopbackError.invalidRedirectURI
        }
        self.redirectURI = redirectURI
        self.expectedPath = redirectURI.path.isEmpty ? "/" : redirectURI.path
        self.baseURL = baseURL
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        guard continuation == nil, finished == false else {
            throw HubProviderOAuthLoopbackError.listenerFailed("Hub OAuth callback server 已经在运行。")
        }
        try startListener()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeout) * 1_000_000_000))
                await timeoutIfNeeded()
            }
        }
    }

    private func startListener() throws {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(redirectURI.port ?? 0)) else {
            throw HubProviderOAuthLoopbackError.invalidRedirectURI
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.allowFastOpen = true
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleConnection(connection) }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func handleListenerState(_ state: NWListener.State) async {
        if case .failed(let error) = state {
            await finish(with: .failure(HubProviderOAuthLoopbackError.listenerFailed(String(describing: error))))
        }
    }

    private func handleConnection(_ connection: NWConnection) async {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            Task {
                await self.processConnection(connection, data: data, error: error)
            }
        }
    }

    private func processConnection(
        _ connection: NWConnection,
        data: Data?,
        error: NWError?
    ) async {
        if let error {
            sendHTMLResponse(
                connection,
                statusLine: "HTTP/1.1 500 Internal Server Error",
                body: "<html><body><h1>Hub OAuth failed</h1><p>\(escapeHTML(String(describing: error)))</p></body></html>"
            )
            return
        }

        guard let data,
              let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first else {
            sendHTMLResponse(
                connection,
                statusLine: "HTTP/1.1 400 Bad Request",
                body: "<html><body><h1>Hub OAuth failed</h1><p>Could not read callback request.</p></body></html>"
            )
            return
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            sendHTMLResponse(
                connection,
                statusLine: "HTTP/1.1 400 Bad Request",
                body: "<html><body><h1>Hub OAuth failed</h1><p>Malformed request line.</p></body></html>"
            )
            return
        }

        guard let callbackURL = resolvedCallbackURL(for: String(parts[1])) else {
            sendHTMLResponse(
                connection,
                statusLine: "HTTP/1.1 400 Bad Request",
                body: "<html><body><h1>Hub OAuth failed</h1><p>Could not parse callback URL.</p></body></html>"
            )
            return
        }

        guard callbackURL.path == expectedPath else {
            sendHTMLResponse(
                connection,
                statusLine: "HTTP/1.1 404 Not Found",
                body: "<html><body><h1>Not Found</h1></body></html>"
            )
            return
        }

        sendHTMLResponse(
            connection,
            statusLine: "HTTP/1.1 200 OK",
            body: "<html><body><h1>Authentication successful</h1><p>You can close this window and return to X-Hub.</p></body></html>"
        )
        await finish(with: .success(callbackURL))
    }

    private func resolvedCallbackURL(for target: String) -> URL? {
        if let absolute = URL(string: target), absolute.scheme != nil {
            return absolute
        }
        return URL(string: target, relativeTo: baseURL)?.absoluteURL
    }

    private func sendHTMLResponse(
        _ connection: NWConnection,
        statusLine: String,
        body: String
    ) {
        let data = responseData(statusLine: statusLine, body: body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func responseData(statusLine: String, body: String) -> Data {
        let payload = body.data(using: .utf8) ?? Data()
        let header = """
        \(statusLine)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(payload.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r
        """
        var data = Data(header.utf8)
        data.append(payload)
        return data
    }

    private func timeoutIfNeeded() async {
        guard finished == false else { return }
        await finish(with: .failure(HubProviderOAuthLoopbackError.timedOut))
    }

    private func finish(with result: Result<URL, Error>) async {
        guard finished == false else { return }
        finished = true
        listener?.cancel()
        listener = nil
        let continuation = self.continuation
        self.continuation = nil
        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func escapeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
