import Foundation

public enum FailMode: String { case open, closed }
public enum SchemeRule: String { case allow, block }

public struct Policy {
  public var blockedCategories: Set<ContentCategory>
  public var allow: [String]
  public var block: [String]
  public var schemes: [String: SchemeRule]
  public var failMode: FailMode

  public init(blockedCategories: Set<ContentCategory>, allow: [String], block: [String],
              schemes: [String: SchemeRule], failMode: FailMode) {
    self.blockedCategories = blockedCategories; self.allow = allow; self.block = block
    self.schemes = schemes; self.failMode = failMode
  }

  public static func makeDefault() -> Policy {
    Policy(blockedCategories: [.adult, .gambling],
           allow: [],
           block: [],
           schemes: ["data": .block, "file": .block],
           failMode: .open)
  }

  public static func parse(_ data: Data) -> Policy? {
    guard let obj = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] else { return nil }
    var p = makeDefault()
    if let categories = obj["blockedCategories"] as? [String] {
      p.blockedCategories = ContentCategory.set(fromWire: categories)
    }
    if let allow = obj["allow"] as? [String] { p.allow = allow }
    if let block = obj["block"] as? [String] { p.block = block }
    if let schemes = obj["schemes"] as? [String: String] {
      p.schemes = schemes.compactMapValues { SchemeRule(rawValue: $0) }
    }
    if let fm = obj["failMode"] as? String, let parsed = FailMode(rawValue: fm) {
      p.failMode = parsed
    } else {
      p.failMode = .open
    }
    return p
  }
}
