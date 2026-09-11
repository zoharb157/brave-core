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
  public var fetchedAt: Date

  public init(security: SecurityStatus, categories: Set<ContentCategory>, title: String,
              summary: String, reasons: [String], fetchedAt: Date = Date()) {
    self.security = security; self.categories = categories; self.title = title
    self.summary = summary; self.reasons = reasons; self.fetchedAt = fetchedAt
  }

  public static func parse(_ data: Data) -> Verdict? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    // TODO(backend): the live backend does not return a `security` field yet —
    // content categories work today, security is pending backend work. Until
    // it ships, treat an absent/unrecognized `security` as `.safe` so a
    // category-only response still parses as a valid verdict.
    let security = (obj["security"] as? String).flatMap(SecurityStatus.init(rawValue:)) ?? .safe
    let categories = ContentCategory.set(fromWire: obj["categories"] as? [String] ?? [])
    return Verdict(
      security: security,
      categories: categories,
      title: obj["title"] as? String ?? "",
      summary: obj["summary"] as? String ?? "",
      reasons: obj["reasons"] as? [String] ?? [])
  }
}
