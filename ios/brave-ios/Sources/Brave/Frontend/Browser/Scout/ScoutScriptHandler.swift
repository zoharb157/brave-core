// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Shared
import Web
import WebKit

/// Receives the interstitial's button presses.
///
/// There is no parent and no PIN in this product: the user owns the browser and
/// may accept the risk. Proceeding records the domain in Brave's existing
/// per-tab set so the same origin is not re-prompted in that tab.
class ScoutScriptHandler: TabContentScript {
  static let scriptName = "ScoutScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .page
  static let userScript: WKUserScript? = nil

  func tab(
    _ tab: some TabState,
    receivedScriptMessage message: WKScriptMessage,
    replyHandler: (Any?, String?) -> Void
  ) {
    defer { replyHandler(nil, nil) }

    guard let action = message.body as? String else { return }

    switch action {
    case "proceed":
      proceed(tab: tab)
    case "back":
      goBack(tab: tab)
    default:
      break
    }
  }

  private func proceed(tab: some TabState) {
    MainActor.assumeIsolated {
      guard let url = ScoutInterstitialState.shared.take(for: tab) else { return }
      if let etldP1 = url.baseDomain {
        tab.proceedAnywaysDomainList?.insert(etldP1)
      }
      tab.loadRequest(URLRequest(url: url))
    }
  }

  private func goBack(tab: some TabState) {
    MainActor.assumeIsolated {
      _ = ScoutInterstitialState.shared.take(for: tab)
      if tab.canGoBack {
        tab.goBack()
      }
    }
  }
}
