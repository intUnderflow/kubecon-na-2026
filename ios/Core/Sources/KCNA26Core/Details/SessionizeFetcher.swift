import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Outcome of one live fetch (Kotlin `sealed interface FetchResult`).
enum FetchResult: Sendable, Hashable {
    /// HTTP 2xx with a markdown body.
    case ok(_ body: String)

    /// Sessionize has no such session (404/410): nothing to show, not worth retrying soon.
    case notFound

    /// Offline, timeout, server error, or a captive-portal HTML page: try again later.
    case failed(_ reason: String)

    /// Kotlin `result is FetchResult.Failed`.
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Fetches one session's markdown (Kotlin `fun interface DetailsFetcher`). ``DetailsRepository``
/// calls it off the main actor; a thrown error counts as ``FetchResult/failed(_:)``.
protocol DetailsFetcher: Sendable {
    func fetch(_ sessionId: String) async throws -> FetchResult
}

/// A ``DetailsFetcher`` from a closure (Kotlin passes a lambda for the `fun interface`).
struct ClosureDetailsFetcher: DetailsFetcher {
    let body: @Sendable (String) async throws -> FetchResult

    init(_ body: @escaping @Sendable (String) async throws -> FetchResult) {
        self.body = body
    }

    func fetch(_ sessionId: String) async throws -> FetchResult { try await body(sessionId) }
}

/// Live Sessionize fetch over URLSession, with the same User-Agent style and Accept header as
/// scripts/fetch_details.py. One attempt per call (the repository decides when to retry).
///
/// Kotlin -> Swift: HttpURLConnection's separate connect (10 s) and read (15 s) timeouts become
/// URLSession's one idle timeout (`timeoutIntervalForRequest`, which also covers connecting),
/// set to the read timeout. Redirects are followed and no HTTP cache is used (ephemeral
/// session, `reloadIgnoringLocalCacheData`), like `instanceFollowRedirects` / `useCaches = false`.
/// The body is read up to ``MAX_BYTES`` (the rest is not downloaded), then decoded as UTF-8
/// with U+FFFD for malformed sequences.
struct SessionizeFetcher: DetailsFetcher {
    let connectTimeoutMs: Int
    let readTimeoutMs: Int
    /// ``URL_PREFIX``; another base only to exercise the HTTP path against a local server.
    let urlPrefix: String

    init(connectTimeoutMs: Int = 10_000, readTimeoutMs: Int = 15_000, urlPrefix: String = SessionizeFetcher.URL_PREFIX) {
        self.connectTimeoutMs = connectTimeoutMs
        self.readTimeoutMs = readTimeoutMs
        self.urlPrefix = urlPrefix
    }

