import Foundation

/// Somewhere to look before trusting anything Scout already believes.
public protocol ThreatListProviding {
  func listsAsThreat(_ url: URL) -> Bool
}

/// Hosts that are publicly known to be phishing or serving malware.
///
/// The mirror image of `WarmList`, and deliberately built the same way: a file
/// of host names, refreshed now and then, read before the network check so the
/// phone can answer for itself. What it answers is the opposite. A warm list
/// entry says "this one is fine, don't wait"; an entry here says "this one is
/// known to be an attack, don't open it at all".
///
/// It exists because the two things that decide a page before the network —
/// the cache and the warm list — both say safe, and neither of them can learn
/// otherwise. A site is checked, found clean, cached for a week, and is then
/// compromised or bought by somebody phishing on the Tuesday after. The
/// service's own check can be fooled too: a convincing clone of a bank reads
/// to a model exactly like the bank. A list built from reports of real attacks
/// catches both cases, and catches them without asking the network anything.
///
/// Not part of `VerdictCache`, for the same reason `WarmList` is not: forty
/// thousand entries poured through a two-thousand-entry LRU would evict
/// everything this phone earned by browsing, and these are not verdicts. There
/// is no title, no summary and no reasons here — a listed host is blocked on
/// the fact that it is listed, which is all the file knows.
public final class ThreatList: ThreatListProviding {
  public var count: Int { hosts.count }

  private let hosts: Set<String>
  private let builtAt: Date
  private let now: () -> Date
  private let maxAge: TimeInterval

  /// How far behind the list's own timestamp this phone's clock may be.
  ///
  /// Same slack, same reason as `WarmList`: a clock set forward makes a fresh
  /// list look ancient, a clock set back makes an ancient one look fresh, and
  /// an age that can be negative is not an age. Here the consequence points
  /// the other way, though — where a warm list that stops answering only costs
  /// a wait, this one stopping means an attack site gets through to the
  /// ordinary check. That is still the right way to fail: the check is what
  /// decided these pages before this list existed.
  private static let clockSlack: TimeInterval = 24 * 3600

  /// - Parameter hosts: lower-cased host names, already parsed. The store
  ///   holds the parsed set and never the file it came from, so a list that
  ///   costs three megabytes to download costs a set of strings to keep.
  /// - Parameter builtAt: when the data was fetched. The lists themselves are
  ///   rebuilt every twelve hours and say so in a comment header, but they do
  ///   not carry a machine-readable build time, so this is the download's own
  ///   timestamp rather than the publisher's.
  /// - Parameter maxAge: how long the data may go on blocking for. Past it the
  ///   list answers `false` to everything and the page takes the ordinary
  ///   route. Stale threat data is worse than no threat data: a site that was
  ///   compromised, cleaned up and delisted would otherwise stay blocked for
  ///   as long as the phone kept the file, with nothing on the page to explain
  ///   why and nothing the user could do about it.
  public init(hosts: Set<String>, builtAt: Date, now: @escaping () -> Date,
              maxAge: TimeInterval) {
    self.hosts = hosts
    self.builtAt = builtAt
    self.now = now
    self.maxAge = maxAge
  }

  /// Whether `url` is on the list — as the exact host, or as any parent of it
  /// down to the registrable domain.
  ///
  /// The parent walk is what makes a listing worth having. Phishing is hosted
  /// on a name registered for it half an hour ago, and the report names
  /// whichever host the victim was sent to; the next victim gets a different
  /// subdomain of the same registration. Walking up covers those without
  /// covering anything else.
  ///
  /// It stops at the registrable domain and goes no further, because the label
  /// above it is a public suffix — one report about a `.com` phishing site
  /// must never come out as "`.com` is a threat". It also walks whole labels
  /// only, so `notbad-example.com` is not a child of `bad-example.com`: it is
  /// a different registration that merely reads like one, which is exactly the
  /// trick these sites are built on.
  public func listsAsThreat(_ url: URL) -> Bool {
    let age = now().timeIntervalSince(builtAt)
    guard age > -Self.clockSlack, age < maxAge else { return false }
    guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
    let site = eTLDPlusOne(host)
    var candidate = host
    while true {
      if hosts.contains(candidate) { return true }
      // The registrable domain is the last thing worth asking about. Checked
      // before we stop, not after, so a list that names the bare domain
      // catches every page on it.
      if candidate == site { return false }
      guard let dot = candidate.firstIndex(of: ".") else { return false }
      candidate = String(candidate[candidate.index(after: dot)...])
      // A host that ran out of labels without ever reaching `site` means the
      // two disagree about what a site is. Stop rather than loop.
      if candidate.isEmpty { return false }
    }
  }

  // MARK: - Reading the published files

