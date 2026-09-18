// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShared
import Foundation
import Onboarding
import Preferences
import Scout
import Shared
import UIKit
import WebKit

/// Owns the guard's collaborators for the app.
///
/// One policy store and one verdict cache are shared across tabs, so a site
/// checked in one tab is instant in the next. The policy store is injected into
/// the guard as `PolicyProviding`, which is what lets a server-synced provider
/// replace it later without touching the guard.
@MainActor
public final class ScoutServices {
  public static let shared = ScoutServices()

  /// The same backend the Kid Safe app uses. It returns content categories and
  /// a `security` status; `Verdict.parse` still defaults a missing `security`
  /// to `.safe` so an older server cannot make the guard block everything.
  private static let checkEndpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/check")!

  /// Measured checks run 1.5–3.1 seconds, so this leaves about a second of
  /// headroom over the slowest seen.
  ///
  /// An earlier note here proposed 400 ms on the assumption that a precheck
  /// would have warmed the cache first, and observed that precheck did not
  /// exist — so every unknown host timed out and failed open, and the guard
  /// never blocked on a live verdict. Precheck exists now and does take the
  /// wait off a link the user is about to open. The warm list does not yet:
  /// a site only reaches it once fifty distinct installs have opened it, and
  /// in production the published list is still empty, so it takes nothing off
  /// this path today and will not until the install base is large enough.
  /// Until then this timeout applies exactly as often as it ever did — on
  /// every first visit to an unknown site. When it fires, the check falls to
  /// the user's own fail-mode setting rather than being waited out.
  private static let checkTimeout: TimeInterval = 4.0

  /// Sites where the pages are written by whoever signs up, so one page's
  /// verdict says nothing about the next: a video, a subreddit, an
  /// encyclopedia article or a free hosting subdomain is checked as a page,
  /// not as a site. Everywhere else a verdict covers the whole domain, which
  /// is what keeps browsing fast.
  ///
  /// Mirrors `PER_PAGE_HOSTS` in `packages/cross/utils/url.ts`. The two lists
  /// key the same URL the same way or the phone and the server disagree about
  /// what a site is — they had already drifted once, the phone missing every
  /// shortener, so that `bit.ly/A` lent its verdict to `bit.ly/B` on device
  /// while the server kept them apart.
  nonisolated static let perPageHosts: Set<String> = [
    // Social and user-posted content
    "reddit.com", "x.com", "twitter.com", "tumblr.com", "facebook.com", "instagram.com",
    "tiktok.com", "snapchat.com", "vk.com", "pinterest.com", "quora.com", "discord.com",
    "twitch.tv", "4chan.org", "deviantart.com", "imgur.com",
    // Video and story platforms
    "youtube.com", "youtu.be", "dailymotion.com", "vimeo.com", "wattpad.com",
    "archiveofourown.org", "fanfiction.net",
    // Publishing and free hosting: anyone can put a page under these
    "medium.com", "substack.com", "blogspot.com", "wordpress.com", "wixsite.com",
    "weebly.com", "github.io", "pages.dev", "netlify.app", "vercel.app", "glitch.me",
    "sites.google.com", "notion.site", "blogger.com", "tilda.ws", "webflow.io",
    // Reference and archives written by the public. An encyclopedia is the
    // clearest case there is of one page not speaking for the next: the first
    // article anyone checked would otherwise answer for every other one.
    "wikipedia.org", "wikimedia.org", "wiktionary.org", "wikia.com", "fandom.com",
    "archive.org", "scribd.com", "slideshare.net", "academia.edu",
    // Documents and files someone else uploaded, served under a name the
    // uploader did not have to earn.
    "docs.google.com", "drive.google.com", "dropbox.com", "onedrive.live.com",
    "pastebin.com", "ghostbin.com", "gist.github.com", "box.com", "mega.nz",
    "icloud.com", "sharepoint.com", "wetransfer.com",
    // Link shorteners and link-in-bio pages. The most important entries here:
    // the whole point of one is that the address says nothing about where it
    // goes, so a verdict for bit.ly/A describes a page that has nothing to do
    // with bit.ly/B. Keyed by domain, the first short link anyone opened would
    // decide every short link for everyone.
    "bit.ly", "bitly.com", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "buff.ly",
    "is.gd", "cutt.ly", "rb.gy", "shorturl.at", "rebrand.ly", "lnkd.in", "amzn.to",
    "fb.me", "wa.me", "tiny.cc", "v.gd", "trib.al", "dlvr.it", "ift.tt", "t.ly",
    "short.gy", "shrtco.de", "s.id", "po.st", "adf.ly", "clck.ru", "vk.cc", "u.to",
    "lc.cx", "kutt.it", "urlz.fr", "snip.ly", "smarturl.it", "lnk.to", "ffm.to",
    "hyperurl.co", "linktr.ee", "lin.ee", "msha.ke", "beacons.ai", "carrd.co",
    "apple.co", "spoti.fi", "nyti.ms", "wapo.st", "reut.rs", "bbc.in", "cnn.it",
    "huff.to", "econ.st", "mzl.la", "red.ht",
  ]

