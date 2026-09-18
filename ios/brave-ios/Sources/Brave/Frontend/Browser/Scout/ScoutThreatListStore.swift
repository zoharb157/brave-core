// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout
import Shared

/// Keeps the public phishing and malware lists on disk, fetches newer ones now
/// and then, and holds the parsed hosts in memory so the guard sees a fresh
/// download the moment it lands rather than only on the next cold start.
///
/// Built like `ScoutWarmListStore`, which does the same job for the opposite
/// answer, and differs from it in three ways the data forces.
///
/// The files are published by somebody else, so there is no version number to
/// send and nothing to ask for a delta: the phone sends back the ETag it was
/// given last time and is usually told the file has not changed. That is the
/// whole privacy story for this feature, and it is the same one as the warm
/// list's — the phone never names a site to find out about it, it downloads
/// the file everybody downloads.
///
/// The two lists are kept apart rather than merged into one file. They fail
/// separately: one publisher can go down, or start serving something that is
/// not a filter list, while the other is fine. Each ages on its own timestamp,
/// so a dead source stops answering without taking a live one with it.
///
/// And what is kept is the parsed hosts, never the file. Three megabytes of
/// text arrives and a set of host names stays.
///
/// `@MainActor`, matching the other Scout singletons in this directory. Two
/// exceptions, both deliberate: `listsAsThreat(_:)` is a synchronous,
/// non-isolated requirement of `ThreatListProviding` that `NavigationGuard`
/// calls from a plain non-actor context, and the downloading and parsing are
/// non-isolated because neither waiting on the network nor walking forty
/// thousand lines belongs on the main actor. What they share is guarded by
/// `lock` rather than by actor isolation.
@MainActor
public final class ScoutThreatListStore: ThreatListProviding {
  public static let shared = ScoutThreatListStore()

  /// One published list, and the name its parsed copy is filed under on disk.
  private struct Source: Sendable {
    let name: String
    let url: URL
  }

  nonisolated private static let sources: [Source] = [
    Source(
      name: "phishing",
      url: URL(string: "https://malware-filter.gitlab.io/malware-filter/phishing-filter.txt")!),
    Source(
      name: "urlhaus",
      url: URL(
        string: "https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-online.txt")!),
  ]

  /// How long a downloaded list may go on blocking for.
  ///
  /// Both lists are rebuilt every twelve hours and this asks once a day, so a
  /// week is seven consecutive failures: long enough to ride out a phone that
  /// spent a fortnight in a drawer, a captive portal, or a publisher having a
  /// bad week. Short enough that a site which was compromised, cleaned up and
  /// taken off the list is not still blocked on week-old evidence — a block
  /// nobody can explain and the user cannot appeal is worse than a page taking
  /// the ordinary route, which is what decided every one of these pages before
  /// this list existed.
  nonisolated private static let maxAge: TimeInterval = 7 * 24 * 3600
  /// How often the phone is willing to ask for newer ones.
  nonisolated private static let refreshInterval: TimeInterval = 24 * 3600
  /// Bigger than either list has any business being. A download is untrusted
  /// input and `Data` has no ceiling of its own; without this, whatever
  /// answers at that address can hand the phone as much memory as it likes.
  nonisolated private static let maxDownloadBytes = 16 * 1024 * 1024

  private let session: URLSession
  private let lock = NSLock()
  /// The lists `listsAsThreat(_:)` answers from, one per source. Read and
  /// written under `lock` rather than through actor isolation, since the sole
  /// reader must stay synchronous and non-isolated to satisfy
  /// `ThreatListProviding` the way `NavigationGuard` calls it.
  private nonisolated(unsafe) var current: [ThreatList] = []
  /// The read of the cached copies, so a refresh cannot install over the top
  /// of a load that has not finished.
  private var diskLoad: Task<Void, Never>?

  private init(session: URLSession = .shared) {
    self.session = session
    // Reading two files and parsing forty thousand lines is not something to
    // do on the main thread while the browser is trying to draw, so launch
    // does not wait for it: the lists install themselves a moment later and
    // recognise nothing until they do. Failing to recognise a site for the
    // first instants of a cold launch costs one ordinary check, which is the
    // route every one of these pages took before this existed.
    diskLoad = Task.detached(priority: .utility) { [weak self] in
      let loaded = Self.loadFromDisk()
      guard !loaded.isEmpty else { return }
      self?.install(loaded)
    }
  }

  /// Whether `url` is on either list.
  ///
  /// Non-isolated so `NavigationGuard` — a plain, non-actor type — can call it
  /// synchronously on the navigation path. Thread safety comes from `lock`.
  public nonisolated func listsAsThreat(_ url: URL) -> Bool {
    lock.lock()
    let lists = current
    lock.unlock()
    return lists.contains { $0.listsAsThreat(url) }
  }

