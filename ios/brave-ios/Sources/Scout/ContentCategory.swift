import Foundation

/// A content category the user can choose to block. Distinct from security
/// (phishing/malware/scam) — there is no parent here, so blocking a category
/// is always the user's own preference, never enforced on someone else.
public enum ContentCategory: String, CaseIterable, Hashable {
  case adult, gambling, ads

  /// Parses a single wire string from the backend's `categories: [String]`
  /// array, case-insensitively, accepting known synonyms. Unknown strings
  /// yield `nil` rather than being coerced into a category.
  public init?(wireString: String) {
    switch wireString.lowercased() {
    case "adult", "porn", "pornography", "explicit": self = .adult
    case "gambling", "betting", "casino": self = .gambling
    case "ads", "advertising", "trackers", "tracking": self = .ads
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
