// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout

/// Where the user's own protection decisions live.
///
/// These are choices a person made, not data Scout can re-derive, so unlike the
/// verdict cache they go in preferences (the shared app-group defaults) and
/// survive a Caches purge, an update, and clearing history.
extension Preferences.Scout {
  /// Sites the user allowed or blocked by hand, as `[site: "allow"|"block"]`.
  static let siteRules = Preferences.Option<[String: String]>(
    key: "scout.site-rules",
    default: [:]
  )

  /// The recent-blocks list, as JSON. A plist array of dictionaries would need
  /// every value to be a plist type; one JSON string keeps the record shape
  /// the log's own business.
  static let blockLog = Preferences.Option<String>(
    key: "scout.block-log",
    default: ""
  )

  /// Whether search engines are pinned to their own filtered mode.
  ///
  /// Separate from the adult-content category because it does something
  /// different: the category decides whether a site opens, this decides what a
  /// results page is allowed to show before anything is clicked. On by
  /// default — an unfiltered results page shows explicit thumbnails to
  /// someone who never opened an explicit site.
  public static let safeSearch = Preferences.Option<Bool>(
    key: "scout.safe-search",
    default: true
  )
}

/// Reads and writes the two stores through preferences.
///
/// Both core types announce their own changes (`onChange`), so persistence is
/// wired once here rather than at every call site that might change a rule.
enum ScoutProtectionStore {
  static func loadSiteRules() -> SiteRules {
    let rules = SiteRules.deserialize(Preferences.Scout.siteRules.value)
    rules.onChange = { [weak rules] in
      guard let rules else { return }
      Preferences.Scout.siteRules.value = rules.serialize()
    }
    return rules
  }

  static func loadBlockLog() -> BlockLog {
    let log = BlockLog()
    let stored = Preferences.Scout.blockLog.value
    if !stored.isEmpty, let data = stored.data(using: .utf8),
      let wire = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    {
      log.load(wire)
    }
    log.onChange = { [weak log] in
      guard let log else { return }
      guard let data = try? JSONSerialization.data(withJSONObject: log.serialize()),
        let json = String(data: data, encoding: .utf8)
      else { return }
      Preferences.Scout.blockLog.value = json
    }
    return log
  }
}
