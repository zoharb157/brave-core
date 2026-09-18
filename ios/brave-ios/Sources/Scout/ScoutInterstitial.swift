import Foundation

/// The content decisions behind an interstitial: which chip, title, summary,
/// reason chips, and button labels to show. Kept separate from HTML rendering
/// so both `ScoutInterstitial.html(...)` (used by the test harness) and the
/// real Brave iOS `BlockedDomainHandler` (which loads an HTML asset from the
/// app bundle and substitutes `%placeholder%` tokens) can consume the same
/// decisions without duplicating the branching rules.
///
/// All strings here are RAW/unescaped. Escaping is the renderer's
/// responsibility (see `ScoutInterstitial.htmlEscaped`), since each
/// renderer knows its own substitution context.
public struct ScoutInterstitialModel: Equatable {
  public let chipText: String
  public let isBlocking: Bool
  public let title: String
  public let summary: String
  public let reasons: [String]
  public let primaryLabel: String
  /// Nil where going on is not offered: a search engine that cannot filter
  /// would show the same unfiltered results after any number of continues.
  public let secondaryLabel: String?
  /// Offered when the check could not be completed, where trying it again is
  /// the thing the reader actually wants. `nil` everywhere else — a verdict
  /// that came back does not become different by asking twice.
  public let retryLabel: String?
  /// A standing decision about this site, offered only where one makes sense:
  /// nil for a malicious page, where the honest offer is a one-time
  /// "continue anyway" and not a permanent exception.
  public let alwaysLabel: String?
}

