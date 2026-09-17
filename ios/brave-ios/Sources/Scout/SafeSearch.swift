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

  /// Sites this cookie can actually reach.
  ///
  /// youtube-nocookie.com is deliberately not here. It is a separate
  /// registrable domain, so a .youtube.com cookie is never sent to it — and
  /// it does not honour the cookie even when one is sent directly: the same
  /// /embed page answers `enableSafetyMode: true` on youtube.com and does not
  /// on youtube-nocookie.com. Claiming it cost a wasted reload on every first
  /// visit and covered nothing.
  ///
  /// youtu.be is here and works, but by redirect rather than directly: it
  /// answers 302 to www.youtube.com/watch, and the cookie applies there.
  private static let sites: Set<String> = ["youtube.com", "youtu.be"]

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
    // It was missing, so the setting was on, said explicit results never
    // reach the page, and did nothing at all for Brave Search. It was the
    // default in most regions when that was found; it is still offered in
    // every region, and nobody who picks it should get less than the rest.
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
    // Qwant parses `safesearch=2` — it even copies it into its own links —
    // and then filters nothing: explicit results come back unchanged. What its
    // own Strict switch writes is `s=2`, and with that the settings drawer
    // reads Strict and the adult results are gone.
    ({ $0 == "qwant.com" }, "s", "2"),
  ]

  /// What Scout can honestly promise about an engine.
  ///
  /// The setting says explicit results never reach the page. For most engines
  /// a rule above makes that true. For the rest it does not, and the two
  /// reasons it does not are different enough that a screen telling the user
  /// about it should not merge them.
  public enum Coverage: Equatable {
    /// A rule above pins the engine's own filter on.
    case pinned
    /// No rule, and none needed: the engine already excludes adult results
    /// from a signed-out user by itself.
    case filteredByEngine
    /// No rule, and no filter of the engine's own. Explicit results arrive.
    case unfiltered
  }

  /// Engines that take no parameter because they already filter.
  ///
  /// Korean law puts naver.com and daum.net behind real-name age
  /// verification, so a signed-out user — which is what a child on a shared
  /// phone is — is told "results unsuitable for minors have been excluded"
  /// and gets none. The only way past it is a verified account, which Scout
  /// can pin neither on nor off. So the residual risk here is narrow: a
  /// device already signed in to one.
  public static let filteredByEngine: Set<String> = ["naver.com", "daum.net"]

  /// Engines Scout ships that nothing filters.
  ///
  /// Named rather than left as an absence, so the gap is a thing someone
  /// decided rather than a thing nobody noticed. A parameter that turns out
  /// to be wrong is worse than none, because the setting would then claim a
  /// filter that is not there — so nothing goes in the rules table above
  /// until it has been checked against the engine itself.
  ///
  /// startpage.com is the one that was checked and failed. Its Safe Search is
  /// a stored preference — a `disable_family_filter` select of
  /// heavy/moderate/none, POSTed to /do/settings — and passing that name in
  /// the URL changes nothing: on an explicit query, `heavy` returns the same
  /// ten adult results as the default, on both /sp/search and the /do/search
  /// endpoint Scout ships. It is exactly the plausible-looking parameter
  /// someone would add from reading the settings page, and adding it would
  /// have been precisely the bug this list exists to prevent.
  ///
  /// ecosia.org is the same shape. Its filter is the `f` field of its ECFG
  /// cookie (y/i/n); with that set to off, neither `safesearch=2` — which was
  /// shipped here — nor `adultFilter=y` removes a single adult result. A fresh
  /// visitor gets Moderate by default, but anyone can switch it off in two
  /// taps, and no URL Scout rewrites would stop that.
  ///
  /// Yandex is the one where the rule that used to be here was worse than
  /// nothing. `fyandex=1` makes Yandex answer "nothing found" to ordinary
  /// queries — "kittens" included, on yandex.ru and yandex.com alike — while
  /// an explicit query keeps its adult results. That is not a stray
  /// parameter misfiring: Yandex's own Family mode, saved through its
  /// settings page, behaves identically, so this appears to be the URL form
  /// of a mode that, as tested from outside Yandex's home regions, empties
  /// ordinary searches and filters nothing. It may behave in the ten regions
  /// where Yandex is Scout's default; that cannot be checked from here, and a
  /// filter nobody has seen work is not one to claim. The rule never did harm
  /// only because Yandex carries the query as `text=`, which the results-page
  /// check below never looked for, so it never fired.
  public static let unfiltered: Set<String> = [
    "startpage.com", "ecosia.org", "yandex.ru", "yandex.com",
  ]

  /// What Scout can promise about the engine serving this address.
  ///
  /// Anything unrecognised counts as unfiltered. A custom engine someone
  /// added may well filter itself, but Scout cannot pin it and has no way to
  /// find out, and claiming cover it does not have is the failure this whole
  /// type exists to avoid.
  public static func coverage(of url: URL) -> Coverage {
    guard let host = url.host else { return .unfiltered }
    return coverage(ofSite: eTLDPlusOne(host))
  }

  /// The parameters the engines in `unfiltered` carry a search in: Startpage
  /// uses `query` (and `q` on older paths), Ecosia `q`, Yandex `text`.
  private static let unfilteredQueryNames: Set<String> = ["q", "query", "text"]

  /// Whether `url` is a page of results from an engine Scout cannot filter.
  ///
  /// Search filtering promises that explicit results never reach the page, and
  /// for these engines nothing Scout can do to the address keeps it — so on a
  /// supervised phone their results are not shown at all. Choosing one as the
  /// default engine, or typing its address, used to be a way round the filter
  /// that needed no PIN.
  ///
  /// - Parameter customEngines: for each engine the user added, its
  ///   registrable domain and the parameter its search template puts the query
  ///   in. An added engine can be any site, so only that parameter counts.
  public static func isUnfilteredResults(_ url: URL, customEngines: [String: String] = [:]) -> Bool {
    guard let host = url.host else { return false }
    let site = eTLDPlusOne(host)
    let names: Set<String>
    if unfiltered.contains(site) {
      names = unfilteredQueryNames
    } else if let name = customEngines[site], coverage(ofSite: site) == .unfiltered {
      names = [name]
    } else {
      return false
    }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return items.contains {
      names.contains($0.name)
        && !($0.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  /// As `coverage(of:)`, for a registrable domain already in hand.
  public static func coverage(ofSite site: String) -> Coverage {
    if rules.contains(where: { $0.matches(site) }) { return .pinned }
    if filteredByEngine.contains(site) { return .filteredByEngine }
    return .unfiltered
  }

  /// DuckDuckGo's no-JavaScript pages ignore its filter entirely.
  ///
  /// html.duckduckgo.com and lite.duckduckgo.com return the same adult results
  /// with `kp=1` as without it — over GET or POST, and with the settings
  /// cookie set — while duckduckgo.com itself honours `kp=1` and says "Safe
  /// search: strict". The rule below matched them anyway, being the same
  /// registrable domain, so a child typing either address got unfiltered
  /// results with the setting on. The search is kept and moved to the page
  /// that filters it.
  ///
  /// Every visit is moved, not just ones carrying a query: these pages' own
  /// search box submits by POST, so the query never appears in the address a
  /// navigation policy sees. Moving the home page too means the unfiltered
  /// form is never reached in the first place.
  private static let unfilterableDuckDuckGoHosts: Set<String> = [
    "html.duckduckgo.com", "lite.duckduckgo.com",
  ]

  private static func movedToFilteringEndpoint(_ url: URL, host: String) -> URL? {
    guard unfilterableDuckDuckGoHosts.contains(host.lowercased()) else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "duckduckgo.com"
    components.path = "/"
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "q" })?.value
    if let query, !query.isEmpty {
      components.queryItems = [
        URLQueryItem(name: "q", value: query), URLQueryItem(name: "kp", value: "1"),
      ]
    }
    return components.url
  }

  /// The same URL with the engine's filter pinned on, or nil when nothing needs
  /// changing — not a search engine, or already filtered.
  public static func enforced(_ url: URL) -> URL? {
    guard let host = url.host else { return nil }
    if let moved = movedToFilteringEndpoint(url, host: host) { return moved }
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
