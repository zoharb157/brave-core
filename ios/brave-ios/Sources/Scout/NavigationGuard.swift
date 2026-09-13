import Foundation

public enum DecisionType { case allow, warn, block }

/// Spec §4.4: why a Decision came out the way it did. Distinct from
/// `DecisionType` (what happened) — this says which pipeline stage decided.
public enum DecisionReason: Equatable { case policyList, scheme, security, category, unavailable }

public struct Decision {
  public let type: DecisionType
  public let verdict: Verdict?
  public let reason: DecisionReason
  /// Non-empty only when `reason == .category`: the blocked categories that
  /// this verdict actually matched, so the interstitial can name them.
  public let matchedCategories: Set<ContentCategory>
  public init(type: DecisionType, verdict: Verdict? = nil, reason: DecisionReason,
              matchedCategories: Set<ContentCategory> = []) {
    self.type = type; self.verdict = verdict; self.reason = reason
    self.matchedCategories = matchedCategories
  }
}

public final class NavigationGuard {
  private let policy: PolicyProviding
  private let cache: VerdictCache
  private let checker: SafetyChecker
  private let timeout: TimeInterval
  private let isReachable: () -> Bool

  /// - Parameter isReachable: whether the network can reach the service at all.
  ///   With no network the check can only time out, so the guard skips it and
  ///   applies `failMode` immediately instead of making every navigation wait
  ///   out the timeout.
  public init(policy: PolicyProviding, cache: VerdictCache,
              checker: SafetyChecker, timeout: TimeInterval,
              isReachable: @escaping () -> Bool = { true }) {
    self.policy = policy; self.cache = cache
    self.checker = checker; self.timeout = timeout
    self.isReachable = isReachable
  }

  /// Resolves a fetched/cached `Verdict` against the user's chosen
  /// `blockedCategories`. There is no parent and no override tier here — the
  /// only inputs are the backend's security read and the user's own category
  /// choices.
  ///
  /// Reason choice for the final `.allow` branch: `.security` is used (rather
  /// than introducing a fifth "everything's fine" reason) because reaching
  /// that branch means security was actively consulted and found not
  /// malicious/suspicious — the allow *is* a security-driven outcome, just a
  /// positive one. `.category` is reserved for branches where a category
  /// match is what drove the decision.
  public static func resolve(_ verdict: Verdict, blockedCategories: Set<ContentCategory>) -> Decision {
    if verdict.security == .malicious {
      return Decision(type: .block, verdict: verdict, reason: .security)
    }
    let matched = verdict.categories.intersection(blockedCategories)
    if !matched.isEmpty {
      return Decision(type: .block, verdict: verdict, reason: .category, matchedCategories: matched)
    }
    if verdict.security == .suspicious {
      return Decision(type: .warn, verdict: verdict, reason: .security)
    }
    return Decision(type: .allow, verdict: verdict, reason: .security)
  }

  public static func resolveFailure(_ failMode: FailMode) -> Decision {
    switch failMode {
    case .open: return Decision(type: .allow, reason: .unavailable)
    case .closed: return Decision(type: .warn, reason: .unavailable)
    }
  }

  private func isHTTP(_ url: URL) -> Bool {
    url.scheme == "http" || url.scheme == "https"
  }

  /// The decision if it needs no network call (scheme rule, policy list, or a
  /// cached verdict), otherwise nil. Lets the browser skip the "checking" page
  /// entirely for anything it already knows.
  public func decideImmediately(_ url: URL) -> Decision? {
    if !isHTTP(url) {
      switch policy.schemeDecision(url) {
      case .some(.allow): return Decision(type: .allow, reason: .scheme)
      case .some(.block), .none: return Decision(type: .block, reason: .scheme)
      }
    }
    switch policy.decideHost(url) {
    case .allow: return Decision(type: .allow, reason: .policyList)
    case .block: return Decision(type: .block, reason: .policyList)
    case .unknown: break
    }
    if let cached = cache.get(url) {
      return Self.resolve(cached, blockedCategories: policy.blockedCategories)
    }
    if !isReachable() {
      return Self.resolveFailure(policy.failMode)
    }
    return nil
  }

  public func decide(_ url: URL) async -> Decision {
    if let immediate = decideImmediately(url) {
      return immediate
    }
    let result = await checker.check(url, timeout: timeout)
    if result.status == .ok, let v = result.verdict {
      cache.put(url, v)
      return Self.resolve(v, blockedCategories: policy.blockedCategories)
    }
    return Self.resolveFailure(policy.failMode)
  }
}