public enum ScoutInterstitial {
  /// Produces the content decisions for an interstitial: which chip, title,
  /// summary, reasons, and button labels to show for the given decision
  /// type/verdict/reason. Pure content — no HTML or escaping.
  ///
  /// There is no parent and no PIN in this product: a blocked page always
  /// offers "continue anyway", because it is the user's own browser.
  public static func model(type: DecisionType, verdict: Verdict?, reason: DecisionReason,
                            matchedCategories: Set<ContentCategory> = []) -> ScoutInterstitialModel {
    let chipText: String
    let title: String
    let summary: String
    let reasons: [String]

    switch reason {
    case .security:
      if let v = verdict {
        chipText = type == .block ? "NOT SAFE" : "CAUTION"
        title = v.title
        summary = v.summary
        reasons = v.reasons.compactMap(sentenceCased)
      } else {
        // Shouldn't happen (a .security reason implies a verdict was
        // resolved), but fall back to the offline copy rather than blank text.
        chipText = "CAUTION"
        title = "Can't verify right now"
        summary = "We couldn't check this page. Try again."
        reasons = []
      }
    // An address block is a category block that needed no verdict: same
    // decision, same words for it.
    case .category, .address:
      chipText = "BLOCKED"
      title = "Blocked by your settings"
      // Naming what matched is the point of this screen, but an empty set must
      // never render as a sentence with nothing in it ("This page matched: .").
      summary =
        matchedCategories.isEmpty
        ? "This page matched something you chose to block."
        : "This page matched: \(categorySummary(matchedCategories))."
      reasons = []
    case .policyList:
      chipText = "BLOCKED"
      title = "Blocked by your settings"
      summary = "You added this site to your blocked list."
      reasons = []
    case .scheme:
      chipText = "BLOCKED"
      title = "This kind of link is blocked"
      summary = "Scout doesn't open this type of link."
      reasons = []
    case .unavailable:
      // Fail policy (timeout/error): today's offline copy, deliberately soft
      // regardless of decision type.
      chipText = "CAUTION"
      title = "Can't verify right now"
      summary = "We couldn't check this page."
      reasons = []
    case .knownThreat:
      // "NOT SAFE" rather than "BLOCKED", which is the word the other
      // settings-driven blocks use. This one is not a setting: it would stop
      // this page for anybody, and the reader should be able to tell the
      // difference at a glance before reading a word of it.
      chipText = "NOT SAFE"
      title = "This site is known to be dangerous"
      // No verdict was fetched, so there is nothing to say about the page
      // itself — only about the address, which is all that was recognised.
      // Saying where it comes from matters more here than anywhere else on
      // this screen: a block nobody can attribute reads as the browser having
      // an opinion, and this one is a matter of public record.
      summary =
        "This address is on a public list of sites caught stealing passwords or "
        + "spreading malware. Scout stopped it without opening the page."
      reasons = []
    case .uncheckedAddress:
      // Two things went wrong at once and the page has to say both, in that
      // order: the check not finishing is why this screen is here at all, and
      // the address is why it is not the soft `.unavailable` copy above. Said
      // the other way round it reads as an accusation the check never made.
      //
      // What the address gave away is not listed. The signals are named for
      // the service's scoring — "excessive-subdomains", "credentials-in-url" —
      // and rewriting each into a sentence would be a second vocabulary for
      // this screen to keep true. The address is printed under the summary
      // already, which is the thing a reader can actually check.
      chipText = type == .block ? "NOT SAFE" : "CAUTION"
      title = "Couldn't check this — and the address looks wrong"
      summary =
        type == .block
        ? "Scout couldn't reach its safety check, so nothing has looked at this page. "
          + "The address itself is built the way trick links are built."
        : "Scout couldn't reach its safety check, so nothing has looked at this page. "
          + "There is something odd about the address itself."
      reasons = []
    case .insecureCertificate:
      chipText = "NOT SAFE"
      title = "This site's certificate is wrong"
      summary =
        "A certificate is how a site proves it is itself and keeps what you send private. "
        + "This one does not check out, so somebody could be reading or changing what goes "
        + "between this phone and the site."
      reasons = []
    case .unfilteredSearch:
      chipText = "BLOCKED"
      title = "This search engine can't be filtered"
      summary =
        "Scout can't turn on safe search here, so its results could show explicit images. "
        + "Search with Google, Bing or DuckDuckGo instead."
      reasons = []
    // Only ever read back off a stored record, never decided live — but the
    // screen has to have words for it rather than none.
    case .unspecified:
      chipText = "BLOCKED"
      title = "Blocked"
      summary = "Scout stopped this page."
      reasons = []
    }

    // Continuing past a block should be able to stick. Repeating the same
    // override on every visit reads as a browser that isn't listening, and a
    // parent who wants one site allowed has nothing else to reach for. The
    // exception is a page the check found actually dangerous: there the only
    // honest offer is this once.
    let alwaysLabel: String?
    switch reason {
    case .category, .address: alwaysLabel = "Always allow this site"
    case .policyList: alwaysLabel = "Unblock this site"
    // A known attack site sits with `.security` rather than with the settings:
    // going on is offered once, and only once. Nobody sets up a standing
    // exception for a site that is phishing on purpose — and the one tap that
    // would do it is exactly the tap somebody being phished has already been
    // talked into making.
    // And nothing lasting on an address nobody could check. A standing
    // exception written now would be written on the strength of a check that
    // did not happen, and it would outlive the minute the network was down.
    // Nothing standing on a block whose grounds this build cannot name.
    case .security, .scheme, .unavailable, .unfilteredSearch, .knownThreat,
      .uncheckedAddress, .insecureCertificate, .unspecified:
      alwaysLabel = nil
    }

    return ScoutInterstitialModel(
      chipText: chipText,
      isBlocking: type == .block,
      title: title,
      summary: summary,
      reasons: reasons,
      primaryLabel: "Go back",
      // No way on for either of these. A search engine that cannot be
      // filtered returns the same unfiltered results however many times it is
      // asked, and going on past a certificate that does not check out is the
      // whole of what the warning was about — on a phone somebody else is
      // meant to be watching, that is not this screen's to offer.
      secondaryLabel: reason == .unfilteredSearch || reason == .insecureCertificate
        ? nil : type == .block ? "Continue anyway" : "Continue",
      // Offered here as well as on `.unavailable`, because half of what this
      // page says is that the check could not be reached — and reaching it is
      // what would settle the other half.
      retryLabel: reason == .unavailable || reason == .uncheckedAddress ? "Try again" : nil,
      alwaysLabel: alwaysLabel)
  }