  /// Lists, scheme rules and fail mode (server-synced later).
  public let policy: PolicyStore
  /// What the guard decides with: `policy`, but with blocked categories read
  /// live from the user's choice (onboarding / Settings → Blocked Content),
  /// and with the user's own per-site rules ahead of both.
  public let decisionPolicy: PolicyProviding
  /// Sites the user allowed or blocked by hand. Consulted before the category
  /// settings and before the network check, so "always allow" takes effect on
  /// the very next navigation.
  public let siteRules: SiteRules
  /// What Scout has blocked recently, for Settings → Protection.
  public let blockLog: BlockLog
  private let cache: VerdictCache
  /// Sites first seen in a private tab. Their verdicts are held in memory so a
  /// private session doesn't re-check the same page over and over, and are
  /// dropped the moment that session ends — see `forgetPrivateVerdicts()`.
  private var privateOnlyKeys: Set<String> = []
  /// Moves on each time the private keys are dropped, so a private check that
  /// lands afterwards can tell its session is over.
  private var privateSession = 0
  private let checker: SafetyChecker
  public let guard_: NavigationGuard

  private init() {
    var base = Policy.makeDefault()
    base.allow = ScoutContact.ownHosts
    policy = PolicyStore(policy: base)
    siteRules = ScoutProtectionStore.loadSiteRules()
    blockLog = ScoutProtectionStore.loadBlockLog()
    let categoryPolicy = UserCategoryPolicy(
      base: policy, blockedCategories: { Preferences.ScoutBlocking.chosen },
      // Read live, like the categories, so changing it in Settings applies to
      // the very next navigation rather than the next launch.
      //
      // A supervised phone always asks. It is already sitting on a checking
      // screen, and a check that could not finish is not a verdict — opening
      // the page anyway would be the one thing supervision promises not to do.
      // Failing open is a choice for someone deciding for themselves, which is
      // exactly who a supervised phone is not.
      //
      // The preference is read directly rather than through
      // `ScoutSupervision.shared`, which is MainActor-isolated: this closure is
      // called from `decide`, which is nonisolated and runs off the main actor.
      failMode: {
        if Preferences.Scout.supervised.value { return .closed }
        return Preferences.Scout.askWhenCheckFails.value ? .closed : .open
      })
    // The user's own per-site decision is the outermost layer: it is the one
    // input that is an explicit human answer about this exact site, so it wins
    // over both the category settings and the check.
    let rules = siteRules
    decisionPolicy = UserSitePolicy(base: categoryPolicy, rules: { rules })
    cache = VerdictCache(maxEntries: 2000, now: { Date() }, perPageHosts: Self.perPageHosts)
    checker = CoalescingSafetyChecker(
      // The install's own random id, already what the activity log is filed
      // under, so the service can ration checks per phone instead of per
      // network — every phone on a school's Wi-Fi used to share one allowance.
      transport: NetworkSafetyTransport(
        endpoint: Self.checkEndpoint, deviceID: ScoutActivityReporter.installId),
      // Same key the cache uses, so two pages that are cached apart are also
      // checked apart rather than sharing one in-flight request.
      key: { VerdictCache.cacheKey(for: $0, perPageHosts: ScoutServices.perPageHosts) })
    guard_ = NavigationGuard(
      policy: decisionPolicy, cache: cache, checker: checker, timeout: Self.checkTimeout,
      // With no network the check can only time out, and the page is about to
      // fail to load anyway — don't spend the timeout on a checking screen.
      isReachable: { Reachability.shared.status.connectionType != .offline },
      // Verdicts for the sites people open most, shipped as a file and
      // refreshed at most once a day. Consulted after the cache and before
      // the network check, so a verdict this phone fetched for itself always
      // wins. The store itself is passed, not a snapshot of what it held at
      // construction — a list downloaded mid-session replaces what the store
      // holds, and the guard sees that update on its very next lookup rather
      // than only after the next cold start.
      warmList: ScoutWarmListStore.shared,
      // Hosts publicly known to be phishing or serving malware, downloaded at
      // most once a day. Read before both the cache and the warm list: those
      // two only ever say a site looked fine when it was last looked at, and
      // neither can hear that it has since been compromised or sold. Like the
      // warm list, the store itself is passed rather than a snapshot, so a
      // download that lands mid-session is used on the very next navigation.
      threatList: ScoutThreatListStore.shared)

    load()
    observeLifecycle()
  }

