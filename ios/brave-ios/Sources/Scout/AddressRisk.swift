import Foundation

/// What the address alone says about a page, for the moments when nothing else
/// can say anything.
///
/// The service scores the address as well as the page: a link with a password
/// in front of the host, a bare IP where a name should be, a brand's name
/// parked in a subdomain of somewhere else. Those signals never needed the
/// network — they are read off the text of the URL — but they only existed on
/// the server, so a phone that could not reach it lost them along with
/// everything else. That is exactly the moment they are worth most: the check
/// failed, the user's fail mode says open it, and nothing at all has looked at
/// `http://apple.com@evil.example/`.
///
/// So this is the server's own address pass, ported to run on the phone with
/// no network, no registry and no page fetch. The codes, the weights and the
/// two thresholds are copied from `signal-weights.ts` rather than reinvented,
/// because the phone and the server describing the same address differently is
/// a bug a parent would have to referee.
///
/// It is not a second opinion. `NavigationGuard` asks it only where the real
/// check produced no answer; where the service answered, the service scored
/// the address too and its answer stands.
public enum AddressRisk {
  /// What the shape of an address amounts to.
  ///
  /// Named for what is known rather than for what to do about it. `.doubtful`
  /// is not "warn" — it is "this would not survive a second look", and the
  /// guard decides what that is worth.
  public enum Level: Equatable, Sendable {
    case ordinary, doubtful, dangerous
  }

  /// One thing the address gave away. The raw values are the server's own
  /// signal codes, so a phone-side reason reads the same as the server's.
  public enum Reason: String, Equatable, Sendable, CaseIterable {
    case brandInSubdomain = "brand-in-subdomain"
    case brandLabelInSubdomain = "brand-label-in-subdomain"
    case credentialsInURL = "credentials-in-url"
    case punycodeHost = "punycode-host"
    case ipAddressHost = "ip-address-host"
    case excessiveSubdomains = "excessive-subdomains"
    case suspiciousTLD = "suspicious-tld"
    case noHTTPS = "no-https"

    /// Mirrors `SIGNAL_WEIGHTS` in `signal-weights.ts`. Changing one of these
    /// without changing the other is how the two sides start disagreeing.
    public var weight: Int {
      switch self {
      case .brandInSubdomain: return 60
      case .brandLabelInSubdomain: return 15
      case .credentialsInURL: return 50
      case .punycodeHost: return 30
      case .ipAddressHost: return 25
      case .excessiveSubdomains: return 15
      case .suspiciousTLD: return 15
      case .noHTTPS: return 10
      }
    }
  }

  public struct Assessment: Equatable, Sendable {
    public let level: Level
    public let reasons: [Reason]
    /// The summed weights, capped at 100 as the server caps them. Kept because
    /// a level alone cannot be checked against the server's own thresholds.
    public let score: Int

    public init(level: Level, reasons: [Reason], score: Int) {
      self.level = level
      self.reasons = reasons
      self.score = score
    }

    public static let ordinary = Assessment(level: .ordinary, reasons: [], score: 0)
  }

  /// `SCORE_THRESHOLDS.malicious` and `.suspicious` from `signal-weights.ts`.
  static let dangerousScore = 60
  static let doubtfulScore = 30
  static let maxScore = 100

  /// `SUSPICIOUS_TLDS` from `url-heuristics.ts`: suffixes that a phishing
  /// campaign can have for nothing, or that read as a file name in a link.
  static let suspiciousTLDs: Set<String> = [
    "zip", "mov", "tk", "ml", "ga", "cf", "gq", "top", "xyz", "click",
    "country", "kim", "work", "party", "gdn",
  ]

  /// `PROTECTED_BRANDS` from `typosquat.ts`: the names worth impersonating.
  static let protectedBrands: [String] = [
    "apple.com", "google.com", "paypal.com", "microsoft.com", "amazon.com",
    "netflix.com", "facebook.com", "instagram.com", "whatsapp.com",
    "binance.com", "coinbase.com", "chase.com", "wellsfargo.com", "dhl.com",
    "fedex.com",
  ]

