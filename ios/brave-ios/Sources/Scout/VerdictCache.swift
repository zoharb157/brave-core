import Foundation

public final class VerdictCache {
  public static let safeTTL: TimeInterval = 7 * 24 * 3600
  public static let riskyTTL: TimeInterval = 24 * 3600

  private struct Entry { let verdict: Verdict; let storedAt: Date }

  private let maxEntries: Int
  private let now: () -> Date
  private var entries: [String: Entry] = [:]
  private var lru: [String] = []  // most-recent first

  public init(maxEntries: Int, now: @escaping () -> Date) {
    self.maxEntries = maxEntries; self.now = now
  }

  private func key(_ url: URL) -> String { Self.cacheKey(for: url) }

  private func ttl(for security: SecurityStatus) -> TimeInterval {
    security == .safe ? Self.safeTTL : Self.riskyTTL
  }

  private func isExpired(_ e: Entry) -> Bool {
    now().timeIntervalSince(e.storedAt) >= ttl(for: e.verdict.security)
  }

  private func touch(_ k: String) {
    lru.removeAll { $0 == k }
    lru.insert(k, at: 0)
  }

  public func get(_ url: URL) -> Verdict? {
    let k = key(url)
    guard let e = entries[k] else { return nil }
    if isExpired(e) { entries[k] = nil; lru.removeAll { $0 == k }; return nil }
    touch(k)
    return e.verdict
  }

  public func put(_ url: URL, _ verdict: Verdict) {
    let k = key(url)
    entries[k] = Entry(verdict: verdict, storedAt: now())
    touch(k)
    while entries.count > maxEntries, let last = lru.last {
      entries[last] = nil
      lru.removeLast()
    }
  }

  /// Forget every verdict — called when the user clears browsing history, since
  /// the keys are the sites they visited.
  public func removeAll() {
    entries.removeAll()
    lru.removeAll()
  }

  /// The key a URL is cached under — its eTLD+1. Callers need it to name
  /// entries they don't want written to disk (private browsing).
  public static func cacheKey(for url: URL) -> String {
    guard let host = url.host else { return url.absoluteString }
    return eTLDPlusOne(host)
  }

  public func serialize(excludingKeys excluded: Set<String> = []) -> Data {
    // Most-recent first, so a reload that trims to `maxEntries` keeps the
    // entries most likely to be wanted again.
    let arr: [[String: Any]] = lru.compactMap { k in
      guard let e = entries[k], !excluded.contains(k) else { return nil }
      return ["key": k, "security": e.verdict.security.rawValue,
              "categories": e.verdict.categories.map(\.rawValue),
              "title": e.verdict.title, "summary": e.verdict.summary,
              "reasons": e.verdict.reasons,
              "storedAt": e.storedAt.timeIntervalSince1970]
    }
    return (try? JSONSerialization.data(withJSONObject: arr)) ?? Data()
  }

  public func deserialize(_ data: Data) {
    entries.removeAll(); lru.removeAll()
    guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return }
    for d in arr {
      guard let k = d["key"] as? String,
            let securityStr = d["security"] as? String,
            let security = SecurityStatus(rawValue: securityStr),
            let storedAt = d["storedAt"] as? TimeInterval else { continue }
      let categories = ContentCategory.set(fromWire: d["categories"] as? [String] ?? [])
      let v = Verdict(security: security, categories: categories,
                      title: d["title"] as? String ?? "",
                      summary: d["summary"] as? String ?? "",
                      reasons: d["reasons"] as? [String] ?? [])
      let entry = Entry(verdict: v, storedAt: Date(timeIntervalSince1970: storedAt))
      // A stale entry would only be dropped on its next lookup; skip it now so a
      // reload can't carry more than `maxEntries` worth of dead weight.
      if isExpired(entry) || entries.count >= maxEntries { continue }
      entries[k] = entry
      lru.append(k)
    }
  }
}
