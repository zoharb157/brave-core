import Foundation

/// Reduces what someone types into the allow or block list to the site it
/// names, or nil if there isn't one in there.
///
/// This is the one place a site rule can be created from free text — every
/// other caller passes a `URL`, whose `host` is already a bare hostname. Text
/// that is not reduced here becomes a rule key that no URL can ever match, and
/// the list then shows the user a site they believe is blocked and is not.
public enum SiteInput {
  public static func site(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return nil }

    // A pasted address is parsed rather than picked apart: `host` drops the
    // scheme, the path, the port and any user:password in front of it. That
    // last one matters — `apple.com@evil.example` is evil.example, and taking
    // the text before the @ would let someone add one site by naming another.
    var candidate = trimmed
    if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
      candidate = host
    } else if let url = URL(string: "http://\(trimmed)"), let host = url.host, !host.isEmpty {
      // No scheme, so it does not parse as a URL on its own. Giving it one
      // costs nothing and gets the same handling for ports and credentials.
      candidate = host
    } else {
      candidate = trimmed.components(separatedBy: "/").first ?? trimmed
    }

    // A site has a dot and nothing stray around it. `localhost` and a bare
    // label are refused rather than stored as rules that describe nothing.
    guard candidate.contains("."), !candidate.hasPrefix("."), !candidate.hasSuffix("."),
      !candidate.contains(" ")
    else { return nil }
    return candidate
  }
}
