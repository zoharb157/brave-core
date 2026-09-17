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
  /// The site's certificate does not check out and the person went on past
  /// the warning anyway, on a supervised phone. Not a decision the guard
  /// reaches: the browser reports it once the page has committed, because
  /// nothing is asked of the guard before the warning is shown.
  case insecureCertificate
  /// A results page from a search engine Scout cannot put into safe mode, on
  /// a supervised phone. See `SafeSearch.isUnfilteredResults`.
  case unfilteredSearch
  /// The host is on a public list of sites caught phishing or serving
  /// malware. Kept apart from `security` for the same reason `address` is: no
  /// page was fetched and no verdict was made, so this was not judged — it
  /// was recognised. Reading the log back, "the check read this page and
  /// called it an attack" and "this address is already publicly known to be
  /// one" are different facts about how much is known.
  case knownThreat
  /// The check could not be completed *and* the address itself reads as a
  /// trap. Two facts, and the reason has to carry both: on its own the first
  /// is `.unavailable`, which is a shrug, and the second was never a reason
  /// for anything because the address was only ever scored by the service.
  /// See `AddressRisk`.
  case uncheckedAddress
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
  private let warmList: WarmListProviding?
  private let threatList: ThreatListProviding?

  /// - Parameter isReachable: whether the network can reach the service at all.
  ///   With no network the check can only time out, so the guard skips it and
  ///   applies `failMode` immediately instead of making every navigation wait
  ///   out the timeout.
  /// - Parameter staleGrace: how long past its TTL a verdict may still decide a
  ///   navigation. Without it the first visit after a verdict expires waits out
  ///   a whole fresh check; within the window the known answer is used and the
  ///   entry is refreshed in the background (`Decision.isStale`).
  /// - Parameter warmList: verdicts for the sites people open most, shipped as
  ///   a file. Consulted after the cache and before the network check, so a
  ///   verdict this phone fetched for itself always wins.
  /// - Parameter threatList: hosts publicly known to be phishing or serving
  ///   malware. Consulted before both the cache and the warm list — see
  ///   `decideImmediately` for why that order is the whole point of it.
  public init(policy: PolicyProviding, cache: VerdictCache,
              checker: SafetyChecker, timeout: TimeInterval,
              isReachable: @escaping () -> Bool = { true },
              staleGrace: TimeInterval = 24 * 3600,
              warmList: WarmListProviding? = nil,
              threatList: ThreatListProviding? = nil) {
    self.policy = policy; self.cache = cache
    self.checker = checker; self.timeout = timeout
    self.isReachable = isReachable
    self.staleGrace = staleGrace
    self.warmList = warmList
    self.threatList = threatList
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

  /// What to do when the check produced no answer at all.
  ///
  /// The fail mode is the user's choice and it decides this, with one thing
  /// read first: the address. A check that could not finish is the only moment
  /// nothing whatsoever has looked at the page — no verdict, no cache, no
  /// list — and "open, marked" is a default an unsupervised phone is left on.
  /// An address that reads as a trap is not a page to apply that default to,
  /// so a `.dangerous` shape is blocked whatever the fail mode says, and a
  /// `.doubtful` one is at least asked about.
  ///
  /// It cannot go the other way: nothing here ever opens a page the fail mode
  /// would have stopped. A quiet-looking address is not evidence of anything —
  /// it is the absence of evidence, which is what `.unavailable` already means.
  ///
  /// This runs only where the check failed. Where it answered, the service
  /// scored the address too, and its answer is the one that stands.
  public static func resolveFailure(_ failMode: FailMode, for url: URL?) -> Decision {
    switch url.map(AddressRisk.judge)?.level {
    case .dangerous:
      return Decision(type: .block, reason: .uncheckedAddress)
    case .doubtful:
      return Decision(type: .warn, reason: .uncheckedAddress)
    case .ordinary, nil:
      switch failMode {
      case .open: return Decision(type: .allow, reason: .unavailable)
      case .closed: return Decision(type: .warn, reason: .unavailable)
      }
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
    // Before the cache and before the warm list, and that ordering is the
    // reason this list is worth having at all. Both of those say a site was
    // fine when somebody last looked, and neither can ever change its mind on
    // its own: a site checked clean is cached clean for a week, and a site on
    // the warm list is one lots of people opened safely. Sites are compromised
    // and domains change hands inside those windows, and when that happens the
    // public lists are what hears about it first. A rule that consulted them
    // after a cached "safe" would hear about it and then not act on it.
    //
    // Still behind the user's own rules, though, and behind the address check.
    // Someone who said "always allow this site" has answered a question about
    // a site they know, and taking that away on a downloaded file would be
    // Scout overruling its own user — the honest place to argue with them is
    // the block page, which they will see on any site they have not allowed.
    if threatList?.listsAsThreat(url) == true {
      return Decision(type: .block, reason: .knownThreat)
    }
    if let cached = cache.lookup(url, grace: staleGrace) {
      let decision = Self.resolve(cached.verdict, blockedCategories: policy.blockedCategories)
      return Decision(
        type: decision.type, verdict: decision.verdict, reason: decision.reason,
        matchedCategories: decision.matchedCategories, isStale: cached.isStale)
    }
    // After the cache, never before it. A verdict this phone fetched is newer
    // and more specific than a list entry, and consulting the cache first is
    // what makes that true without a rule that says so.
    if let warm = warmList?.verdict(for: url) {
      return Self.resolve(warm, blockedCategories: policy.blockedCategories)
    }
    if !isReachable() {
      return Self.resolveFailure(policy.failMode, for: url)
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
    // One attempt. Retrying an error used to be worth it against a twelve
    // second timeout, where a blip cost less than a wrong answer. Against four
    // it costs eight seconds of somebody staring at a blank tab, which is the
    // wait this exists to remove — and a check that fails still has a fail mode
    // to fall to, which is a user's choice rather than a guess.
    let result = await checker.check(url, timeout: timeout)
    if result.status == .ok, let v = result.verdict {
      cache.put(url, v)
      return Self.resolve(v, blockedCategories: policy.blockedCategories)
    }
    return Self.resolveFailure(policy.failMode, for: url)
  }
}

/// What to do while a verdict is still coming.
public enum MissBehaviour: Equatable, Sendable {
  /// Show nothing until the answer arrives.
  case wait
  /// Open the page now; take it back if the answer is bad.
  case renderOptimistically
}

extension NavigationGuard {
  /// Whether a page may be shown before it has been judged.
  ///
  /// Someone who chose their own categories may have the page now and lose it
  /// if the verdict is bad. A supervised phone may not: not rendering before a
  /// verdict is the promise supervision is sold on, and it is not tradeable
  /// for speed.
  ///
  /// This is a pure function so the rule can be tested. Be clear about what
  /// that buys: it pins the rule, not the wiring. Nothing here can tell you
  /// that the browser actually asks it before letting a page through — only
  /// reading the call site, and watching a supervised phone, can.
  public static func missBehaviour(supervised: Bool) -> MissBehaviour {
    supervised ? .wait : .renderOptimistically
  }
}
