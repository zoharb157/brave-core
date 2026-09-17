import Foundation

public struct NetworkSafetyTransport: SafetyTransport {
  private let endpoint: URL
  private let session: URLSession
  private let deviceID: String?

  /// - Parameter deviceID: a random id this install made for itself, sent so
  ///   the service can ration checks per phone. Without it every copy of the
  ///   app shares one allowance per network, and a school's worth of phones
  ///   runs out together. Not a credential: never pass the device token here.
  public init(endpoint: URL, session: URLSession = .shared, deviceID: String? = nil) {
    self.endpoint = endpoint; self.session = session; self.deviceID = deviceID
  }

  /// `audience: general` asks the service for copy addressed to the user
  /// themselves. The default (`kids`) is the Kid Safe app's parent framing.
  func request(for url: URL, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let deviceID { request.setValue(deviceID, forHTTPHeaderField: "x-device-id") }
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
