import Foundation

/// When a page that changed its own address, without loading, needs checking.
///
/// A navigation is where every check runs, and a page that rewrites its
/// address from script never makes one: WebKit only reports it after the fact,
/// with the new page already on screen. Most sites do this for trivia — a
/// fragment, a filter. The ones where it matters are the ones Scout checks
/// page by page, because anyone can post there: swiping to the next short or
/// opening a subreddit inside the app is a different page with no navigation
/// behind it, and so none of them was ever checked. Only the first page of a
/// visit was.
public enum InPageNavigation {
  /// The cache key to check `url` under, or nil when there is nothing to do:
  /// not a per-page host — the verdict for the site already covers it — or the
  /// same page as the one last checked, which is what a fragment or a
  /// re-written address for the same page looks like.
  public static func keyToCheck(_ url: URL, perPageHosts: Set<String>, lastKey: String?) -> String? {
    guard url.scheme == "http" || url.scheme == "https", let host = url.host?.lowercased() else {
      return nil
    }
    guard VerdictCache.isPerPage(host: host, site: eTLDPlusOne(host), in: perPageHosts) else {
      return nil
    }
    let key = VerdictCache.cacheKey(for: url, perPageHosts: perPageHosts)
    return key == lastKey ? nil : key
  }
}
