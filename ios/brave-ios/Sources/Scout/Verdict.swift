import Foundation

public enum SecurityStatus: String {
  case safe, suspicious, malicious
}

public struct Verdict: Equatable {
  public let security: SecurityStatus
  public let categories: Set<ContentCategory>
  public let title: String
  public let summary: String
  public let reasons: [String]
  /// Whether the service read the page, or guessed from the address because
  /// the fetch returned nothing.
  ///
  /// It decides how long this is worth keeping. The service keeps a guess for
  /// an hour and a reading for a week, and used to tell us neither — so the
  /// cache kept both for a week, and a site that was unreachable for one
  /// minute got a week-long answer out of it.
  ///
  /// Defaults to true: a verdict from a service too old to say was always
  /// claiming to have read the page.
  public let readPage: Bool
  public var fetchedAt: Date

  public init(security: SecurityStatus, categories: Set<ContentCategory>, title: String,
              summary: String, reasons: [String], readPage: Bool = true,
              fetchedAt: Date = Date()) {
    self.security = security; self.categories = categories; self.title = title
    self.summary = summary; self.reasons = reasons; self.readPage = readPage
    self.fetchedAt = fetchedAt
  }

  public static func parse(_ data: Data) -> Verdict? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    // Required. It used to default to safe while the service did not send it
    // yet; the service sends it on every path now, its schema requires it,
    // and the default meant any other JSON object — an error body answered
    // with a 200, a proxy's page — was cached as a week of "safe". A reply
    // without a status this app can read is a failed check, and the user's
    // fail mode decides what happens next.
    guard let security = (obj["security"] as? String).flatMap(SecurityStatus.init(rawValue:))
    else { return nil }
    let categories = ContentCategory.set(fromWire: obj["categories"] as? [String] ?? [])
    return Verdict(
      security: security,
      categories: categories,
      title: obj["title"] as? String ?? "",
      summary: obj["summary"] as? String ?? "",
      reasons: obj["reasons"] as? [String] ?? [],
      // Absent means a service too old to say, and every verdict claimed to
      // have read the page before this existed. Present and false means the
      // fetch returned nothing and this is a guess from the address, which
      // the cache keeps for an hour rather than a week.
      readPage: obj["readPage"] as? Bool ?? true)
  }
}
