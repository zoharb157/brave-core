// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences.Scout {
  /// Which revision of `ScoutFilterLists.defaults` this install has been
  /// subscribed to. Kept so a list the user removed is not added back.
  static let defaultFilterListsRevision = Preferences.Option<Int>(
    key: "scout.default-filter-lists-revision",
    default: 0
  )
}

/// The filter lists every install subscribes to.
///
/// The full lists a browser like this normally blocks with arrive as components
/// from the upstream update server, and that server refuses this app: it wants
/// a key only the upstream vendor's own builds carry. Without them, blocking
/// ran on the small built-in rule set alone — no element hiding, no list
/// updates, and an "ads blocked" count that never left zero, because the count
/// comes from the engine those lists feed.
///
/// These are downloaded straight from their publishers through the same path
/// as a filter list someone adds by URL, so they update on the same schedule
/// and can be switched off in the same place.
@MainActor
enum ScoutFilterLists {
  static let defaults: [URL] = [
    URL(string: "https://easylist.to/easylist/easylist.txt")!,
    URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
  ]
  /// Bump when `defaults` gains a list, so installs subscribed to the old set
  /// pick up the new one.
  private static let revision = 1

  /// Adds the default lists to `storage` once per revision.
  static func subscribeIfNeeded(_ storage: CustomFilterListStorage) {
    guard Preferences.Scout.defaultFilterListsRevision.value < revision else { return }
    for url in defaults
    where !storage.filterListsURLs.contains(where: { $0.setting.externalURL == url }) {
      storage.filterListsURLs.append(
        FilterListCustomURL(externalURL: url, isEnabled: true, inMemory: !storage.persistChanges)
      )
    }
    Preferences.Scout.defaultFilterListsRevision.value = revision
  }
}