  /// Reads `url`'s text and nothing else. No network, no registry, no fetch,
  /// and never throws — an address it cannot parse is an address it has
  /// nothing to say about, which is `.ordinary`.
  public static func judge(_ url: URL) -> Assessment {
    guard let host = url.host?.lowercased(), !host.isEmpty else { return .ordinary }

    var reasons: [Reason] = []
    let labels = host.split(separator: ".").map(String.init).filter { !$0.isEmpty }

    if isAddressLiteral(host) {
      reasons.append(.ipAddressHost)
    }
    if labels.contains(where: { $0.hasPrefix("xn--") }) {
      reasons.append(.punycodeHost)
    }
    // Anything before the `@` — `http://apple.com@evil.example/` shows the
    // brand and opens the attacker. Foundation has already split it off the
    // host for us, which is the whole trick it plays on a reader.
    if url.user(percentEncoded: false)?.isEmpty == false
      || url.password(percentEncoded: false)?.isEmpty == false
    {
      reasons.append(.credentialsInURL)
    }
    if labels.count > 4 {
      reasons.append(.excessiveSubdomains)
    }
    if let tld = labels.last, suspiciousTLDs.contains(tld) {
      reasons.append(.suspiciousTLD)
    }
    if url.scheme?.lowercased() != "https" {
      reasons.append(.noHTTPS)
    }
    if let brand = brandSignal(host) {
      reasons.append(brand)
    }

    return score(reasons)
  }

  /// Sums the weights and maps them through the server's thresholds. Pure, so
  /// the arithmetic the two sides share can be tested on its own.
  static func score(_ reasons: [Reason]) -> Assessment {
    let raw = reasons.reduce(0) { $0 + $1.weight }
    let score = min(maxScore, max(0, raw))
    let level: Level
    if score >= dangerousScore {
      level = .dangerous
    } else if score >= doubtfulScore {
      level = .doubtful
    } else {
      level = .ordinary
    }
    return Assessment(level: level, reasons: reasons, score: score)
  }

  /// What a protected brand's name in somebody else's subdomain amounts to,
  /// or nil when there is none. Mirrors `detectBrandAbuse` in `typosquat.ts`,
  /// which raises the same two signals for the same two shapes.
  ///
  /// They are not the same claim, and reading them as one was a bug on both
  /// sides. The brand's *whole* registrable domain buried in a subdomain —
  /// `apple.com` inside `apple.com.login.evil.ru` — is a decoy and nothing
  /// else: no service hands a tenant a name with a dot-com in it, and the part
  /// of a long host a phone shows is the beginning of it. That is
  /// `.brandInSubdomain`, and it is heavy enough to stop a page on its own.
  ///
  /// The brand as a plain *label* is what every multi-tenant service looks
  /// like. `apple.stackexchange.com`, `apple.slack.com`, `amazon.workday.com`
  /// and `paypal.myshopify.com` all wear it, and scored as the decoy they were
  /// hard-blocked. It is still half of the classic shape, so it is kept as
  /// `.brandLabelInSubdomain` — at a weight that has to find company before it
  /// means anything.
  ///
  /// A brand's own country site needs no special case any more. Only a
  /// complete public suffix list knows that `com.co` and `com.pe` are
  /// suffixes, so read with the short list this package falls back on,
  /// `www.google.com.co` comes out as a subdomain "google" of a site "com.co"
  /// — a bare label, which is now 15 points and no verdict. The dot-com shape
  /// a country site can never have is the only one that still blocks.
  static func brandSignal(_ host: String) -> Reason? {
    let labels = host.split(separator: ".").map(String.init).filter { !$0.isEmpty }
    guard labels.count > 1 else { return nil }
    let site = eTLDPlusOne(host)
    let siteLabelCount = site.split(separator: ".").count
    guard labels.count > siteLabelCount else { return nil }
    let subdomainLabels = Array(labels.dropLast(siteLabelCount))

    for brand in protectedBrands where site != brand {
      let brandLabels = brand.split(separator: ".").map(String.init)
      let buried = subdomainLabels.indices.contains { at in
        brandLabels.enumerated().allSatisfy { offset, label in
          at + offset < subdomainLabels.count && subdomainLabels[at + offset] == label
        }
      }
      if buried { return .brandInSubdomain }
    }
    for brand in protectedBrands where site != brand {
      let name = brand.split(separator: ".").first.map(String.init) ?? brand
      if subdomainLabels.contains(name) { return .brandLabelInSubdomain }
    }
    return nil
  }
}