  public static func html(type: DecisionType, verdict: Verdict?, reason: DecisionReason,
                           matchedCategories: Set<ContentCategory> = [],
                           host: String = "") -> String {
    let m = model(type: type, verdict: verdict, reason: reason, matchedCategories: matchedCategories)
    // Escaping only applies to content that can originate from the remote
    // check response (a resolved Verdict's title/summary/reasons, surfaced
    // only for the .security reason). All other copy here is a compile-time
    // literal chosen by us, so it is rendered as-is.
    let isRemoteSourced = reason == .security && verdict != nil
    let title = isRemoteSourced ? htmlEscaped(m.title) : m.title
    let summary = isRemoteSourced ? htmlEscaped(m.summary) : m.summary
    let reasonsHTML = m.reasons
      .map { "<li>\(isRemoteSourced ? htmlEscaped($0) : $0)</li>" }
      .joined()
    let reasonsBlock = m.reasons.isEmpty ? "" : "<ul class=\"reasons\">\(reasonsHTML)</ul>"
    let hostBlock = host.isEmpty ? "" : "<p class=\"host\">\(htmlEscaped(host))</p>"
    let tone = m.isBlocking ? "block" : "warn"
    // When nothing could be established, checking again is the action the
    // page was already telling people to take — it just had no button. It
    // leads, because going back or continuing unchecked are both worse
    // answers to "we couldn't check this".
    let retryBlock =
      m.retryLabel.map {
        "<button class=\"primary\" onclick=\"webkit.messageHandlers.scout.postMessage('retry')\">\(htmlEscaped($0))</button>"
      } ?? ""

    let proceedBlock =
      m.secondaryLabel.map {
        "<button class=\"quiet\" onclick=\"webkit.messageHandlers.scout.postMessage('proceed')\">\(htmlEscaped($0))</button>"
      } ?? ""

    // "Continue anyway" lasts for this visit; this one lasts forever. They
    // were the same quiet button with different words, so the permanent one
    // read as no more consequential than the temporary one above it — and it
    // took a single tap to stop Scout checking a site for good. It is set
    // apart, it says what it will do, and it asks twice.
    let alwaysBlock =
      m.alwaysLabel.map { label in
        let note = Self.lastingNote(reason: reason, host: host)
        // Inline, like the two buttons above it: this page's other actions
        // are inline handlers, and a <script> block here did nothing when
        // tapped. Arming lives on the element itself so there is no state to
        // keep anywhere else, and it disarms after four seconds so it cannot
        // be armed now and hit by accident later.
        let arm =
          "if(this.dataset.armed===\'1\'){window.webkit.messageHandlers.scout.postMessage(\'always\');}"
          + "else{this.dataset.armed=\'1\';this.textContent=\'Tap again to confirm\';"
          + "this.classList.add(\'armed\');var b=this;setTimeout(function(){b.dataset.armed=\'\';"
          + "b.textContent=b.getAttribute(\'data-label\');b.classList.remove(\'armed\');},4000);}"
        return """
        <div class="lasting">
          <button class="lasting-btn" data-label="\(htmlEscaped(label))"
            onclick="\(arm)">\(htmlEscaped(label))</button>
          <p class="lasting-note">\(note)</p>
        </div>
        """
      } ?? ""

    // Without a title the browser falls back to the page's address, and these
    // pages live at `internal://local/scout…`. Several blocked tabs then read
    // as the same unreadable string in the tab tray, in history and anywhere
    // else a title is shown, with no way to tell which site each one was.
    let pageTitle = htmlEscaped(Self.tabTitle(blocking: m.isBlocking, host: host))

    return """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <title>\(pageTitle)</title>
    <style>\(css)</style></head>
    <body class="tone-\(tone)">
      <main class="card">
        <div class="glyph">\(m.isBlocking ? shieldGlyph : warnGlyph)</div>
        <span class="chip">\(m.chipText)</span>
        <h1>\(title)</h1>
        <p class="lede">\(summary)</p>
        \(hostBlock)
        \(reasonsBlock)
        <div class="actions">
          \(retryBlock)
          <button class="\(m.retryLabel == nil ? "primary" : "quiet")" onclick="webkit.messageHandlers.scout.postMessage('back')">\(m.primaryLabel)</button>
          \(proceedBlock)
          \(alwaysBlock)
        </div>
      </main>
    </body></html>
    """
  }