  /// Host names from one of the published filter files.
  ///
  /// The files are adblock syntax, and are written for a content blocker that
  /// can match a whole URL. Scout can only decide a host, so it reads the
  /// lines that are about a host and ignores the rest:
  ///
  /// - `||host^` is the shape this understands: a whole host, nothing else.
  /// - A bare host on its own line is the same statement without the syntax,
  ///   and the published files carry thousands of them.
  /// - Anything carrying `/`, `*`, `$` or `#` is dropped, and dropping it is
  ///   the point rather than a simplification. Those rules name a *page* —
  ///   `||0.gravatar.com/avatar/…^$all`, `||1drv.ms/o/…^$all` — and the host
  ///   in front of the slash is an ordinary site someone hosted one attack
  ///   page on. Taking the host off those lines would block Gravatar,
  ///   OneDrive, Weebly and every other host anybody has ever been phished
  ///   through. A page-level rule needs page-level matching, which is the
  ///   service's job, not this file's.
  /// - `!` comments, exception rules (`@@`), and anything that does not read
  ///   as a host name are dropped as well.
  ///
  /// Nothing here trusts the file to be well formed. It is downloaded from the
  /// internet, it can arrive truncated or be something else entirely, and a
  /// junk line has to cost one skipped line rather than a wrong block.
  public static func hosts(fromFilterText text: String) -> Set<String> {
    var found: Set<String> = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }
      // One test for every option, path, wildcard and cosmetic rule at once,
      // applied before anything is unwrapped so no shape can slip past by
      // being unwrapped first.
      if line.contains("/") || line.contains("*") || line.contains("$")
        || line.contains("#") || line.contains("@")
      {
        continue
      }
      var candidate = Substring(line)
      if candidate.hasPrefix("||") {
        candidate = candidate.dropFirst(2)
        guard candidate.hasSuffix("^") else { continue }
        candidate = candidate.dropLast()
      } else if candidate.hasSuffix("^") {
        // `host^` without the anchor is not a rule these files emit, and
        // guessing at what it meant is how a parser starts accepting things
        // nobody wrote.
        continue
      }
      let host = candidate.lowercased()
      guard isHostName(host) else { continue }
      found.insert(host)
    }
    return found
  }

  /// Whether `host` reads as a host name: labels of letters, digits and
  /// hyphens, separated by dots, with at least two of them.
  ///
  /// Deliberately strict, and deliberately not a URL parse. `URL(string:)`
  /// accepts a great deal that is not a host, and every accepted line here
  /// becomes a block nobody can appeal — so the bar is "this could not be
  /// anything but a host name". A single label is refused too: no registrable
  /// domain has one, and a stray word from a mangled download would otherwise
  /// match every host under it.
  static func isHostName(_ host: String) -> Bool {
    guard !host.isEmpty, host.count <= 253 else { return false }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else { return false }
    return labels.allSatisfy { label in
      guard !label.isEmpty, label.count <= 63 else { return false }
      guard label.first != "-", label.last != "-" else { return false }
      return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
  }

  // MARK: - Keeping it between launches

  /// The parsed hosts, as the bytes to write to disk.
  ///
  /// One host per line after a header naming the format and when the data was
  /// fetched. Not JSON: forty thousand quoted strings is a megabyte of
  /// punctuation and a parse that builds an array of them before the set can
  /// be made, on a path that runs at launch. Lines cost a split.
  public func serialize() -> Data {
    var text = "\(Self.header) \(Int(builtAt.timeIntervalSince1970))\n"
    text += hosts.sorted().joined(separator: "\n")
    return Data(text.utf8)
  }

  /// Reads back what `serialize()` wrote, or nil if the file is not that.
  ///
  /// A file that fails to read is not an empty list: answering nothing is the
  /// correct outcome, but it has to come back as "there is no list here" so
  /// the store keeps looking rather than installing a list of no hosts and
  /// calling it current.
  public convenience init?(data: Data, now: @escaping () -> Date, maxAge: TimeInterval) {
    let text = String(decoding: data, as: UTF8.self)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard let first = lines.first, first.hasPrefix(Self.header),
      let stamp = TimeInterval(first.dropFirst(Self.header.count).trimmingCharacters(in: .whitespaces))
    else { return nil }
    lines.removeFirst()
    var hosts: Set<String> = []
    hosts.reserveCapacity(lines.count)
    for line in lines {
      let host = line.trimmingCharacters(in: .whitespaces)
      // Checked again on the way in. The file lives in a container other
      // processes can write to, and a host that fails the same test it passed
      // on the way out means these are not our bytes.
      guard Self.isHostName(host) else { continue }
      hosts.insert(host)
    }
    self.init(
      hosts: hosts, builtAt: Date(timeIntervalSince1970: stamp), now: now, maxAge: maxAge)
  }

  private static let header = "# scout-threat-list 1"
}
