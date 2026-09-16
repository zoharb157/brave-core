import Foundation

/// YouTube's Restricted Mode, as a browser can actually set it.
///
/// The documented `YouTube-Restrict` header is for network equipment that
/// rewrites every request on the wire; sent by a client it does nothing —
/// youtube.com answers `SafetyMode: false` with and without it. What the
/// site's own Restricted Mode switch writes is a cookie, and that is sent with
/// every request the page makes, including the SPA's own fetches. So Scout
/// writes the same cookie the switch would.
///
/// This covers YouTube opened as a web page; the YouTube app has its own
/// setting and is out of reach.
public enum RestrictedMode {
  public static let cookieName = "PREF"
  /// `f2` is the flag bank the Restricted Mode switch sets; 0x8000000 is the
  /// bit for it.
  public static let cookieValue = "f2=8000000"
  /// Leading dot: the cookie has to reach m.youtube.com and www.youtube.com
  /// alike, since which one you land on depends on the device.
  public static let cookieDomain = ".youtube.com"

  private static let sites: Set<String> = ["youtube.com", "youtube-nocookie.com", "youtu.be"]

  /// Whether `url` is a site whose Restricted Mode this cookie governs.
  public static func governs(_ url: URL) -> Bool {
    guard let host = url.host else { return false }
    return sites.contains(eTLDPlusOne(host))
  }

  /// Whether `value` (an existing PREF cookie) already has Restricted Mode on.
  ///
  /// PREF carries the viewer's other choices — language, playback, appearance —
  /// so it is amended rather than replaced, and left alone when the flag is
  /// already there.
  public static func isRestricted(_ value: String) -> Bool {
    fields(value)["f2"].map { ($0 ?? 0) & 0x800_0000 != 0 } ?? false
  }

  /// `value` with Restricted Mode turned on, preserving every other field.
  public static func restricting(_ value: String) -> String {
    var seen = false
    var parts = value.split(separator: "&", omittingEmptySubsequences: true).map { part -> String in
      guard part.hasPrefix("f2=") else { return String(part) }
      seen = true
      let current = Int(part.dropFirst(3), radix: 16) ?? 0
      return "f2=" + String(current | 0x800_0000, radix: 16)
    }
    if !seen { parts.append(cookieValue) }
    return parts.joined(separator: "&")
  }

  private static func fields(_ value: String) -> [String: Int?] {
    var out: [String: Int?] = [:]
    for part in value.split(separator: "&") {
      let pair = part.split(separator: "=", maxSplits: 1)
      guard pair.count == 2 else { continue }
      out[String(pair[0])] = Int(pair[1], radix: 16)
    }
    return out
  }
}

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
    // Scout's own default in most regions, and it was missing — so the
    // setting was on, said explicit results never reach the page, and did
    // nothing at all for the engine the majority of users never change away
    // from.
    ({ $0 == "brave.com" }, "safesearch", "strict"),
    ({ $0 == "google.com" || $0.hasPrefix("google.") }, "safe", "active"),
    ({ $0 == "bing.com" }, "adlt", "strict"),
    ({ $0 == "duckduckgo.com" }, "kp", "1"),
    ({ $0 == "yahoo.com" }, "vm", "r"),
    // Yahoo! JAPAN is a separate engine on a separate registrable domain, but
    // it reads the same parameter: its own search settings offer 弱/中/強 as
    // vm=p/i/r, and `r` is the one that excludes adult data from web results
    // rather than images alone. Confirmed against the engine — on an explicit
    // query, vm=r and vm=p share no result host at all, and vm=r returns
    // reference pages (Wikipedia, Merriam-Webster, NCBI) where vm=p returns
    // adult sites. The regional default in Japan, so this closes the gap for
    // everyone there who never changes engine.
    ({ $0 == "yahoo.co.jp" }, "vm", "r"),
    ({ $0 == "qwant.com" }, "safesearch", "2"),
    ({ $0 == "ecosia.org" }, "safesearch", "2"),
    ({ $0.hasPrefix("yandex.") }, "fyandex", "1"),
  ]

  /// Engines Scout ships that no rule here can pin.
  ///
  /// Named rather than left as an absence, so the gap is a thing someone
  /// decided rather than a thing nobody noticed. Each was checked against the
  /// engine itself; none of them turned out to take a filter parameter, and a
  /// parameter that turns out to be wrong is worse than none, because the
  /// setting would then claim a filter that is not there.
  ///
  /// They are not all unfiltered for the same reason, and the difference
  /// matters to anyone deciding what to tell the user:
  ///
  /// - startpage.com genuinely does not filter. Its Safe Search is a stored
  ///   preference (a `disable_family_filter` select of heavy/moderate/none,
  ///   POSTed to /do/settings), and passing that name in the URL changes
  ///   nothing: on an explicit query, `heavy` returns the same ten adult
  ///   results as the default, on both /sp/search and the /do/search endpoint
  ///   Scout ships. Adding the parameter would have been precisely the bug
  ///   this list exists to prevent.
  /// - naver.com and daum.net take no parameter because they already filter.
  ///   Korean law puts them behind real-name age verification, so a
  ///   signed-out user — which is what a child on a shared phone is — is told
  ///   "results unsuitable for minors have been excluded" and gets no adult
  ///   results. The only way past it is a verified account, which Scout
  ///   cannot pin on and cannot pin off.
  ///
  /// So the residual risk on the two Korean engines is narrow: a device
  /// already signed in to an age-verified account. On startpage.com it is not
  /// narrow at all.
  public static let unfiltered: Set<String> = [
    "startpage.com", "naver.com", "daum.net",
  ]

  /// Whether this engine is one nothing here can filter.
  public static func isUnfiltered(_ url: URL) -> Bool {
    guard let host = url.host else { return false }
    return unfiltered.contains(eTLDPlusOne(host))
  }

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
