import Foundation

public enum HTTPTransferError: LocalizedError, Equatable {
    case timedOut
    case tooLarge
    case invalidResponse
    public var errorDescription: String? {
        switch self {
        case .timedOut: "The server did not respond before the time limit."
        case .tooLarge: "The response exceeded the safe size limit."
        case .invalidResponse: "The server returned an unreadable response."
        }
    }
}

/// A wall-clock deadline, bounded streaming buffer and cancellation share one
/// completion gate. URLRequest's timeout alone is only an inactivity timeout.
public struct BoundedHTTPClient: @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }

    public func data(for request: URLRequest, timeout: TimeInterval = 12, maximumBytes: Int = 10 * 1024 * 1024) async throws -> (Data, HTTPURLResponse) {
        let transfer = HTTPTransfer(configuration: configuration, request: request, timeout: timeout, maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { transfer.start($0) }
        } onCancel: {
            transfer.finish(.failure(CancellationError()))
        }
    }

    public func download(for request: URLRequest, timeout: TimeInterval = 45, maximumBytes: Int = 100 * 1024 * 1024) async throws -> (URL, HTTPURLResponse) {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf.part")
        let transfer = HTTPTransfer(configuration: configuration, request: request, timeout: timeout, maximumBytes: maximumBytes, destination: destination)
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { transfer.start($0) }
        } onCancel: { transfer.finish(.failure(CancellationError())) }
        return (destination, result.1)
    }
}

private final class HTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Response = (Data, HTTPURLResponse)
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private let request: URLRequest
    private let timeout: TimeInterval
    private let maximumBytes: Int
    private var continuation: CheckedContinuation<Response, Error>?
    private var terminalResult: Result<Response, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var timer: DispatchSourceTimer?
    private var response: HTTPURLResponse?
    private var buffer = Data()
    private let destination: URL?
    private var file: FileHandle?
    private var receivedBytes = 0

    init(configuration: URLSessionConfiguration, request: URLRequest, timeout: TimeInterval, maximumBytes: Int, destination: URL? = nil) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.request = request
        self.timeout = max(0.01, timeout)
        self.maximumBytes = max(1, maximumBytes)
        self.destination = destination
    }

    func start(_ continuation: CheckedContinuation<Response, Error>) {
        lock.lock()
        if let result = terminalResult {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        if let destination {
            do {
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                file = try FileHandle(forWritingTo: destination)
            } catch { lock.unlock(); finish(.failure(error)); return }
        }
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var boundedRequest = request
        boundedRequest.timeoutInterval = timeout
        let task = session.dataTask(with: boundedRequest)
        self.task = task
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in self?.finish(.failure(HTTPTransferError.timedOut)) }
        self.timer = timer
        timer.resume()
        task.resume()
        lock.unlock()
    }

    func finish(_ result: Result<Response, Error>) {
        lock.lock()
        guard terminalResult == nil else { lock.unlock(); return }
        terminalResult = result
        let continuation = self.continuation
        let task = self.task
        let session = self.session
        let timer = self.timer
        let file = self.file
        self.continuation = nil; self.task = nil; self.session = nil; self.timer = nil
        self.file = nil
        buffer = Data()
        lock.unlock()
        timer?.cancel()
        try? file?.close()
        if case .failure = result, let destination { try? FileManager.default.removeItem(at: destination) }
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); finish(.failure(HTTPTransferError.invalidResponse)); return
        }
        guard response.expectedContentLength <= maximumBytes else {
            completionHandler(.cancel); finish(.failure(HTTPTransferError.tooLarge)); return
        }
        lock.lock()
        let finished = terminalResult != nil
        if !finished { self.response = http }
        lock.unlock()
        completionHandler(finished ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard terminalResult == nil else { lock.unlock(); return }
        if data.count > maximumBytes - receivedBytes {
            lock.unlock(); finish(.failure(HTTPTransferError.tooLarge)); return
        }
        receivedBytes += data.count
        do {
            if let file { try file.write(contentsOf: data) } else { buffer.append(data) }
        } catch { lock.unlock(); finish(.failure(error)); return }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let data = buffer
        let response = self.response
        lock.unlock()
        if let error { finish(.failure(error)) }
        else if let response { finish(.success((data, response))) }
        else { finish(.failure(HTTPTransferError.invalidResponse)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward credentials to another host, or downgrade HTTPS.
        guard request.url?.host == self.request.url?.host, request.url?.scheme == "https" else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}