  // MARK: - What a site is

  /// Hands the package the browser's own Public Suffix List.
  ///
  /// Everything Scout keys by site — verdicts, site rules, the warm list,
  /// checks in flight — asks the package what a host's registrable domain is,
  /// and on its own the package knows only a short hand-made list of suffixes.
  /// Any suffix missing from it merged whole countries' sites: adult.co.id and
  /// tokopedia.co.id were both "co.id". Chromium's list is already in the app.
  ///
  /// Called once at launch, before anything is keyed by site. ICANN suffixes
  /// only: the private ones (github.io, pages.dev) are already handled page
  /// by page through `perPageHosts`, which names them as sites, and counting
  /// each subdomain as a site of its own would change what a standing rule
  /// covers — a separate decision from this one.
  public static func useBrowserSuffixList() {
    RegistrableDomain.resolver = { host in
      let domain = NSURL.domainAndRegistryExcludingPrivateRegistries(host: host)
      return domain.isEmpty ? nil : domain
    }
  }

  // MARK: - Keeping verdicts between launches

  /// Checking an unknown site takes seconds, so a cache that died with the app
  /// meant every site paid that price again on the next launch. Verdicts are
  /// re-derivable, so they live in Caches; they expire on their own (7 days
  /// safe, 24 hours otherwise) and are dropped when the user clears history.
  private static var storeURL: URL? {
    try? FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("scout-verdicts.json")
  }

  private func load() {
    guard let url = Self.storeURL, let data = try? Data(contentsOf: url) else { return }
    cache.deserialize(data)
  }

  public func save() {
    guard let url = Self.storeURL else { return }
    try? cache.serialize(excludingKeys: privateOnlyKeys).write(to: url, options: .atomic)
  }

  /// Everything Scout knows about one site, for the panel behind the URL bar.
  public struct SiteStatus {
    /// The registrable domain the status is about — what a rule would key on.
    public let site: String
    /// The user's own standing decision, if they made one.
    public let rule: SiteRule?
    /// The check's answer, if Scout has one on hand.
    public let verdict: Verdict?
    /// When that answer was fetched.
    public let checkedAt: Date?
    /// Categories on this site that the user currently blocks. Recomputed
    /// from the live settings rather than stored, so turning a category off
    /// is reflected without re-checking anything.
    public let blockedCategories: Set<ContentCategory>
  }