  /// The page shown *while* the check runs. The service fetches and analyses
  /// the page, which takes seconds — showing that work is far better than a
  /// frozen tab followed by a verdict appearing from nowhere.
  public static func checkingHTML(host: String) -> String {
    let pageTitle = htmlEscaped(host.isEmpty ? "Checking" : "Checking \(host)")
    return """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <title>\(pageTitle)</title>
    <style>\(css)</style></head>
    <body class="tone-check">
      <main class="card">
        <div class="scanner" role="img" aria-label="Checking this link">
          <svg viewBox="0 0 120 120" class="globe">
            <circle class="ring ring-a" cx="60" cy="60" r="52"/>
            <circle class="ring ring-b" cx="60" cy="60" r="52"/>
            <g class="mark">
              <circle cx="60" cy="60" r="26"/>
              <line x1="34" y1="60" x2="86" y2="60"/>
              <path d="M60 34 C 49 43, 49 77, 60 86"/>
              <path d="M60 34 C 71 43, 71 77, 60 86"/>
            </g>
            <g class="sweep"><path d="M60 60 L60 4 A56 56 0 0 1 108 34 Z"/></g>
          </svg>
        </div>
        <span class="chip">CHECKING</span>
        <h1>Checking this link</h1>
        <p class="lede">Scout is looking at this page before it opens.</p>
        <p class="host">\(htmlEscaped(host))</p>
        <ul class="steps">
          <li class="s1">Reading the address</li>
          <li class="s2">Checking for phishing &amp; scams</li>
          <li class="s3">Matching your blocked categories</li>
        </ul>
      </main>
    </body></html>
    """
  }

  private static let shieldGlyph = """
  <svg viewBox="0 0 48 48"><path d="M24 4 L42 11 v13 c0 11-8 17-18 20 C14 41 6 35 6 24 V11 Z"/>  <path class="x" d="M17 17 L31 31 M31 17 L17 31"/></svg>
  """
  private static let warnGlyph = """
  <svg viewBox="0 0 48 48"><path d="M24 5 L45 41 H3 Z"/>  <path class="x" d="M24 18 v11 M24 34 v.5"/></svg>
  """

  /// Escapes text that originates from the remote check response (title,
  /// summary, reasons) before it is interpolated into the interstitial's
  /// HTML. The page is loaded via `loadHTMLString` into a `WKWebView` that
  /// runs JavaScript, so unescaped remote text (which is itself derived from
  /// an untrusted, potentially hostile scraped page) could inject
  /// markup/script and forge the `webkit.messageHandlers.scout
  /// .postMessage(...)` calls the interstitial's own buttons use.
  ///
  /// Public so the future Brave `BlockedDomainHandler` (which substitutes
  /// `%placeholder%` tokens into a bundled HTML asset) can reuse the same
  /// escaping instead of reimplementing it.
  public static func htmlEscaped(_ raw: String) -> String {
    var escaped = raw
    escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
    escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
    escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
    escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
    escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
    return escaped
  }

