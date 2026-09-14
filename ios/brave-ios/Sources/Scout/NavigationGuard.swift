import Foundation

public enum DecisionType { case allow, warn, block }

/// Spec §4.4: why a Decision came out the way it did.
///
/// `address` is a category block decided from the URL alone, with no verdict
/// involved. It is kept apart from `category` because the two fail in
/// different ways: one means the check judged the page, the other means the
/// check never got a say — and telling them apart is what makes an escape
/// traceable.
public enum DecisionReason: Equatable, Sendable {
  case policyList, scheme, security, category, address, unavailable
}

public struct Decision {
  public let type: DecisionType
  public let verdict: Verdict?
  public let reason: DecisionReason
  /// Non-empty only when `reason == .category`: the blocked categories that
  /// this verdict actually matched, so the interstitial can name them.
  public let matchedCategories: Set<ContentCategory>
  /// Decided from a verdict that is past its TTL but still within the grace
  /// window: usable now, and worth refreshing in the background.
  public let isStale: Bool
  public init(type: DecisionType, verdict: Verdict? = nil, reason: DecisionReason,
              matchedCategories: Set<ContentCategory> = [], isStale: Bool = false) {
    self.type = type; self.verdict = verdict; self.reason = reason
    self.matchedCategories = matchedCategories
    self.isStale = isStale
  }
}

public final class NavigationGuard {
  private let policy: PolicyProviding
  private let cache: VerdictCache
  private let checker: SafetyChecker
  private let timeout: TimeInterval
  private let isReachable: () -> Bool
  private let staleGrace: TimeInterval

  /// - Parameter isReachable: whether the network can reach the service at all.
  ///   With no network the check can only time out, so the guard skips it and
  ///   applies `failMode` immediately instead of making every navigation wait
  ///   out the timeout.
  /// - Parameter staleGrace: how long past its TTL a verdict may still decide a
  ///   navigation. Without it the first visit after a verdict expires waits out
  ///   a whole fresh check; within the window the known answer is used and the
  ///   entry is refreshed in the background (`Decision.isStale`).
  public init(policy: PolicyProviding, cache: VerdictCache,
              checker: SafetyChecker, timeout: TimeInterval,
              isReachable: @escaping () -> Bool = { true },
              staleGrace: TimeInterval = 24 * 3600) {
    self.policy = policy; self.cache = cache
    self.checker = checker; self.timeout = timeout
    self.isReachable = isReachable
    self.staleGrace = staleGrace
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
    // Read the address before the cache, not after. A verdict is keyed by site,
    // so an injected page on an otherwise clean domain inherits that domain's
    // clean answer — and no amount of re-fetching fixes it, because the rest of
    // the domain really is clean. The address is per-page and free.
    //
    // After the user's own rules, though: someone who chose "always allow this
    // site" has answered this question already.
    if policy.blockedCategories.contains(.adult), ExplicitURL.looksExplicit(url) {
      return Decision(type: .block, reason: .address, matchedCategories: [.adult])
    }
    if let cached = cache.lookup(url, grace: staleGrace) {
      let decision = Self.resolve(cached.verdict, blockedCategories: policy.blockedCategories)
      return Decision(
        type: decision.type, verdict: decision.verdict, reason: decision.reason,
        matchedCategories: decision.matchedCategories, isStale: cached.isStale)
    }
    if !isReachable() {
      return Self.resolveFailure(policy.failMode)
    }
    return nil
  }

  /// Re-checks `url` and updates the cache, discarding the decision. For a
  /// navigation that went ahead on a stale verdict, so the next one is fresh.
  public func refresh(_ url: URL) async {
    guard isReachable() else { return }
    let result = await checker.check(url, timeout: timeout)
    if result.status == .ok, let v = result.verdict {
      cache.put(url, v)
    }
  }

  public func decide(_ url: URL) async -> Decision {
    if let immediate = decideImmediately(url) {
      return immediate
    }
    var result = await checker.check(url, timeout: timeout)
    // A refused connection or a 500 is usually a blip, and failing open on one
    // is how an unchecked page slips through. A timeout is not retried: the
    // budget is already spent and the user is waiting.
    if result.status == .error {
      result = await checker.check(url, timeout: timeout)
    }
    if result.status == .ok, let v = result.verdict {
      cache.put(url, v)
      return Self.resolve(v, blockedCategories: policy.blockedCategories)
    }
    return Self.resolveFailure(policy.failMode)
  }
}
