import Foundation

/// Reads the address itself for unambiguous adult markers.
///
/// Every other check in Scout asks about a *site*, and a verdict earned by one
/// page is reused for the rest of the domain — which is what keeps browsing
/// fast, and what let injected spam on a hacked but legitimate domain inherit
/// that domain's clean verdict. A page fetch doesn't help either: the real
/// homepage is real, and the injected page can serve a crawler something else.
///
/// The address is the one signal that is per-page by nature, costs no network
/// call, and cannot be cached away. It catches nothing subtle — that is what
/// the content check is for — but `/xxx-sex-videos` on a food company's domain
/// needs no analysis to recognise.
public enum ExplicitURL {
  /// Markers with no common innocent reading. Deliberately short: a false
  /// positive here blocks a page someone may genuinely need — sexual health,
  /// an anatomy article, a news story — and this product's whole premise is
  /// that the user can still continue, not that guessing is free.
  ///
  /// Bare "sex", "nude", "adult" and "breast" are all excluded for that
  /// reason. Judging those is the content check's job, with the page in hand.
  /// "fetish" and "nsfw" were removed for the same reason: a dictionary
  /// defining the first and a news piece explaining the second were both being
  /// blocked outright. "xxx" is not here either — runs of x are judged by
  /// `hasRunOfX`, which reads a host differently from a path.
  static let markers: Set<String> = [
    "porn", "porno", "pornos", "pornhub", "xvideos", "xnxx", "xhamster",
    "youporn", "redtube", "brazzers", "hentai", "camgirl", "camgirls",
    "chaturbate", "onlyfans", "milf", "milfs", "sextape", "sextapes", "sexcam",
    "sexcams", "sexvideo", "sexvideos", "nudes", "cumshot", "cumshots", "creampie",
    "blowjob", "blowjobs", "deepthroat", "gangbang", "bukkake",
  ]

  /// Words that mean little alone but settle what a run of x is doing beside
  /// them. "xxx" next to any of these is not a number.
  ///
  /// Mirrors `X_COMPANIONS` in `packages/cross/utils/url.ts`.
  static let xCompanions: Set<String> = [
    "sex", "sexo", "sexe", "video", "videos", "vids", "tube", "cam", "cams",
    "webcam", "webcams", "anal", "teen", "teens", "hardcore", "nude", "escort",
    "escorts", "fuck", "fucking", "hentai", "adult", "hd", "4k",
  ]

  /// Whether a page's own title names explicit content.
  ///
  /// The last line of defence, and the only one that sees what actually
  /// rendered. A verdict describes a site; an injected page on a hacked domain
  /// inherits it, and the address only gives it away when the address happens
  /// to say so. The title is written by the page itself, for the person
  /// reading it — an injected spam page announces exactly what it is, because
  /// that is the whole point of it.
  ///
  /// Same markers as the address, and the same restraint: a page about
  /// legislation or health that merely mentions these words is a page someone
  /// may need, and blocking it is recoverable but not free.
  public static func looksExplicit(title: String) -> Bool {
    let words = tokens(title.lowercased())
    if words.contains(where: { markers.contains($0) }) { return true }
    // A title has no host and no segments, so a run of x counts only when a
    // word beside it says what it means — "Super Bowl XXX" is a title too.
    return words.contains(where: isRunOfX) && words.contains(where: { xCompanions.contains($0) })
  }

  /// Whether `url`'s address carries an adult marker.
  ///
  /// Matching is on whole words, split at anything that isn't a letter or
  /// digit, so a marker buried inside an ordinary word never fires: the point
  /// is to catch `/xxx-sex-videos`, not to rediscover why "Scunthorpe" is a
  /// famous problem.
  public static func looksExplicit(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    // The host and the path are read together: the marker can be in either
    // (`porn.example.com` or `example.com/porn`).
    let address = host + " " + url.path.lowercased() + " " + (url.query?.lowercased() ?? "")
    let words = tokens(address)
    if words.contains(where: { markers.contains($0) }) { return true }
    return hasRunOfX(host: host, path: url.path.lowercased(), words: words)
  }

  private static func tokens(_ text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }

  private static func isRunOfX(_ word: String) -> Bool {
    word.count >= 3 && word.allSatisfy { $0 == "x" }
  }

  /// Whether a run of x here is the way those sites spell it.
  ///
  /// In a host name it always is — nobody numbers a domain. In a path it is
  /// far more often thirty: Super Bowl XXX and Olympiad XXX were both being
  /// blocked outright as pornography. So in a path it counts only when the
  /// segment is nothing but the run, or a word beside it says what it means.
  ///
  /// The path cannot simply be ignored: this check runs so that an injected
  /// page on a hacked but otherwise clean domain does not inherit that
  /// domain's clean verdict, and such a page is a path, never a host.
  private static func hasRunOfX(host: String, path: String, words: [String]) -> Bool {
    if host.split(separator: ".").contains(where: { isRunOfX(String($0)) }) { return true }
    guard words.contains(where: isRunOfX) else { return false }
    if words.contains(where: { xCompanions.contains($0) }) { return true }
    return path.split(separator: "/").contains { isRunOfX(String($0)) }
  }
}