  /// How many hosts are being recognised, across both lists.
  public nonisolated var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return current.reduce(0) { $0 + $1.count }
  }

  private nonisolated func install(_ lists: [ThreatList]) {
    lock.lock()
    current = lists
    lock.unlock()
  }

  // MARK: - On disk

  /// Where a source's parsed hosts live between launches.
  ///
  /// The app group container, which is where `Preferences` already keeps
  /// everything that has to survive: it is not swept when the system reclaims
  /// caches, and an extension could read it if one ever needed to. A phone
  /// that cannot see the container just re-downloads.
  nonisolated private static func fileURL(_ name: String) -> URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: AppInfo.sharedContainerIdentifier)?
      .appendingPathComponent("scout-threat-\(name).txt")
  }

  nonisolated private static func cached(_ name: String) -> ThreatList? {
    guard let url = fileURL(name), let data = try? Data(contentsOf: url) else { return nil }
    return ThreatList(
      data: data, now: { Date() }, maxAge: maxAge, perPageHosts: ScoutServices.perPageHosts)
  }

  nonisolated private static func loadFromDisk() -> [ThreatList] {
    sources.compactMap { cached($0.name) }
  }

  // MARK: - Asking for newer ones

  /// Asks for newer lists, at most once a day.
  ///
  /// Failure is silent and leaves the previous files in place. A list that
  /// cannot be refreshed is still better than none, and it stops answering on
  /// its own once it is too old.
  public func refreshIfDue() async {
    guard
      WarmListResponse.isRefreshDue(
        lastCheckedAt: Preferences.Scout.threatListCheckedAt.value, now: Date(),
        interval: Self.refreshInterval)
    else { return }
    // Stamped before the requests go out, not after: this caps attempts at one
    // a day regardless of outcome, so a publisher that is down, or a phone
    // behind a captive portal, is not asked again on every cold launch.
    Preferences.Scout.threatListCheckedAt.value = Date().timeIntervalSince1970

    // Let the cached copies land first. Without this a refresh that manages
    // only one source would install that one alone, dropping the other's last
    // good copy because `current` was still empty when it finished.
    await diskLoad?.value

    for source in Self.sources {
      let etag = Self.etagPreference(source.name)
      let modified = Self.modifiedPreference(source.name)
      // The validators are read and written here on the main actor, and the
      // work between is not: only strings cross.
      guard
        let fetched = await fetch(
          source, ifNoneMatch: etag.value, ifModifiedSince: modified.value)
      else { continue }
      // Recorded only once the bytes have arrived, parsed and been written.
      // Stamping them on arrival would mean a file that failed to parse was
      // never usefully asked for again: the phone would be told "not
      // modified" from then on and never get a copy it could read.
      etag.value = fetched.etag
      modified.value = fetched.modified
    }
  }

  /// What a download that worked leaves for the main actor to remember.
  private struct Validators: Sendable {
    let etag: String
    let modified: String
  }

  /// Downloads one source, parses it, writes it, and installs the result
  /// alongside whatever the other source currently has.
  ///
  /// Returns nil whenever there is nothing new to remember — told it has not
  /// changed, could not be reached, or handed something that is not a filter
  /// list. All three mean the same thing: go on with the copy on disk.
  ///
  /// Non-isolated: the download waits on the network and the parse walks tens
  /// of thousands of lines, and neither belongs on the main actor. Nothing
  /// that is not `Sendable` crosses back.
  private nonisolated func fetch(
    _ source: Source, ifNoneMatch etag: String, ifModifiedSince modified: String
  ) async -> Validators? {
    var request = URLRequest(url: source.url)
    // Conditional, so the usual answer is a 304 with no body at all. These
    // files are rebuilt every twelve hours and this asks every twenty-four, so
    // without it the phone would pull three megabytes a day to be told roughly
    // the same thing.
    if !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
    if !modified.isEmpty { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }

    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse,
      http.statusCode == 200, data.count <= Self.maxDownloadBytes
    else { return nil }

    // Scoped so the megabytes of text are gone by the time this returns. What
    // is kept is the set of hosts and nothing else.
    let hosts: Set<String> = {
      ThreatList.hosts(fromFilterText: String(decoding: data, as: UTF8.self))
    }()
    // A list that parsed to nothing is not a list. Something else answered at
    // that address — a captive portal, an error page, a file that is no longer
    // a filter list — and installing it would quietly switch this off while
    // looking like it had worked.
    guard !hosts.isEmpty else { return nil }

    // The shared-hosting names are handed in, not written down again here:
    // a bare entry for one of them would block every tenant of it, and the
    // browser's list of them is the one the cache and the warm list use.
    let list = ThreatList(
      hosts: hosts, builtAt: Date(), now: { Date() }, maxAge: Self.maxAge,
      perPageHosts: ScoutServices.perPageHosts)
    if let url = Self.fileURL(source.name) {
      try? list.serialize().write(to: url, options: .atomic)
    }
    // Rebuilt from what is on disk plus the one just parsed, rather than
    // appended to what is held: the other source's copy may be older than this
    // one, or missing, and reading it back is how each keeps its own age.
    install(
      Self.sources.compactMap { $0.name == source.name ? list : Self.cached($0.name) })

    return Validators(
      etag: http.value(forHTTPHeaderField: "ETag") ?? "",
      modified: http.value(forHTTPHeaderField: "Last-Modified") ?? "")
  }

  /// The validators from the last download that worked.
  ///
  /// Built on demand rather than declared once per source: an `Option` reads
  /// its value out of the container when it is made, so one built here holds
  /// what is stored now, and there is no list of preference names to keep in
  /// step with the list of sources.
  private static func etagPreference(_ name: String) -> Preferences.Option<String> {
    Preferences.Option<String>(key: "scout.threat-list.etag.\(name)", default: "")
  }

  private static func modifiedPreference(_ name: String) -> Preferences.Option<String> {
    Preferences.Option<String>(key: "scout.threat-list.modified.\(name)", default: "")
  }
}
