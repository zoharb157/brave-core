import Foundation

public enum LocalDecision { case allow, block, unknown }

/// Public suffixes made of two labels, where the registrable name is the third
/// from the right: bbc.co.uk, not co.uk.
///
/// Curated rather than the full Public Suffix List: the list is thousands of
/// entries and needs updating, while these cover the overwhelming majority of
/// real browsing. A suffix missing from here degrades to the last two labels,
/// which is what every host used to get.
///
/// Mirrors MULTI_PART_PUBLIC_SUFFIXES in packages/cross/utils/url.ts — the same
/// list serves the safety service, so the two must agree on what a site is.
let multiPartPublicSuffixes: Set<String> = [
  // United Kingdom
  "co.uk", "org.uk", "gov.uk", "ac.uk", "me.uk", "net.uk", "sch.uk",
  // Australia
  "com.au", "net.au", "org.au", "edu.au", "gov.au",
  // New Zealand
  "co.nz", "net.nz", "org.nz",
  // South Africa
  "co.za", "org.za",
  // Japan
  "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp",
  // Brazil
  "com.br", "net.br", "org.br", "gov.br",
  // Other Latin America
  "com.mx", "com.ar",
  // Turkey
  "com.tr",
  // East / Southeast Asia
  "com.tw", "com.hk", "com.sg", "com.my", "com.ph", "com.vn",
  "com.cn", "net.cn", "org.cn", "gov.cn",
  // Korea
  "co.kr", "or.kr",
  // India
  "co.in", "net.in", "org.in", "gov.in", "ac.in",
  // Israel
  "co.il", "org.il", "gov.il", "ac.il",
  // Poland, Ukraine, Russia
  "com.pl", "com.ua", "com.ru",
  // Thailand, Egypt, Saudi Arabia, Nigeria, Pakistan, Bangladesh
  "co.th", "com.eg", "com.sa", "com.ng", "com.pk", "com.bd",
]

/// The registrable domain: the name someone actually registered, plus its
/// public suffix. Everything keyed per site — verdicts, allow and block lists,
/// in-flight checks — hangs off this, so treating "co.uk" as a site would let
/// one checked British site vouch for every other one.
public func eTLDPlusOne(_ host: String) -> String {
  let lowered = host.lowercased()
  // An address has no registrable domain, and splitting one on dots is worse
  // than useless: 1.2.3.4 and 9.9.3.4 would both reduce to "3.4" and share a
  // verdict, so a checked host would vouch for an unrelated one.
  if isAddressLiteral(lowered) { return lowered }
  let parts = lowered.split(separator: ".").map(String.init)
  guard parts.count > 2 else { return parts.joined(separator: ".") }
  let lastTwo = parts.suffix(2).joined(separator: ".")
  let suffixLabels = multiPartPublicSuffixes.contains(lastTwo) ? 2 : 1
  guard parts.count > suffixLabels else { return parts.joined(separator: ".") }
  return parts.suffix(suffixLabels + 1).joined(separator: ".")
}

/// Whether `host` is an IPv4 or IPv6 literal rather than a name.
private func isAddressLiteral(_ host: String) -> Bool {
  if host.contains(":") { return true }  // IPv6, bracketed or not
  let labels = host.split(separator: ".", omittingEmptySubsequences: false)
  guard labels.count == 4 else { return false }
  return labels.allSatisfy { label in
    !label.isEmpty && label.count <= 3 && label.allSatisfy(\.isNumber)
      && (Int(label).map { $0 <= 255 } ?? false)
  }
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
  /// Guards `policy`.
  ///
  /// `NavigationGuard.decide` is `async` and not actor-bound, so the policy is
  /// read off the main actor on every navigation, while Settings replaces it
  /// wholesale from the main actor. Replacing a struct holding Sets and a
  /// Dictionary while another thread reads it crashes — the same shape that
  /// already took the browser down once in `VerdictCache`.
  ///
  /// Every read takes a snapshot rather than touching `policy` field by field,
  /// so a decision is made against one coherent policy instead of half of the
  /// old one and half of the new.
  private let lock = NSLock()
  private var policy: Policy
  public init(policy: Policy) { self.policy = policy }

  private var current: Policy {
    lock.lock()
    defer { lock.unlock() }
    return policy
  }

  public var blockedCategories: Set<ContentCategory> { current.blockedCategories }
  public var failMode: FailMode { current.failMode }

  public func setPolicy(_ p: Policy) {
    lock.lock()
    policy = p
    lock.unlock()
  }

  public func decideHost(_ url: URL) -> LocalDecision {
    guard let host = url.host else { return .unknown }
    let etld1 = eTLDPlusOne(host)
    let policy = current
    if policy.allow.contains(where: { hostMatches(host, etld1, $0) }) { return .allow }
    if policy.block.contains(where: { hostMatches(host, etld1, $0) }) { return .block }
    return .unknown
  }

  public func schemeDecision(_ url: URL) -> SchemeRule? {
    guard let scheme = url.scheme else { return nil }
    return current.schemes[scheme]
  }
}

extension PolicyStore: PolicyProviding {}
