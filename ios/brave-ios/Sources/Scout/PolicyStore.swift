import Foundation

public enum LocalDecision { case allow, block, unknown }

public func eTLDPlusOne(_ host: String) -> String {
  let parts = host.split(separator: ".")
  guard parts.count > 2 else { return host }
  return parts.suffix(2).joined(separator: ".")
}

private func globMatch(_ text: String, _ pattern: String) -> Bool {
  // '*' matches any run of characters (including dots).
  let escaped = NSRegularExpression.escapedPattern(for: pattern)
    .replacingOccurrences(of: "\\*", with: ".*")
  guard let re = try? NSRegularExpression(pattern: "^\(escaped)$") else { return false }
  let range = NSRange(text.startIndex..., in: text)
  return re.firstMatch(in: text, range: range) != nil
}

private func hostMatches(_ host: String, _ etld1: String, _ pattern: String) -> Bool {
  if pattern.contains("*") { return globMatch(host, pattern) }
  return pattern == host || pattern == etld1
}

public protocol PolicyProviding: AnyObject {
  func decideHost(_ url: URL) -> LocalDecision
  func schemeDecision(_ url: URL) -> SchemeRule?
  var blockedCategories: Set<ContentCategory> { get }
  var failMode: FailMode { get }
}

public final class PolicyStore {
  private var policy: Policy
  public init(policy: Policy) { self.policy = policy }

  public var blockedCategories: Set<ContentCategory> { policy.blockedCategories }
  public var failMode: FailMode { policy.failMode }
  public func setPolicy(_ p: Policy) { policy = p }

  public func decideHost(_ url: URL) -> LocalDecision {
    guard let host = url.host else { return .unknown }
    let etld1 = eTLDPlusOne(host)
    if policy.allow.contains(where: { hostMatches(host, etld1, $0) }) { return .allow }
    if policy.block.contains(where: { hostMatches(host, etld1, $0) }) { return .block }
    return .unknown
  }

  public func schemeDecision(_ url: URL) -> SchemeRule? {
    guard let scheme = url.scheme else { return nil }
    return policy.schemes[scheme]
  }
}

extension PolicyStore: PolicyProviding {}