  public func status(for url: URL) -> SiteStatus {
    // The list of already-checked sites answers navigations when this phone
    // has no verdict of its own, so it answers here too. Without it a site
    // opened straight from the list read "Not checked yet" beside the plain
    // logo, while it had been checked and let through on that answer.
    let cached = cache.get(url)
    let verdict = cached ?? ScoutWarmListStore.shared.verdict(for: url)
    return SiteStatus(
      site: eTLDPlusOne(url.host ?? ""),
      rule: siteRules.rule(for: url),
      verdict: verdict,
      checkedAt: cached == nil ? verdict?.fetchedAt : cache.storedAt(url),
      blockedCategories: verdict?.categories.intersection(decisionPolicy.blockedCategories) ?? [])
  }

  /// Clears what a page wrote before its verdict arrived, at the granularity
  /// the verdict was made at.
  ///
  /// Used when a page was shown before its verdict arrived and the verdict
  /// turned out to be bad. Swapping the view does not undo what the page
  /// already ran: by the time an answer lands it has executed its scripts,
  /// written its cookies and filled its local storage. Deleting those is what
  /// makes "taken back" mean something rather than being a change of picture.
  ///
  /// - Parameter dataStore: the store the page actually loaded in, captured
  ///   before the check started rather than read off the tab when the verdict
  ///   lands. It is deliberately non-optional and there is no
  ///   `WKWebsiteDataStore.default()` fallback: a private tab has its own
  ///   store, that store dies with the tab, and falling back when it is gone
  ///   would delete the user's *regular-mode* cookies, storage and saved
  ///   credentials for a domain they only ever opened privately — silently
  ///   logging them out of a session no verdict was about, while the private
  ///   data it meant to delete had already gone with the store. No store, no
  ///   shred; deleting from the wrong store is worse than deleting nothing.
  ///
  /// ## Granularity
  ///
  /// A verdict keyed to a whole domain may shred that domain's records. A
  /// verdict keyed to one page may not. `VerdictCache.cacheKey` is what draws
  /// that line — a domain key is a bare eTLD+1, a page key carries a path, so
  /// the presence of a `/` is the same test the cache itself used — rather
  /// than re-deriving the `perPageHosts` rule here and letting the two drift.
  ///
  /// - **Domain key** → `deleteDataRecords(forDomains:)`, the Shred Site Data
  ///   menu action's own code path. It compares whole registrable domains
  ///   against `WKWebsiteDataRecord.displayName`, so `evilexample.com` cannot
  ///   be caught by `example.com`.
  /// - **Page key** → only cookies whose domain is exactly this host. A
  ///   `WKWebsiteDataRecord` is named by registrable domain and aggregates
  ///   every subdomain under it, so deleting the record for a page verdict
  ///   would take origins nothing judged: blocking one
  ///   `docs.google.com/document/d/…` would delete Gmail, Drive and Search;
  ///   `gist.github.com` would take GitHub; `onedrive.live.com`,
  ///   `sites.google.com`, `icloud.com` and `sharepoint.com` the same shape.
  ///   `perPageHosts` exists precisely so one page can be blocked on a host
  ///   the user otherwise trusts, so the aggregated record is left alone.
  ///
  /// The domain name used is `url.baseDomain` — Chromium's public-suffix list,
  /// the same property the Shred Site Data action uses. Scout's own
  /// `eTLDPlusOne` is deliberately *not* used even though it answers the same
  /// question elsewhere: it is a short hand-rolled suffix table, while WebKit
  /// computes `displayName` from the real list, and for `alice.github.io` the
  /// two disagree (`github.io` against `alice.github.io`) — the shred would
  /// quietly delete nothing. Keying on the same list WebKit used is the only
  /// way the names line up.
  ///
  /// `urlToShred` is nil for anything that is not http(s), so a `blob:` or
  /// `data:` main-frame load is taken back by picture only: nothing is
  /// deleted. Those loads have no site-scoped store of their own to clear —
  /// what they touched belongs to the origin that created them, which no
  /// verdict here judged.
  public func shredOrigin(_ url: URL, in dataStore: WKWebsiteDataStore) async {
    guard let site = url.urlToShred?.baseDomain, let host = url.host?.lowercased() else { return }
    // Keyed off the original URL, not `urlToShred`: that property strips the
    // path when `kBraveShieldsContentSettings` is off, which would make every
    // page verdict look like a domain verdict and shred the whole domain.
    let key = VerdictCache.cacheKey(for: url, perPageHosts: Self.perPageHosts)
    guard key.contains("/") else {
      await dataStore.deleteDataRecords(forDomains: [site])
      return
    }
    await Self.deleteCookies(exactlyMatching: host, in: dataStore)
  }

