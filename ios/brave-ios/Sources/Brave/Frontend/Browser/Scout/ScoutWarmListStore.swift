// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout

/// Keeps the warm list on disk, fetches a newer one now and then, and holds
/// the current list in memory so the guard sees a fresh download the moment
/// it lands rather than only on the next cold start.
///
/// The request carries a version number and nothing else. That is the whole
/// privacy story for this feature: the phone never names a site to find out
/// about it, it downloads the same file everybody downloads.
///
/// `@MainActor`, matching the other Scout singletons in this directory
/// (`ScoutServices`, `ScoutActivityReporter`, `ScoutSupervision`). The one
/// exception is `verdict(for:)`: `WarmListProviding` is a synchronous,
/// non-isolated requirement, and `NavigationGuard` calls it from a plain,
/// non-actor context — so that single witness is `nonisolated`, and the list
/// it reads is guarded by `lock` rather than by actor isolation.
@MainActor
public final class ScoutWarmListStore: WarmListProviding {
  public static let shared = ScoutWarmListStore()

  private static let endpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/warm-list")!
  /// How long a list may answer for before the phone goes back to asking.
  private static let maxAge: TimeInterval = 14 * 24 * 3600
  /// How often the phone is willing to ask for a newer one.
  private static let refreshInterval: TimeInterval = 24 * 3600

  private let session: URLSession
  private let lock = NSLock()
  /// The list `verdict(for:)` answers from. Read and written under `lock`
  /// rather than through actor isolation, since the sole reader —
  /// `verdict(for:)` — must stay synchronous and non-isolated to satisfy
  /// `WarmListProviding` the way `NavigationGuard` calls it.
  private nonisolated(unsafe) var current: WarmList?

  private init(session: URLSession = .shared) {
    self.session = session
    current = Self.loadFromDisk()
  }

  private static var fileURL: URL? {
    FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("scout-warm-list.json")
  }

  /// The list to use at startup: whatever was downloaded, or the one that
  /// shipped.
  ///
  /// Carries the stored confirmation with it, so a list the server has gone on
  /// re-asserting keeps answering across relaunches rather than starting every
  /// cold launch from its build date alone.
  private static func loadFromDisk() -> WarmList? {
    let confirmed = Preferences.Scout.warmListConfirmedCurrentAt.value
    let made = { (data: Data) -> WarmList? in
      let list = WarmList(
        data: data, now: { Date() }, maxAge: maxAge,
        perPageHosts: ScoutServices.perPageHosts,
        confirmedCurrentAt: confirmed > 0 ? Date(timeIntervalSince1970: confirmed) : nil)
      return list
    }
    if let fileURL, let data = try? Data(contentsOf: fileURL), let list = made(data) {
      return list
    }
    guard let bundled = Bundle.module.url(forResource: "scout-warm-list", withExtension: "json"),
      let data = try? Data(contentsOf: bundled)
    else {
      return nil
    }
    return made(data)
  }

  /// A warm verdict for `url`, from whatever list is currently held.
  ///
  /// Non-isolated so `NavigationGuard` — a plain, non-actor type — can call it
  /// synchronously, exactly as it does today. Thread safety for `current`
  /// comes from `lock`, not from actor isolation.
  public nonisolated func verdict(for url: URL) -> Verdict? {
    lock.lock()
    defer { lock.unlock() }
    return current?.verdict(for: url)
  }

  private var currentVersion: String? {
    lock.lock()
    defer { lock.unlock() }
    return current?.version
  }

  /// Asks for a newer list, at most once a day.
  ///
  /// Failure is silent and leaves the previous file in place. The list is an
  /// optimisation; a stale one is better than none, and it stops answering on
  /// its own once it is too old.
  public func refreshIfDue() async {
    let last = Preferences.Scout.warmListCheckedAt.value
    guard Date().timeIntervalSince1970 - last > Self.refreshInterval else { return }
    // Stamped before the request goes out, not after: this caps attempts at
    // one a day regardless of outcome. Stamping only on success meant a down
    // endpoint, or a phone behind a captive portal, got asked again on every
    // single cold launch.
    Preferences.Scout.warmListCheckedAt.value = Date().timeIntervalSince1970

    var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
    if let version = currentVersion {
      components?.queryItems = [URLQueryItem(name: "since", value: version)]
    }
    guard let url = components?.url else { return }

    var request = URLRequest(url: url)
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200
    else { return }

    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }

    // No `entries` means the version we already have is current. That reply
    // still carries the server's `builtAt`, and it is the only thing keeping
    // this phone's list alive: the entry set is hash-stable and moves slowly,
    // so a phone installed weeks after the build sends its bundled version,
    // hears "you're current" every day, and — if this reply were thrown away —
    // would sail past `maxAge` and stop answering permanently, with no later
    // refresh able to repair it.
    guard let rows = object["entries"] as? [[String: Any]] else {
      noteStillCurrent(object)
      return
    }

    // An empty list is not a list to install. The server returns `[]` only
    // when nothing is common enough to publish yet, and a phone that already
    // holds a real list would be trading it for nothing — so keep what is
    // held and let the next refresh bring something worth having.
    guard !rows.isEmpty, let fileURL = Self.fileURL else { return }

    // `WarmList.init?` requires `builtAt` and is the safety valve that stops
    // a phone trusting a list once it's too old to answer for — that only
    // works against a timestamp the server actually computed. The server
    // contract now carries one; a payload that still fails to parse here is
    // left unwritten rather than stamped with a timestamp of this phone's
    // own invention, which would measure "when I downloaded this" instead of
    // "when this was built" and defeat the whole point of the check.
    guard
      let list = WarmList(
        data: data, now: { Date() }, maxAge: Self.maxAge, perPageHosts: ScoutServices.perPageHosts)
    else { return }

    // A freshly downloaded list ages from its own `builtAt`; any confirmation
    // held for the list it replaces is about a different version.
    Preferences.Scout.warmListConfirmedCurrentAt.value = 0
    try? data.write(to: fileURL, options: .atomic)
    lock.lock()
    current = list
    lock.unlock()
  }

  /// Records that the server re-asserted the list this phone already holds,
  /// and re-stamps the held list so it goes on answering.
  ///
  /// Re-stamping is safe here only because the value is the server's own
  /// timestamp: it says "the list you have is the one I would send you, and I
  /// built it at X". A mark of this phone's own making would turn the age
  /// check into "when did I last download something", which is the thing it
  /// exists not to measure.
  private func noteStillCurrent(_ object: [String: Any]) {
    guard let builtAt = object["builtAt"] as? TimeInterval,
      builtAt > Preferences.Scout.warmListConfirmedCurrentAt.value
    else { return }
    Preferences.Scout.warmListConfirmedCurrentAt.value = builtAt
    guard let list = Self.loadFromDisk() else { return }
    lock.lock()
    current = list
    lock.unlock()
  }
}
