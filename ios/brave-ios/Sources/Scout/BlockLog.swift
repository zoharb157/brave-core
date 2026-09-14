import Foundation

/// One blocked navigation, as it should read back to a person.
public struct BlockRecord: Equatable, Identifiable, Sendable {
  /// Site and time together: two entries share a site only when they are
  /// minutes apart (`coalesce`), and two sites blocked in the same instant are
  /// still told apart by name. A list keyed on the date alone would collide if
  /// they ever weren't.
  public var id: String { "\(site)@\(date.timeIntervalSince1970)" }

  /// The site, as the registrable domain — the same key rules and verdicts use.
  public let site: String
  public let reason: DecisionReason
  public let categories: Set<ContentCategory>
  public let date: Date
  /// Whether the user went through anyway. Set after the fact, so the log
  /// distinguishes "Scout stopped this" from "Scout stopped this and they
  /// went on" — which is the entry a parent actually wants to see.
  public var continued: Bool

  public init(site: String, reason: DecisionReason, categories: Set<ContentCategory>,
              date: Date, continued: Bool = false) {
    self.site = site; self.reason = reason; self.categories = categories
    self.date = date; self.continued = continued
  }
}

/// What Scout has blocked recently, newest first.
///
/// A filter nobody can audit asks to be trusted on nothing. This is the
/// evidence: which sites were stopped, why, and whether they were opened
/// anyway. Capped and local — it is a short recent history, not a browsing
/// record, and nothing here leaves the device.
public final class BlockLog {
  public static let defaultLimit = 100

  private let limit: Int
  private let now: () -> Date
  private var records: [BlockRecord] = []
  public var onChange: (() -> Void)?

  public init(limit: Int = defaultLimit, now: @escaping () -> Date = Date.init) {
    self.limit = limit
    self.now = now
  }

  public var entries: [BlockRecord] { records }
  public var isEmpty: Bool { records.isEmpty }
  public var count: Int { records.count }

  /// Records a block. Repeating the same site and reason within `coalesce`
  /// updates the existing entry instead of adding another — a blocked page
  /// that reloads itself would otherwise bury everything else.
  public func record(site: String, reason: DecisionReason,
                     categories: Set<ContentCategory> = [],
                     coalesce: TimeInterval = 5 * 60) {
    let key = eTLDPlusOne(site)
    guard !key.isEmpty else { return }
    let at = now()
    if let first = records.first, first.site == key, first.reason == reason,
      at.timeIntervalSince(first.date) < coalesce
    {
      records[0] = BlockRecord(site: key, reason: reason, categories: categories, date: at,
                               continued: first.continued)
      onChange?()
      return
    }
    records.insert(
      BlockRecord(site: key, reason: reason, categories: categories, date: at), at: 0)
    if records.count > limit { records.removeLast(records.count - limit) }
    onChange?()
  }

  /// Marks the newest entry for `site` as one the user went through.
  public func noteContinued(site: String) {
    let key = eTLDPlusOne(site)
    guard let index = records.firstIndex(where: { $0.site == key }) else { return }
    guard !records[index].continued else { return }
    records[index].continued = true
    onChange?()
  }

  public func removeAll() {
    guard !records.isEmpty else { return }
    records.removeAll()
    onChange?()
  }

  // MARK: - Persistence

  public func serialize() -> [[String: Any]] {
    records.map {
      [
        "site": $0.site,
        "reason": $0.reason.wire,
        "categories": ContentCategory.wire($0.categories),
        "date": $0.date.timeIntervalSince1970,
        "continued": $0.continued,
      ]
    }
  }

  public func load(_ wire: [[String: Any]]) {
    records = wire.compactMap { item in
      guard let site = item["site"] as? String,
        let reason = (item["reason"] as? String).flatMap(DecisionReason.init(wire:)),
        let seconds = item["date"] as? TimeInterval
      else { return nil }
      return BlockRecord(
        site: site,
        reason: reason,
        categories: ContentCategory.set(fromWire: item["categories"] as? [String] ?? []),
        date: Date(timeIntervalSince1970: seconds),
        continued: item["continued"] as? Bool ?? false)
    }
    if records.count > limit { records.removeLast(records.count - limit) }
  }
}

extension DecisionReason {
  /// A stable string for storage. The enum's own case names would do, but
  /// they'd then be a storage format that renaming a case silently breaks.
  public var wire: String {
    switch self {
    case .policyList: return "policy-list"
    case .scheme: return "scheme"
    case .security: return "security"
    case .category: return "category"
    case .unavailable: return "unavailable"
    }
  }

  public init?(wire: String) {
    switch wire {
    case "policy-list": self = .policyList
    case "scheme": self = .scheme
    case "security": self = .security
    case "category": self = .category
    case "unavailable": self = .unavailable
    default: return nil
    }
  }
}
