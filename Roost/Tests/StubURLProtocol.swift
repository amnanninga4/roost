import Foundation

/// Routes every request on a stub URLSession through a closure. Records requests so tests can count them.
final class StubURLProtocol: URLProtocol {
    struct Recorded: Sendable {
        let method: String
        let path: String
        let query: String?
        let body: [String: Any]?
        let authorization: String?
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    private(set) nonisolated(unsafe) static var recorded: [Recorded] = []
    private static let lock = NSLock()

    /// Return this as the status to answer with no response at all: the connection died.
    static let connectionLost = -1

    static func reset(_ h: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        lock.withLock {
            handler = h
            recorded = []
        }
    }

    static func requests(_ method: String) -> [Recorded] {
        lock.withLock { recorded.filter { $0.method == method } }
    }

    static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let req = request
        var bodyData = req.httpBody
        if bodyData == nil, let stream = req.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 64 * 1024)
            var out = Data()
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 {
                    break
                }
                out.append(buf, count: n)
            }
            stream.close()
            bodyData = out
        }
        let body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        Self.lock.withLock {
            Self.recorded.append(Recorded(
                method: req.httpMethod ?? "GET",
                path: req.url?.path ?? "",
                query: req.url?.query,
                body: body,
                authorization: req.value(forHTTPHeaderField: "Authorization")
            ))
        }
        let (status, data) = Self.handler?(req) ?? (500, Data())
        if status == Self.connectionLost {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let resp = HTTPURLResponse(
            url: req.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func json(_ obj: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: obj)
}

func completionJSON(id: String, choreId: String, person: String, completedAt: String, seq: Int,
                    deleted: Bool = false) -> [String: Any]
{
    [
        "id": id, "choreId": choreId, "person": person, "completedAt": completedAt,
        "createdAt": "2026-09-14T12:00:00.000Z", "updatedAt": "2026-09-14T12:00:00.000Z",
        "deleted": deleted, "seq": seq,
    ]
}

func syncJSON(
    person: String = "anne",
    cursor: Int,
    choresVersion: Int = 1,
    completions: [[String: Any]] = [],
    chores: [[String: Any]]? = nil
) -> Data {
    var obj: [String: Any] = [
        "serverTime": "2026-09-14T12:00:00.000Z",
        "person": person,
        "choresVersion": choresVersion,
        "cursor": cursor,
        "completions": completions,
    ]
    if let chores {
        obj["chores"] = chores
    }
    return json(obj)
}
