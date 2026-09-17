// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout

/// What a supervised phone does about search engines Scout cannot filter.
///
/// Search filtering pins each engine's own safe mode on through the address.
/// Startpage, Ecosia, Yandex and any engine someone adds have no such switch,
/// so choosing one as the default — no PIN asked — used to be a quiet way to
/// get unfiltered results on a supervised phone. While supervised with
/// filtering on, their results are blocked and they are not offered.
@MainActor
enum ScoutSearchFilter {
  /// Whether unfilterable engines are kept off this phone right now.
  static var isEnforced: Bool {
    ScoutSupervision.shared.isOn && Preferences.Scout.safeSearch.value
  }

  /// Whether Scout has no way to filter `engine`'s results.
  static func cannotFilter(_ engine: OpenSearchEngine) -> Bool {
    guard let url = engine.searchURLForQuery("scout") else { return true }
    return SafeSearch.coverage(of: url) == .unfiltered
  }

  /// The block for `url` when it is a page of such results, or nil.
  ///
  /// A site the parent has allowed outright keeps its allowance: that rule
  /// takes the PIN to add.
  static func block(for url: URL, engines: SearchEngines?) -> Scout.Decision? {
    guard isEnforced,
      ScoutServices.shared.siteRules.rule(for: url) != .allow,
      SafeSearch.isUnfilteredResults(url, customEngines: engines?.customEngineQueryParameters ?? [:])
    else { return nil }
    return Decision(type: .block, reason: .unfilteredSearch)
  }
}

extension SearchEngines {
  /// Each added engine's registrable domain, and the parameter its search
  /// template puts the query in.
  var customEngineQueryParameters: [String: String] {
    var parameters: [String: String] = [:]
    for engine in orderedEngines where engine.isCustomEngine {
      guard let name = engine.queryParameterName,
        let host = engine.searchURLForQuery("scout")?.host
      else { continue }
      parameters[eTLDPlusOne(host)] = name
    }
    return parameters
  }
}
