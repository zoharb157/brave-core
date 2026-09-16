import Foundation

/// A content category the user can choose to block. Distinct from security
/// (phishing/malware/scam) — there is no parent here, so blocking a category
/// is always the user's own preference, never enforced on someone else.
///
/// There was an `ads` case. It was removed because nothing could decide it:
/// measured against the rating model, the label landed on 43% of the most
/// popular sites on the internet — amazon.com, apple.com, microsoft.com — and
/// no prompt wording moved it. A setting that blocks the ordinary internet for
/// the person who switches it on is worse than no setting. Ads and trackers
/// are blocked by Shields, from real filter lists, at the network layer.
///
/// A stored preference naming it is dropped on read, like any unknown string.
public enum ContentCategory: String, CaseIterable, Hashable, Sendable {
  case adult, gambling

  /// Parses a single wire string from the backend's `categories: [String]`
  /// array, case-insensitively, accepting known synonyms. Unknown strings
  /// yield `nil` rather than being coerced into a category.
  public init?(wireString: String) {
    switch wireString.lowercased() {
    case "adult", "porn", "pornography", "explicit": self = .adult
    case "gambling", "betting", "casino": self = .gambling
    default: return nil
    }
  }

  /// Parses a `categories: [String]` array, silently dropping unknown
  /// strings rather than failing the whole parse.
  public static func set(fromWire strings: [String]) -> Set<ContentCategory> {
    Set(strings.compactMap(ContentCategory.init(wireString:)))
  }

  /// The canonical names to persist a set under; `set(fromWire:)` reads them back.
  public static func wire(_ categories: Set<ContentCategory>) -> [String] {
    categories.map(\.rawValue).sorted()
  }
}
