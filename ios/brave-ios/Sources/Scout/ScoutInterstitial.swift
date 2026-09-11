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
  public let secondaryLabel: String
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
        reasons = v.reasons
      } else {
        // Shouldn't happen (a .security reason implies a verdict was
        // resolved), but fall back to the offline copy rather than blank text.
        chipText = "CAUTION"
        title = "Can't verify right now"
        summary = "We couldn't check this page. Try again."
        reasons = []
      }
    case .category:
      chipText = "BLOCKED"
      title = "Blocked by your settings"
      summary = "This page matched: \(categorySummary(matchedCategories))."
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
      summary = "We couldn't check this page. Try again."
      reasons = []
    }

    return ScoutInterstitialModel(
      chipText: chipText,
      isBlocking: type == .block,
      title: title,
      summary: summary,
      reasons: reasons,
      primaryLabel: "Go back",
      secondaryLabel: type == .block ? "Continue anyway" : "Continue")
  }

  public static func html(type: DecisionType, verdict: Verdict?, reason: DecisionReason,
                           matchedCategories: Set<ContentCategory> = []) -> String {
    let m = model(type: type, verdict: verdict, reason: reason, matchedCategories: matchedCategories)
    let chipClass = m.isBlocking ? "chip--block" : "chip--warn"
    // Escaping only applies to content that can originate from the remote
    // check response (a resolved Verdict's title/summary/reasons, surfaced
    // only for the .security reason). All other copy here is a compile-time
    // literal chosen by us, so it is rendered as-is.
    let isRemoteSourced = reason == .security && verdict != nil
    let title = isRemoteSourced ? htmlEscaped(m.title) : m.title
    let summary = isRemoteSourced ? htmlEscaped(m.summary) : m.summary
    let reasonsHTML = m.reasons
      .map { "<span class=\"reason\">\(isRemoteSourced ? htmlEscaped($0) : $0)</span>" }
      .joined()

    return """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>\(css)</style></head><body><div class="card">
    <span class="chip \(chipClass)">\(m.chipText)</span>
    <h1>\(title)</h1><p>\(summary)</p>
    <div class="reasons">\(reasonsHTML)</div>
    <button class="primary" onclick="webkit.messageHandlers.scout.postMessage('back')">\(m.primaryLabel)</button>
    <button class="secondary" onclick="webkit.messageHandlers.scout.postMessage('proceed')">\(m.secondaryLabel)</button>
    </div></body></html>
    """
  }

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

  /// Human-readable label for a category as it appears in "This page
  /// matched: …" copy. Deliberately lowercase, mid-sentence phrasing —
  /// distinct from ScoutUI's onboarding row titles, which are capitalized
  /// standalone labels for a different context.
  private static func categoryLabel(_ category: ContentCategory) -> String {
    switch category {
    case .adult: return "adult content"
    case .gambling: return "gambling"
    case .ads: return "ads"
    }
  }

  private static func categorySummary(_ categories: Set<ContentCategory>) -> String {
    categories.map(categoryLabel).sorted().joined(separator: ", ")
  }

  private static let css = """
  :root{--violet-deep:#7361AE;--ground:#F7F5FB;--ink:#2B2440;
  --rose-clay:#B3626B;--ochre:#B08A3E}
  body{margin:0;font:16px/1.5 -apple-system,system-ui,sans-serif;
  background:var(--ground);color:var(--ink);display:flex;min-height:100vh;
  align-items:center;justify-content:center}
  .card{max-width:32rem;padding:2rem;text-align:center}
  .chip{display:inline-block;padding:.25rem .75rem;border-radius:999px;
  font-weight:700;font-size:.8rem;color:#fff}
  .chip--block{background:var(--rose-clay)}.chip--warn{background:var(--ochre)}
  h1{margin:1rem 0 .5rem}.reasons{display:flex;flex-wrap:wrap;gap:.5rem;
  justify-content:center;margin:1rem 0}
  .reason{background:#ECE7F5;border-radius:999px;padding:.2rem .6rem;font-size:.85rem}
  button{font:inherit;border:0;border-radius:.75rem;padding:.75rem 1.25rem}
  .primary{background:var(--violet-deep);color:#fff}
  .secondary{background:transparent;color:var(--violet-deep)}
  @media(prefers-color-scheme:dark){:root{--ground:#1C1830;--ink:#EEE9F7}
  .reason{background:#2E2748}}
  """
}
