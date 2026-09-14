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
  static let markers: Set<String> = [
    "xxx", "porn", "porno", "pornos", "pornhub", "xvideos", "xnxx", "xhamster",
    "youporn", "redtube", "brazzers", "hentai", "nsfw", "camgirl", "camgirls",
    "chaturbate", "onlyfans", "milf", "milfs", "sextape", "sextapes", "sexcam",
    "sexcams", "sexvideo", "sexvideos", "nudes", "cumshot", "cumshots", "creampie",
    "blowjob", "blowjobs", "deepthroat", "gangbang", "bukkake", "fetish",
  ]

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
    for word in address.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
      if markers.contains(String(word)) { return true }
      // Runs of x are how these addresses spell it: xxx, xxxx, 4k-xxx-hd.
      if word.count >= 3 && word.allSatisfy({ $0 == "x" }) { return true }
    }
    return false
  }
}
