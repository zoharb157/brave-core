// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout

/// Keeps the warm list on disk and fetches a newer one now and then.
///
/// The request carries a version number and nothing else. That is the whole
/// privacy story for this feature: the phone never names a site to find out
/// about it, it downloads the same file everybody downloads.
public final class ScoutWarmListStore {
  public static let shared = ScoutWarmListStore()

  private static let endpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/warm-list")!
  /// How long a list may answer for before the phone goes back to asking.
  private static let maxAge: TimeInterval = 14 * 24 * 3600
  /// How often the phone is willing to ask for a newer one.
  private static let refreshInterval: TimeInterval = 24 * 3600

  private let session: URLSession

  private init(session: URLSession = .shared) {
    self.session = session
  }

  private var fileURL: URL? {
    FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("scout-warm-list.json")
  }

  /// The list to use: whatever was downloaded, or the one that shipped.
  public func load() -> WarmList? {
    let made = { (data: Data) -> WarmList? in
      WarmList(
        data: data, now: { Date() }, maxAge: Self.maxAge,
        perPageHosts: ScoutServices.perPageHosts)
    }
    if let fileURL, let data = try? Data(contentsOf: fileURL), let list = made(data) {
      return list
    }
    guard let bundled = Bundle.module.url(forResource: "scout-warm-list", withExtension: "json"),
      let data = try? Data(contentsOf: bundled)
    else { return nil }
    return made(data)
  }

  /// Asks for a newer list, at most once a day.
  ///
  /// Failure is silent and leaves the previous file in place. The list is an
  /// optimisation; a stale one is better than none, and it stops answering on
  /// its own once it is too old.
  public func refreshIfDue() async {
    let last = Preferences.Scout.warmListCheckedAt.value
    guard Date().timeIntervalSince1970 - last > Self.refreshInterval else { return }

    var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
    if let version = load()?.version {
      components?.queryItems = [URLQueryItem(name: "since", value: version)]
    }
    guard let url = components?.url else { return }

    var request = URLRequest(url: url)
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200
    else { return }

    Preferences.Scout.warmListCheckedAt.value = Date().timeIntervalSince1970

    // No `entries` means the version we already have is current.
    guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["entries"] != nil, let fileURL
    else { return }
    // The endpoint's contract (`WarmListContract` in the server) is
    // deliberately `{ version, entries }` — no build timestamp, because the
    // server-side cache is rebuilt on its own schedule and that detail isn't
    // this feature's business. `WarmList.init?` still needs a `builtAt` to
    // know when a list goes stale, so the phone stamps it with the moment it
    // finished downloading. That is a reasonable stand-in: staleness only has
    // to answer "should this phone still be trusting this file", and "since I
    // last fetched it" answers that as well as "since the server built it"
    // would.
    object["builtAt"] = Date().timeIntervalSince1970
    guard let stamped = try? JSONSerialization.data(withJSONObject: object) else { return }
    try? stamped.write(to: fileURL, options: .atomic)
  }
}
