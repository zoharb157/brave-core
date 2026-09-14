// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Scout
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

    // Only Scout's own pages may drive these actions, and the page's address
    // names the site it stands in for.
    guard let action = message.body as? String,
      message.frameInfo.isMainFrame,
      let siteURL = ScoutPages.siteURL(fromPageURL: message.frameInfo.request.url)
    else { return }

    switch action {
    case "proceed":
      proceed(to: siteURL, tab: tab)
    case "always":
      allowFromNowOn(siteURL, tab: tab)
    case "retry":
      retry(siteURL, tab: tab)
    case "back":
      goBack(tab: tab)
    default:
      break
    }
  }

  /// Checks the page again after a check that couldn't be completed.
  ///
  /// Drops whatever is on hand for the site first: a fail-open allow is cached
  /// like any other answer, so simply re-navigating would hand back the same
  /// non-answer and the button would appear to do nothing.
  private func retry(_ siteURL: URL, tab: some TabState) {
    MainActor.assumeIsolated {
      ScoutServices.shared.forget(siteURL)
      tab.loadRequest(URLRequest(url: siteURL))
    }
  }

  private func proceed(to siteURL: URL, tab: some TabState) {
    MainActor.assumeIsolated {
      if let etldP1 = siteURL.baseDomain {
        tab.proceedAnywaysDomainList?.insert(etldP1)
      }
      if let host = siteURL.host {
        ScoutServices.shared.blockLog.noteContinued(site: host)
      }
      ScoutActivityReporter.shared.recordContinued(siteURL, isPrivate: tab.isPrivate)
      tab.loadRequest(URLRequest(url: siteURL))
    }
  }

  /// The standing version of "continue anyway": the site is allowed from now
  /// on, in every tab and after a relaunch, until the user changes it in
  /// Settings → Protection.
  ///
  /// A page the user had blocked by hand offers this as "Unblock this site",
  /// which is the same write with the opposite starting point — clearing the
  /// rule would put the site straight back under whatever blocked it first, so
  /// both paths set an explicit allow.
  private func allowFromNowOn(_ siteURL: URL, tab: some TabState) {
    MainActor.assumeIsolated {
      // A standing allow is the most consequential thing on this page, so on a
      // supervised phone it asks first. "Continue anyway" above it does not.
      ScoutSupervision.shared.gate(
        .alwaysAllowFromBlockPage,
        from: tab.view.window?.rootViewController
      ) {
        Self.applyAllow(siteURL, tab: tab)
      }
    }
  }

  private static func applyAllow(_ siteURL: URL, tab: some TabState) {
    MainActor.assumeIsolated {
      ScoutServices.shared.siteRules.set(.allow, for: siteURL)
      if let host = siteURL.host {
        ScoutServices.shared.blockLog.noteContinued(site: host)
      }
      ScoutActivityReporter.shared.recordContinued(siteURL, isPrivate: tab.isPrivate)
      tab.loadRequest(URLRequest(url: siteURL))
    }
  }

  private func goBack(tab: some TabState) {
    MainActor.assumeIsolated {
      if tab.canGoBack {
        tab.goBack()
      }
    }
  }
}