  /// Deletes the cookies set on exactly `host`, and no others.
  ///
  /// Not a suffix test. A cookie scoped to `.google.com` is sent to
  /// `docs.google.com`, but it is equally Gmail's and Search's, and a verdict
  /// about one uploaded document does not reach them. Only a cookie whose own
  /// domain is this host — with or without the leading dot a domain-scoped
  /// cookie carries — belongs to the page being taken back.
  private static func deleteCookies(
    exactlyMatching host: String,
    in dataStore: WKWebsiteDataStore
  ) async {
    let store = dataStore.httpCookieStore
    for cookie in await store.allCookies() where domain(of: cookie) == host {
      await store.deleteCookie(cookie)
    }
  }

  private static func domain(of cookie: HTTPCookie) -> String {
    let domain = cookie.domain.lowercased()
    return domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
  }

  /// Drops the verdict for `url` without fetching another.
  ///
  /// For a verdict the page itself has just disproved: keeping it would mean
  /// deciding the next visit from an answer already known to be wrong.
  public func forget(_ url: URL) {
    cache.forget(url)
  }

  /// Drops what Scout knows about `url` and checks it again. For the "Check
  /// again" action: a site that changed since its verdict was cached is
  /// otherwise stuck with the old answer for up to a week.
  public func recheck(_ url: URL, isPrivate: Bool) async {
    cache.forget(url)
    await refresh(url, isPrivate: isPrivate)
  }

  /// Links being checked ahead of a tap, by cache key. Bounded so a page that
  /// fires a lot of touches can't queue unbounded work.
  private var warming: Set<String> = []
  private static let maxConcurrentWarms = 4

  /// Starts checking `url` before the user has finished opening it.
  ///
  /// Fire-and-forget: the result is only ever wanted through the cache. The
  /// coalescing checker keys in-flight requests the same way the cache keys
  /// entries, so the navigation that follows joins this request instead of
  /// starting a second one — which is the whole point.
  ///
  /// `isPrivate` is the tab's, read when the user acted: a check started from a
  /// private tab keeps its verdict off disk, as the navigation itself would.
  public func warm(_ url: URL, isPrivate: Bool) {
    if isPrivate {
      notePrivateNavigation(to: url)
    }
    // Anything already decidable — a rule, a cached verdict, a scheme — needs
    // no work, and that is the common case on a site already visited.
    guard guard_.decideImmediately(url) == nil else { return }
    let key = VerdictCache.cacheKey(for: url, perPageHosts: Self.perPageHosts)
    guard warming.count < Self.maxConcurrentWarms, !warming.contains(key) else { return }
    warming.insert(key)
    Task { @MainActor in
      _ = await decide(url, isPrivate: isPrivate)
      warming.remove(key)
    }
  }

  /// Checks `url`, keeping a private tab's verdict private however late it
  /// lands.
  ///
  /// A check takes seconds, and the private session can end inside them — the
  /// last private tab closed mid-check. The verdict is written to the cache
  /// when the check returns, which is after `forgetPrivateVerdicts()` has
  /// emptied the list of keys to keep off disk, so it used to be saved with
  /// the normal verdicts and outlive the session it came from. `isPrivate` is
  /// passed in, read while the tab was certainly alive, for the same reason:
  /// by now the tab may be gone.
  public func decide(_ url: URL, isPrivate: Bool) async -> Scout.Decision {
    guard isPrivate else { return await guard_.decide(url) }
    notePrivateNavigation(to: url)
    let session = privateSession
    let decision = await guard_.decide(url)
    privateVerdictLanded(for: url, session: session)
    return decision
  }

