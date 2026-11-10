import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Outcome of one HTTP GET.
enum HttpResult: Sendable, Equatable {
    /// 2xx. `body` is at most maxBytes + 1 bytes (one more means "too big").
    case ok(body: Data, etag: String?)

    /// 304: the If-None-Match ETag still matches.
    case notModified

    /// Offline, timeout, 404 (repo not published yet), 5xx, …: try again later.
    case failed(String)
}

/// One GET. ``DataSync`` awaits it during a check; tests pass a fake. Never throws.
protocol DataFetcher: Sendable {
    func get(_ url: String, ifNoneMatch: String?, maxBytes: Int64) async -> HttpResult
}

/// ``DataFetcher`` over URLSession with short timeouts (Kotlin: HttpURLConnection). Never throws.
///
/// - No caching: an ephemeral session without a URL cache, and
///   `.reloadIgnoringLocalCacheData`. If-None-Match is set here, so a 304 reaches the caller
///   (URLSession only turns a 304 into a 200 for conditional requests it made from its own cache).
/// - Timeouts: `readTimeoutMs` is the idle timeout (URLSession's `timeoutIntervalForRequest`:
///   no data for that long fails the request, while connecting too). URLSession has no separate
///   connect timeout, so the response headers must arrive within `connectTimeoutMs +
///   readTimeoutMs` (the longest HttpURLConnection waits for them: connect, then read).
/// - Size cap: at most `maxBytes + 1` body bytes are read; then the transfer is cancelled and
///   the truncated body returned (the caller sees it is too big). A non-2xx response's body is
///   not downloaded.
/// - Redirects are followed (URLSession's default, like `instanceFollowRedirects`).
final class HttpDataFetcher: DataFetcher {
    private let connectTimeoutMs: Int
    private let readTimeoutMs: Int

    init(connectTimeoutMs: Int = 5_000, readTimeoutMs: Int = 10_000) {
        self.connectTimeoutMs = connectTimeoutMs
        self.readTimeoutMs = readTimeoutMs
    }

    func get(_ url: String, ifNoneMatch: String?, maxBytes: Int64) async -> HttpResult {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return .failed("MalformedURLException: \(url)")
        }
        var request = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Double(readTimeoutMs) / 1000)
        request.httpMethod = "GET"
        request.setValue(HttpDataFetcher.USER_AGENT, forHTTPHeaderField: "User-Agent")
        if let ifNoneMatch { request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match") }

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = Double(readTimeoutMs) / 1000

        let cap = Int(clamping: max(0, min(maxBytes, Int64.max - 1) + 1))
        let download = CappedDownload(cap: cap)
        let session = URLSession(configuration: config, delegate: download, delegateQueue: nil)
        let deadline = DispatchTimeInterval.milliseconds(connectTimeoutMs + readTimeoutMs)
        return await withCheckedContinuation { (c: CheckedContinuation<HttpResult, Never>) in
            download.start(session.dataTask(with: request), headersDeadline: deadline, c)
            session.finishTasksAndInvalidate()
        }
    }

    /// "kcna26-ios/<CFBundleShortVersionString> (+https://github.com/intUnderflow/kubecon-na-2026)"
    /// (Android: "kcna26-android/<versionName> (+…)").
    static let USER_AGENT: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "kcna26-ios/\(version) (+https://github.com/intUnderflow/kubecon-na-2026)"
    }()
}

/// The URLSession delegate of one ``HttpDataFetcher/get(_:ifNoneMatch:maxBytes:)``: collects
/// at most `cap` body bytes and resumes the continuation exactly once.
private final class CappedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let cap: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var continuation: CheckedContinuation<HttpResult, Never>?
    private var finished = false
    /// The running task, until the result is in (for the headers deadline).
    private var task: URLSessionDataTask?

    init(cap: Int) {
        self.cap = cap
    }

    func start(_ task: URLSessionDataTask, headersDeadline: DispatchTimeInterval, _ c: CheckedContinuation<HttpResult, Never>) {
        lock.lock()
        continuation = c
        self.task = task
        lock.unlock()
        task.resume()
        DispatchQueue.global().asyncAfter(deadline: .now() + headersDeadline) { [weak self] in
            self?.headersDeadlinePassed()
        }
    }

    /// Kotlin's connect + read timeouts before the response: no headers yet, give up.
    private func headersDeadlinePassed() {
        lock.lock()
        let t = task
        lock.unlock()
        guard let t, t.response == nil else { return }
        if finish(.failed("SocketTimeoutException: no response")) { t.cancel() }
    }

    /// Resumes the caller with `result` unless that already happened. True if this call did.
    @discardableResult
    private func finish(_ result: HttpResult) -> Bool {
        lock.lock()
        guard !finished, let c = continuation else {
            lock.unlock()
            return false
        }
        finished = true
        continuation = nil
        task = nil
        lock.unlock()
        c.resume(returning: result)
        return true
    }

    private var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private static func etag(_ r: HTTPURLResponse) -> String? { r.value(forHTTPHeaderField: "ETag") }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isFinished else { return }
        guard let http = dataTask.response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            // Don't download an error page: the status is all that matters.
            if finish(http.statusCode == 304 ? .notModified : .failed("HTTP \(http.statusCode)")) { dataTask.cancel() }
            return
        }
        lock.lock()
        let room = cap - buffer.count
        let full: Data?
        if data.count >= room {
            buffer.append(data.prefix(room))
            full = buffer
        } else {
            buffer.append(data)
            full = nil
        }
        lock.unlock()
        if let full, finish(.ok(body: full, etag: CappedDownload.etag(http))) { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            // Kotlin: "UnknownHostException: Unable to resolve host …".
            if let e = error as? URLError {
                finish(.failed("URLError \(e.code.rawValue): \(e.localizedDescription)"))
            } else {
                finish(.failed(DataSync.describe(error)))
            }
            return
        }
        guard let http = task.response as? HTTPURLResponse else {
            finish(.failed("IOException: not an HTTP response"))
            return
        }
        switch http.statusCode {
        case 304: finish(.notModified)
        case 200...299:
            lock.lock()
            let body = buffer
            lock.unlock()
            finish(.ok(body: body, etag: CappedDownload.etag(http)))
        default: finish(.failed("HTTP \(http.statusCode)"))
        }
    }
}