  /// What the tab is called while one of these pages is showing.
  ///
  /// The site leads. In a tray of tabs the question is which one this is, and
  /// the shield on the thumbnail already says it was stopped — but a title
  /// truncated to "Blocked \u{2026}" would answer neither.
  /// What the permanent button will actually do, said before it is tapped.
  ///
  /// It used to name the host on screen whatever it did. But an allow is
  /// written for the site as a whole, so "stop checking www.google.com" also
  /// stopped checking docs.google.com and sites.google.com — the places
  /// anyone can put a page. And on a site the user blocked, the same note sat
  /// under "Unblock", which puts the site back under normal checking rather
  /// than out of it.
  ///
  /// It has to name the same boundary the rule is written against, which is
  /// `siteOwner` and not `eTLDPlusOne`: on a free host those differ, and the
  /// wider of the two would promise to stop checking every tenant's pages
  /// when the rule reaches only this one's.
  static func lastingNote(reason: DecisionReason, host: String) -> String {
    guard !host.isEmpty else {
      return reason == .policyList
        ? "Scout will check this site again, like any other."
        : "Scout will stop checking this site."
    }
    if reason == .policyList {
      return "Scout will check \(htmlEscaped(host)) again, like any other site."
    }
    let site = siteOwner(host)
    if site == host.lowercased() {
      return "Scout will stop checking \(htmlEscaped(host))."
    }
    return "Scout will stop checking every page on \(htmlEscaped(site)), not only \(htmlEscaped(host))."
  }

  static func tabTitle(blocking: Bool, host: String) -> String {
    guard !host.isEmpty else { return blocking ? "Blocked" : "Not opened" }
    return blocking ? "\(host) — blocked" : "\(host) — not opened"
  }

  /// Human-readable label for a category as it appears in "This page
  /// matched: …" copy. Deliberately lowercase, mid-sentence phrasing —
  /// distinct from ScoutUI's onboarding row titles, which are capitalized
  /// standalone labels for a different context.
  private static func categoryLabel(_ category: ContentCategory) -> String {
    switch category {
    case .adult: return "adult content"
    case .gambling: return "gambling"
    }
  }

  private static func categorySummary(_ categories: Set<ContentCategory>) -> String {
    categories.map(categoryLabel).sorted().joined(separator: ", ")
  }