    func fetch(_ sessionId: String) async -> FetchResult {
        if !DetailsRepository.isKubeConId(sessionId) { return .notFound }
        guard let url = URL(string: urlPrefix + sessionId) else {
            return .failed("InvalidURL: \(urlPrefix + sessionId)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(readTimeoutMs) / 1000
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(SessionizeFetcher.USER_AGENT, forHTTPHeaderField: "User-Agent")
        request.setValue(SessionizeFetcher.ACCEPT, forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = TimeInterval(readTimeoutMs) / 1000
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": SessionizeFetcher.USER_AGENT]

        let collector = CappedCollector(maxBytes: SessionizeFetcher.MAX_BYTES)
        let session = URLSession(configuration: config, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let outcome = await collector.run(session.dataTask(with: request))
        switch outcome {
        case .failure(let error):
            return .failed("\(type(of: error)): \(error.localizedDescription)")
        case .success(let (response, bytes)):
            guard let http = response as? HTTPURLResponse else {
                return .failed("Not an HTTP response")
            }
            let code = http.statusCode
            let body = (200...299).contains(code) ? String(decoding: bytes, as: UTF8.self) : ""
            return SessionizeFetcher.classify(code, contentType(http), body)
        }
    }

    /// The Content-Type header (any letter case), or nil.
    private func contentType(_ r: HTTPURLResponse) -> String? {
        for (k, v) in r.allHeaderFields {
            if let key = k as? String, key.lowercased() == "content-type" { return v as? String ?? "\(v)" }
        }
        return nil
    }

    static let URL_PREFIX = "https://sessionize.com/api/v2/uo948i5p/view/markdown/session/"

    /// Like scripts/fetch_details.py's UA, so Sessionize sees the same polite client.
    static let USER_AGENT = "kubecon-schedule-app/1.0 (personal schedule app; iOS)"
    static let ACCEPT = "text/markdown, text/plain, */*"

    /// A session page is a few KB; refuse anything absurd.
    static let MAX_BYTES = 512 * 1024

    /// Maps an HTTP response to a ``FetchResult``. Pure, for tests.
    static func classify(_ code: Int, _ contentType: String?, _ body: String) -> FetchResult {
        if code == 404 || code == 410 { return .notFound }
        if !(200...299).contains(code) { return .failed("HTTP \(code)") }
        if looksLikeHtml(contentType, body) { return .failed("HTML response (captive portal?)") }
        return .ok(body)
    }

    /// Sessionize serves text/plain markdown; an HTML page means a login wall or captive portal.
    static func looksLikeHtml(_ contentType: String?, _ body: String) -> Bool {
        if let contentType, containsIgnoreCase(contentType, "html") { return true }
        let head = body.kotlinTrimStart().kotlinTake(64).lowercased()
        return head.kotlinStartsWith("<!doctype html") || head.kotlinStartsWith("<html")
    }

    /// Kotlin `s.contains(other, ignoreCase = true)`: Java region matching per UTF-16 unit.
    private static func containsIgnoreCase(_ s: String, _ other: String) -> Bool {
        let h = Array(s.utf16), n = Array(other.utf16)
        if n.isEmpty { return true }
        if n.count > h.count { return false }
        for i in 0...(h.count - n.count) {
            var all = true
            for k in 0..<n.count {
                let a = h[i + k], b = n[k]
                if a == b { continue }
                let ua = javaToUpperCase(a), ub = javaToUpperCase(b)
                if ua == ub || javaToLowerCase(ua) == javaToLowerCase(ub) { continue }
                all = false
                break
            }
            if all { return true }
        }
        return false
    }
}

/// Runs one data task, keeping at most `maxBytes` of the body (Kotlin `readCapped`): the task
/// is cancelled once the cap is reached and the bytes so far are the body.
private final class CappedCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var data = Data()
        var response: URLResponse?
        var continuation: CheckedContinuation<Result<(URLResponse, Data), any Error>, Never>?
        var finished = false
    }

    private let maxBytes: Int
    private let state = Locked(State())

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func run(_ task: URLSessionDataTask) async -> Result<(URLResponse, Data), any Error> {
        await withCheckedContinuation { c in
            state.withLock { $0.continuation = c }
            task.resume()
        }
    }

    private func finish(_ result: Result<(URLResponse, Data), any Error>) {
        let c: CheckedContinuation<Result<(URLResponse, Data), any Error>, Never>? = state.withLock { s in
            if s.finished { return nil }
            s.finished = true
            let c = s.continuation
            s.continuation = nil
            return c
        }
        c?.resume(returning: result)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        state.withLock { $0.response = response }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let full: (URLResponse, Data)? = state.withLock { s in
            if s.finished { return nil }
            let room = maxBytes - s.data.count
            if data.count < room {
                s.data.append(data)
                return nil
            }
            s.data.append(data.prefix(room))
            guard let r = s.response ?? dataTask.response else { return nil }
            return (r, s.data)
        }
        if let full {
            finish(.success(full))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        let snapshot: (URLResponse?, Data) = state.withLock { s in (s.response ?? task.response, s.data) }
        if let r = snapshot.0 {
            finish(.success((r, snapshot.1)))
        } else {
            finish(.failure(URLError(.badServerResponse)))
        }
    }
}
