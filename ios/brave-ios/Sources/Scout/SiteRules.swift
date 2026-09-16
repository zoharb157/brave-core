import Foundation

/// What the user decided about one site, by hand.
public enum SiteRule: String, Sendable { case allow, block }

/// The user's own per-site decisions, overriding both the safety check and the
/// category settings.
///
/// Without this, "continue anyway" is a one-navigation reprieve: the same site
/// is blocked again on the next tap, which reads as the browser not listening.
/// And a parent who wants one specific site gone has no way to say so — the
/// only lever is a whole category. A rule here is the user's answer, so it is
/// consulted before anything else and never expires.
///
/// Rules are keyed by registrable domain: allowing `example.com` allows its
/// subdomains too, which is what someone picking "always allow" on a page
/// means. `perPageHosts` sites (where one verdict can't speak for the whole
/// domain) are deliberately no exception — a rule is an explicit human
/// decision about a site, not an inference from one page.
public final class SiteRules {
  /// Guards `rules`.
  ///
  /// `NavigationGuard.decide` is `async` and not actor-bound, so every rule it
  /// consults is read off the main actor, while "always allow this site" and
  /// the Settings lists write from the main actor. A Dictionary mutated while
  /// another thread reads it crashes — that exact shape already took the
  /// browser down once in `VerdictCache`.
  ///
  /// Plain, not recursive: nothing here nests, and `onChange` is deliberately
  /// called after the lock is released, so a callback that comes back in
  /// cannot deadlock.
  private let lock = NSLock()
  private var rules: [String: SiteRule]
  /// Called after every change, so the browser can persist without this type
  /// knowing where preferences live.
  public var onChange: (() -> Void)?

  public init(rules: [String: SiteRule] = [:]) {
    self.rules = rules
  }

  /// The rule covering `url`, if the user set one.
  public func rule(for url: URL) -> SiteRule? {
    guard let host = url.host else { return nil }
    return rule(forSite: host)
  }

  public func rule(forSite site: String) -> SiteRule? {
    let key = eTLDPlusOne(site)
    lock.lock()
    defer { lock.unlock() }
    return rules[key]
  }

  /// Sets (or with `nil`, clears) the rule for `url`'s site. Setting one
  /// replaces the other: a site is allowed or blocked, never both.
  public func set(_ rule: SiteRule?, for url: URL) {
    guard let host = url.host else { return }
    set(rule, forSite: host)
  }

  public func set(_ rule: SiteRule?, forSite site: String) {
    let key = eTLDPlusOne(site)
    guard !key.isEmpty else { return }
    lock.lock()
    if rules[key] == rule {
      lock.unlock()
      return
    }
    rules[key] = rule
    lock.unlock()
    onChange?()
  }

  /// Every site the user allowed, and every site they blocked — sorted, so
  /// the lists in Settings don't reshuffle between visits.
  public func sites(_ rule: SiteRule) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return rules.filter { $0.value == rule }.keys.sorted()
  }

  public var isEmpty: Bool {
    lock.lock()
    defer { lock.unlock() }
    return rules.isEmpty
  }

  public func removeAll() {
    lock.lock()
    if rules.isEmpty {
      lock.unlock()
      return
    }
    rules.removeAll()
    lock.unlock()
    onChange?()
  }

  // MARK: - Persistence

  /// A plain `[site: rule]` dictionary, the shape a preference can hold.
  public func serialize() -> [String: String] {
    lock.lock()
    defer { lock.unlock() }
    return rules.mapValues(\.rawValue)
  }

  public static func deserialize(_ wire: [String: String]) -> SiteRules {
    SiteRules(rules: wire.compactMapValues(SiteRule.init(rawValue:)))
  }
}

/// A policy whose allow and block lists are the user's own per-site rules,
/// read live on every decision; everything else comes from `base`.
///
/// Sits in front of `base` for the same reason `UserCategoryPolicy` does: the
/// browser backs it with a persisted preference, so tapping "always allow" on
/// a blocked page applies to the very next navigation with nothing to push.
public final class UserSitePolicy: PolicyProviding {
  private let base: PolicyProviding
  private let rules: () -> SiteRules

  public init(base: PolicyProviding, rules: @escaping () -> SiteRules) {
    self.base = base
    self.rules = rules
  }

  public var blockedCategories: Set<ContentCategory> { base.blockedCategories }
  public var failMode: FailMode { base.failMode }
  public func schemeDecision(_ url: URL) -> SchemeRule? { base.schemeDecision(url) }

  public func decideHost(_ url: URL) -> LocalDecision {
    switch rules().rule(for: url) {
    case .allow: return .allow
    case .block: return .block
    case nil: return base.decideHost(url)
    }
  }
}