  /// `NavigationGuard.refresh`, with the same care for a private tab as
  /// `decide(_:isPrivate:)`.
  public func refresh(_ url: URL, isPrivate: Bool) async {
    guard isPrivate else {
      await guard_.refresh(url)
      return
    }
    notePrivateNavigation(to: url)
    let session = privateSession
    await guard_.refresh(url)
    privateVerdictLanded(for: url, session: session)
  }

  /// A private check has written its verdict. If the session it belonged to
  /// is still running, the verdict is kept off disk with the rest; if it has
  /// ended, everything else it learned is already gone, and so is this.
  private func privateVerdictLanded(for url: URL, session: Int) {
    let key = VerdictCache.cacheKey(for: url, perPageHosts: Self.perPageHosts)
    if session == privateSession {
      privateOnlyKeys.insert(key)
    } else {
      cache.forget(key: key)
    }
  }

  /// Whether a long-press may show a live preview of `url`.
  ///
  /// A preview loads the page in a web view Scout does not gate, so a link
  /// nobody had checked rendered in full inside the preview — on a supervised
  /// phone too. It is only offered for a page Scout has already allowed.
  /// Anything else gets the menu without a preview, and its check starts so a
  /// second long-press can have one.
  ///
  /// `isPrivate` is the tab the long-press happened in. The check started here
  /// is a private visit like any other and its verdict stays off disk.
  ///
  /// The preview's own tab is guarded the same way, by `ScoutDetachedTabGate`,
  /// so a page that redirects somewhere Scout has not allowed stops there.
  public func mayPreview(_ url: URL, isPrivate: Bool) -> Bool {
    ScoutDetachedTabGate.admits(url, isPrivate: isPrivate)
  }

  /// Posted once a decision for a page has been recorded.
  ///
  /// The URL bar's mark is drawn from the stored verdict, and nothing told it
  /// when one arrived: a freshly checked page kept the generic shield until
  /// some other event happened to refresh the toolbar, so the browser looked
  /// like it had not checked a page it had just checked.
  public static let verdictDidChange = Notification.Name("scout.verdict-did-change")

  /// How many links Scout has checked over the life of this install.
  ///
  /// A running tally, not the size of the verdict cache: that cache lives in
  /// Caches and iOS empties it whenever it wants the space back, which would
  /// reset this to zero while the block count stayed where it was.
  public var checkedSiteCount: Int { Preferences.Scout.sitesChecked.value }

  /// How many links Scout has stopped over the life of this install. The
  /// "recently blocked" list is capped; this is not, so the two disagree once
  /// someone has run into more blocks than the list holds.
  public var blockedSiteCount: Int { Preferences.Scout.sitesBlocked.value }

  /// Called for every checked navigation in a private tab.
  public func notePrivateNavigation(to url: URL) {
    privateOnlyKeys.insert(VerdictCache.cacheKey(for: url, perPageHosts: Self.perPageHosts))
  }

  /// Drops everything learned in private tabs. Called when the last private
  /// tab closes, alongside the rest of the private teardown.
  ///
  /// These keys were only ever kept out of the file written to disk, and
  /// cleared when the user cleared history. That left a private visit's verdict
  /// sitting in the in-memory cache for the rest of the app's life: the site
  /// panel would say "Checked 20 minutes ago" for a page the user had only ever
  /// opened privately, and the set of keys grew for every private navigation
  /// and was never emptied.
  public func forgetPrivateVerdicts() {
    for key in privateOnlyKeys { cache.forget(key: key) }
    privateOnlyKeys.removeAll()
    privateSession += 1
  }

  /// The cache keys are the sites the user visited, so clearing history clears
  /// them too.
  public func forgetVerdicts() {
    cache.removeAll()
    privateOnlyKeys.removeAll()
    // A private check still running would otherwise land in a cache that no
    // longer knows to keep it off disk.
    privateSession += 1
    if let url = Self.storeURL {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
      center.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { ScoutServices.shared.save() }
      }
    }
    center.addObserver(forName: .privateDataClearedHistory, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { ScoutServices.shared.forgetVerdicts() }
    }
  }
}
