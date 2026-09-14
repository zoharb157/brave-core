import Foundation

/// Forces search engines into their filtered mode.
///
/// The guard checks the pages someone opens, but a search results page is a
/// wall of links and thumbnails that is itself the content: unfiltered results
/// show explicit material before anything is clicked. Every major engine takes
/// a query parameter that pins its own filter on, and they honour it for
/// signed-out users, which is what a child on a shared phone is.
///
/// Tied to the adult-content category: if someone chose to block that, their
/// searches are filtered too.
public enum SafeSearch {
  /// The parameter each engine reads, and the value that means "filter".
  private static let rules: [(matches: (String) -> Bool, name: String, value: String)] = [
    ({ $0 == "google.com" || $0.hasPrefix("google.") }, "safe", "active"),
    ({ $0 == "bing.com" }, "adlt", "strict"),
    ({ $0 == "duckduckgo.com" }, "kp", "1"),
    ({ $0 == "yahoo.com" }, "vm", "r"),
    ({ $0 == "qwant.com" }, "safesearch", "2"),
    ({ $0 == "ecosia.org" }, "sfs", "true"),
  ]

  /// The same URL with the engine's filter pinned on, or nil when nothing needs
  /// changing — not a search engine, or already filtered.
  public static func enforced(_ url: URL) -> URL? {
    guard let host = url.host else { return nil }
    let site = eTLDPlusOne(host)
    guard let rule = rules.first(where: { $0.matches(site) }) else { return nil }
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    // Only search result pages: the home page has nothing to filter, and
    // rewriting it would bounce the user through a reload for nothing.
    var items = components.queryItems ?? []
    guard items.contains(where: { $0.name == "q" || $0.name == "p" }) else { return nil }
    if items.contains(where: { $0.name == rule.name && $0.value == rule.value }) { return nil }

    items.removeAll { $0.name == rule.name }
    items.append(URLQueryItem(name: rule.name, value: rule.value))
    components.queryItems = items
    return components.url
  }
}
