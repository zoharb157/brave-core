import Foundation

public struct NetworkSafetyTransport: SafetyTransport {
  private let endpoint: URL
  private let session: URLSession

  public init(endpoint: URL, session: URLSession = .shared) {
    self.endpoint = endpoint; self.session = session
  }

  /// `audience: general` asks the service for copy addressed to the user
  /// themselves. The default (`kids`) is the Kid Safe app's parent framing.
  func request(for url: URL, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["url": url.absoluteString, "audience": "general"])
    return request
  }

  public func send(_ url: URL, timeout: TimeInterval) async -> CheckResult {
    do {
      let (data, response) = try await session.data(for: request(for: url, timeout: timeout))
      guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            let verdict = Verdict.parse(data) else {
        return CheckResult(status: .error, verdict: nil)
      }
      return CheckResult(status: .ok, verdict: verdict)
    } catch let error as URLError where error.code == .timedOut {
      return CheckResult(status: .timeout, verdict: nil)
    } catch {
      return CheckResult(status: .error, verdict: nil)
    }
  }
}