  private static let css = """
  :root {
    --violet: #8570D2; --violet-deep: #544096; --ink: #1E1830;
    --ground: #F6F4FB; --card: #FFFFFF; --muted: #6B6382;
    --rose: #B3626B; --ochre: #B08A3E; --mint: #7EC8A8;
    --tone: var(--violet-deep);
  }
  body.tone-block { --tone: var(--rose); }
  body.tone-warn  { --tone: var(--ochre); }
  body.tone-check { --tone: var(--violet-deep); }
  @media (prefers-color-scheme: dark) {
    :root { --ground:#141020; --card:#1E1830; --ink:#EFEAF8; --muted:#A79DC0; }
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    margin: 0; display: flex; align-items: center; justify-content: center;
    padding: 24px; background: var(--ground); color: var(--ink);
    font: 16px/1.55 -apple-system, system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  .card {
    width: 100%; max-width: 30rem; background: var(--card);
    border-radius: 26px; padding: 34px 26px 26px; text-align: center;
    box-shadow: 0 1px 2px rgba(20,10,50,.05), 0 18px 48px -12px rgba(40,20,90,.18);
    animation: rise .42s cubic-bezier(.2,.7,.3,1) both;
  }
  @keyframes rise { from { opacity:0; transform: translateY(10px) scale(.985);} }

  .glyph { width: 62px; height: 62px; margin: 0 auto 14px; }
  .glyph svg { width: 100%; height: 100%; }
  .glyph path { fill: color-mix(in srgb, var(--tone) 14%, transparent); stroke: var(--tone); stroke-width: 2.4; stroke-linejoin: round; }
  .glyph .x { fill: none; stroke: var(--tone); stroke-width: 3.4; stroke-linecap: round; }

  .chip {
    display: inline-block; padding: .3rem .8rem; border-radius: 999px;
    font-size: .7rem; font-weight: 800; letter-spacing: .09em;
    color: #fff; background: var(--tone);
  }
  h1 {
    margin: .7rem 0 .35rem; font-size: 1.55rem; line-height: 1.2;
    font-weight: 750; letter-spacing: -.02em; text-wrap: balance;
  }
  .lede { margin: 0 auto; max-width: 26rem; color: var(--muted); }
  .host {
    margin: .9rem 0 0; font-size: .82rem; color: var(--muted);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    word-break: break-all; opacity: .85;
  }
  .reasons {
    list-style: none; margin: 1.1rem 0 0; padding: 0;
    display: flex; flex-direction: column; gap: .4rem; text-align: left;
  }
  .reasons li {
    font-size: .87rem; color: var(--ink); background: color-mix(in srgb, var(--tone) 9%, transparent);
    border-radius: 12px; padding: .5rem .75rem .5rem 2rem; position: relative;
  }
  .reasons li::before {
    content: ""; position: absolute; left: .78rem; top: 50%;
    width: 6px; height: 6px; border-radius: 50%; background: var(--tone);
    transform: translateY(-50%);
  }
  .actions { display: flex; flex-direction: column; gap: .3rem; margin-top: 1.5rem; }
  button { font: inherit; border: 0; cursor: pointer; border-radius: 15px; }
  .primary {
    background: var(--violet-deep); color: #fff; font-weight: 650;
    padding: .92rem 1.2rem; transition: transform .12s ease, opacity .12s ease;
  }
  .primary:active { transform: scale(.985); opacity: .92; }
  .quiet { background: transparent; color: var(--muted); padding: .72rem; font-size: .92rem; }
  .lasting { margin-top: .9rem; padding-top: .9rem; border-top: 1px solid rgba(107,99,130,.22); }
  .lasting-btn {
    background: transparent; color: var(--muted); font-size: .86rem;
    padding: .5rem .72rem; width: 100%;
  }
  .lasting-btn.armed { color: var(--rose); font-weight: 600; }
  .lasting-note { margin: .15rem 0 0; font-size: .76rem; color: var(--muted); opacity: .85; }
  .lasting-btn:focus-visible { outline: 3px solid var(--violet); outline-offset: 3px; }
  button:focus-visible { outline: 3px solid var(--violet); outline-offset: 3px; }

  /* ---- checking state ---- */
  .scanner { width: 128px; height: 128px; margin: 4px auto 16px; }
  .globe { width: 100%; height: 100%; overflow: visible; }
  .globe .mark circle, .globe .mark line, .globe .mark path {
    fill: none; stroke: var(--violet-deep); stroke-width: 3.2; stroke-linecap: round;
  }
  .globe .ring { fill: none; stroke: var(--violet); stroke-width: 2; opacity: .28; }
  .ring-a { animation: pulse 2.1s ease-out infinite; }
  .ring-b { animation: pulse 2.1s ease-out infinite 1.05s; }
  @keyframes pulse {
    0%   { transform: scale(.62); opacity: .42; }
    70%  { opacity: .06; }
    100% { transform: scale(1.06); opacity: 0; }
  }
  .globe .ring { transform-origin: 60px 60px; }
  .sweep path { fill: color-mix(in srgb, var(--mint) 55%, transparent); }
  .sweep { transform-origin: 60px 60px; animation: spin 1.5s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  .steps {
    list-style: none; margin: 1.2rem 0 .2rem; padding: 0;
    display: flex; flex-direction: column; gap: .45rem; text-align: left;
  }
  .steps li {
    font-size: .88rem; color: var(--muted); padding-left: 1.7rem; position: relative;
    opacity: .35; animation: lightUp .5s ease forwards;
  }
  .steps li::before {
    content: ""; position: absolute; left: .35rem; top: .48rem;
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--violet-deep); opacity: .35;
  }
  .steps .s1 { animation-delay: .15s; }
  .steps .s2 { animation-delay: 1.1s; }
  .steps .s3 { animation-delay: 2.2s; }
  @keyframes lightUp { to { opacity: 1; } }

  @media (prefers-reduced-motion: reduce) {
    .card, .steps li { animation: none; opacity: 1; }
    .sweep, .ring-a, .ring-b { animation: none; }
    .globe .ring { opacity: .22; }
  }
  """

}

/// The service's reasons are model-written and inconsistently cased
/// ("common phishing tactics"); show each as a sentence, and drop empties.
private func sentenceCased(_ reason: String) -> String? {
  let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
  guard let first = trimmed.first else { return nil }
  return first.uppercased() + trimmed.dropFirst()
}
