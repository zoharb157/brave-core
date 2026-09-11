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

public actor CoalescingSafetyChecker: SafetyChecker {
  private let transport: SafetyTransport
  private var inFlight: [String: Task<CheckResult, Never>] = [:]

  public init(transport: SafetyTransport) { self.transport = transport }

  public func check(_ url: URL, timeout: TimeInterval) async -> CheckResult {
    let key = eTLDPlusOne(url.host ?? url.absoluteString)
    if let existing = inFlight[key] { return await existing.value }
    let task = Task { await transport.send(url, timeout: timeout) }
    inFlight[key] = task
    let result = await task.value
    inFlight[key] = nil
    return result
  }
}
