// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Shared
import Web
import WebKit

/// Starts the safety check when a link is touched, not when it is followed.
///
/// A navigation can't be allowed until Scout has a verdict, and fetching one
/// takes a beat — which is the checking page the user sees on every site they
/// haven't been to. `pointerdown` lands well before the navigation does, and
/// the checker coalesces by the same key the cache uses, so the navigation's
/// own request joins this one rather than starting a second. The wait is
/// whatever is left of it, usually nothing.
///
/// Only links the user actually touched: this tracks intent rather than
/// guessing at the page, which keeps the work — and the bill for it —
/// proportional to what someone is really about to open.
class ScoutLinkWarmScriptHandler: TabContentScript {
  private struct Warm: Decodable {
    let securityToken: String
    let url: URL
  }

  static let scriptName = "ScoutLinkWarmScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .defaultClient
  static let userScript: WKUserScript? = {
    guard let script = loadUserScript(named: scriptName) else { return nil }
    return WKUserScript(
      source: secureScript(
        handlerName: messageHandlerName,
        securityToken: scriptId,
        script: script
      ),
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: true,
      in: scriptSandbox
    )
  }()

  func tab(
    _ tab: some TabState,
    receivedScriptMessage message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    defer { replyHandler(nil, nil) }
    guard verifyMessage(message: message) else {
      assertionFailure("Missing required security token.")
      return
    }
    guard let data = try? JSONSerialization.data(withJSONObject: message.body),
      let warm = try? JSONDecoder().decode(Warm.self, from: data)
    else { return }

    MainActor.assumeIsolated {
      // A private tab's verdicts stay out of the store on disk, the same as
      // one the user navigated to.
      if tab.isPrivate {
        ScoutServices.shared.notePrivateNavigation(to: warm.url)
      }
      ScoutServices.shared.warm(warm.url)
    }
  }
}
