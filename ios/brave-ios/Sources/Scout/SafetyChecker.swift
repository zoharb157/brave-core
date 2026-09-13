import Foundation

public enum CheckStatus { case ok, timeout, error }
public struct CheckResult { public let status: CheckStatus; public let verdict: Verdict?
  public init(status: CheckStatus, verdict: Verdict?) { self.status = status; self.verdict = verdict } }

public protocol SafetyChecker {
  func check(_ url: URL, timeout: TimeInterval) async -> CheckResult
}

public protocol SafetyTransport {
  func send(_ url: URL, timeout: TimeInterval) async -> CheckResult
}

/// Runs one check at a time per key, so tabs opening the same thing at once
/// make one request.
///
/// The key must match how the verdict will be cached: coalescing two pages that
/// are cached apart would hand the second page the first one's verdict, and the
/// second page would never actually be checked.
public actor CoalescingSafetyChecker: SafetyChecker {
  private let transport: SafetyTransport
  private let key: @Sendable (URL) -> String
  private var inFlight: [String: Task<CheckResult, Never>] = [:]

  public init(
    transport: SafetyTransport,
    key: @escaping @Sendable (URL) -> String = { eTLDPlusOne($0.host ?? $0.absoluteString) }
  ) {
    self.transport = transport
    self.key = key
  }

  public func check(_ url: URL, timeout: TimeInterval) async -> CheckResult {
    let key = self.key(url)
    if let existing = inFlight[key] { return await existing.value }
    let task = Task { await transport.send(url, timeout: timeout) }
    inFlight[key] = task
    let result = await task.value
    inFlight[key] = nil
    return result
  }
}
