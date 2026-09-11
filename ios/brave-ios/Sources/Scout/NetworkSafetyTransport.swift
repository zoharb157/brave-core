import Foundation

public struct NetworkSafetyTransport: SafetyTransport {
  private let endpoint: URL
  private let session: URLSession

  public init(endpoint: URL, session: URLSession = .shared) {
    self.endpoint = endpoint; self.session = session
  }

  public func send(_ url: URL, timeout: TimeInterval) async -> CheckResult {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["url": url.absoluteString])
    do {
      let (data, response) = try await session.data(for: request)
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
