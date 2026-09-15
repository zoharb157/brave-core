import Foundation

/// Somewhere to look before asking the network.
public protocol WarmListProviding {
  func verdict(for url: URL) -> Verdict?
}

/// Verdicts for the sites people open most, shipped as a file.
///
/// Read-only, and deliberately *not* part of `VerdictCache`. That cache holds
/// two thousand entries and evicts the least recently used; pouring ten
/// thousand list entries through it would throw away everything this phone's
/// own browsing had earned. Kept apart and consulted only when the cache
/// misses, a verdict the phone fetched for itself always wins without needing
/// a rule that says so.
public final class WarmList: WarmListProviding {
  public let version: String
  public var count: Int { entries.count }

  private let entries: [String: Verdict]
  private let builtAt: Date
  private let confirmedCurrentAt: Date?
  private let now: () -> Date
  private let maxAge: TimeInterval
  private let perPageHosts: Set<String>

  /// - Parameter maxAge: how long the file may answer for before the phone
  ///   goes back to asking. A device that stops updating should ask, not trust
  ///   a file from months ago.
  /// - Parameter confirmedCurrentAt: when the server last said this exact
  ///   version is still the list it would send. The entry set is hash-stable
  ///   and moves slowly, so a phone can go past `maxAge` while holding the
  ///   list the server would hand it anyway — at which point the list would
  ///   stop answering for good, since a "you're current" reply never brings a
  ///   new `builtAt` to age from. This is the server's own timestamp from that
  ///   reply, not a mark the phone makes on its own: it says "re-asserted at
  ///   X" while `builtAt` goes on saying, honestly, when the list was made.
  public init?(
    data: Data, now: @escaping () -> Date, maxAge: TimeInterval, perPageHosts: Set<String>,
    confirmedCurrentAt: Date? = nil
  ) {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let version = object["version"] as? String,
      let builtAt = object["builtAt"] as? TimeInterval,
      let rows = object["entries"] as? [[String: Any]]
    else { return nil }

    var parsed: [String: Verdict] = [:]
    let stamp = Date(timeIntervalSince1970: builtAt)
    for row in rows {
      guard let rawKey = row["key"] as? String,
        let security = (row["security"] as? String).flatMap(SecurityStatus.init(rawValue:))
      else { continue }
      // Lower-cased once, here, for both the check below and the stored key.
      // `perPageHosts` holds lower-cased hosts and `VerdictCache.cacheKey`
      // lower-cases before it looks anything up, so a key that arrived as
      // "Wikipedia.org" used to slip past the filter *and* then never match a
      // lookup — a row that was both wrongly kept and permanently unreachable.
      let key = rawKey.lowercased()
      // A per-page host is keyed by page; a bare-domain answer for one is
      // exactly the thing keying them per page exists to prevent. This is a
      // belt-and-suspenders check at parse time — the guarantee that actually
      // holds regardless of how the file was built lives in `verdict(for:)`.
      if perPageHosts.contains(key) { continue }
      // The warm list exists so a phone doesn't have to wait before showing a
      // site that is fine. A site that is *not* fine should get a real check
      // instead: that's the only place a verdict gets the title/summary/
      // reasons a block screen needs, and it means a bad or stale list can
      // never cause a block — only fail to prevent a wait. Categories are
      // still carried, since category blocking has its own copy and doesn't
      // read these fields.
      guard security == .safe else { continue }
      parsed[key] = Verdict(
        security: security,
        categories: ContentCategory.set(fromWire: row["categories"] as? [String] ?? []),
        title: "", summary: "", reasons: [],
        fetchedAt: stamp)
    }

    self.version = version
    self.entries = parsed
    self.builtAt = stamp
    self.confirmedCurrentAt = confirmedCurrentAt
    self.now = now
    self.maxAge = maxAge
    self.perPageHosts = perPageHosts
  }

  /// The instant `maxAge` is measured from: the later of when the list was
  /// built and when the server last said it is still the current one.
  private var lastAffirmed: Date {
    guard let confirmedCurrentAt else { return builtAt }
    return max(builtAt, confirmedCurrentAt)
  }

  /// A warm verdict for `url`, or `nil` if there isn't one, the list is too
  /// old, or `url`'s host is one this phone must never answer for from the
  /// list.
  ///
  /// The returned verdict's `fetchedAt` is when the *list* was built, not
  /// when this site was last checked, and not `confirmedCurrentAt` either —
  /// it can be well over `maxAge` older than now. A caller that surfaces it as "just checked" (the way
  /// `VerdictCache.storedAt` is used today) would overstate how fresh the
  /// answer is.
  public func verdict(for url: URL) -> Verdict? {
    guard now().timeIntervalSince(lastAffirmed) < maxAge else { return nil }
    // This is the guard that actually holds regardless of how the file was
    // built: even a wrongly built list — one carrying a per-page-format row
    // like "wikipedia.org/wiki/Cat" — must never answer for a per-page host.
    // Lower-cased to match `VerdictCache`, which lower-cases before this same
    // check.
    guard let host = url.host else { return nil }
    let site = eTLDPlusOne(host)
    guard !VerdictCache.isPerPage(host: host.lowercased(), site: site, in: perPageHosts) else {
      return nil
    }
    return entries[VerdictCache.cacheKey(for: url, perPageHosts: perPageHosts)]
  }
}
