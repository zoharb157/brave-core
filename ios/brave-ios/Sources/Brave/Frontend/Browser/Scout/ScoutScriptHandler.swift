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
/// On an unsupervised phone the user owns the browser and may accept the risk;
/// on a supervised one the actions that weaken protection ask for the PIN
/// first. Proceeding covers the navigation the user approved and the redirects
/// it follows, and nothing after that — see `ContinueApproval`.
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

  /// "Continue anyway": open this one page.
  ///
  /// The approval covers this address and wherever it redirects, and stops
  /// there. It used to add the site's registrable domain to a per-tab set that
  /// the guard treated as a standing allow, so one tap unchecked every page on
  /// that site for the life of the tab. Someone who wants that has "Always
  /// allow" below, which says so.
  private func proceed(to siteURL: URL, tab: some TabState) {
    MainActor.assumeIsolated {
      tab.scoutTabHelper?.approveContinue(to: siteURL)
      // A private tab's block was never logged, so there is nothing to mark;
      // marking the entry a normal tab left for the same site would record
      // what was done privately.
      if !tab.isPrivate, let host = siteURL.host {
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
      let rules = ScoutServices.shared.siteRules
      // The same button reads "Unblock this site" when the block is the
      // user's own rule, and that means taking the rule away — the site goes
      // back to being checked like any other. It used to write an allow over
      // the block instead, so unblocking a site also switched off every
      // safety and category check on it for good. Nothing else produces a
      // list block here: the built-in block list is empty.
      if rules.rule(for: siteURL) == .block {
        rules.set(nil, for: siteURL)
      } else {
        rules.set(.allow, for: siteURL)
      }
      // The rule itself is a standing setting and applies everywhere; the
      // log entry is a trace of this visit, and a private one leaves none.
      if !tab.isPrivate, let host = siteURL.host {
        ScoutServices.shared.blockLog.noteContinued(site: host)
      }
      ScoutActivityReporter.shared.recordContinued(siteURL, isPrivate: tab.isPrivate)
      tab.loadRequest(URLRequest(url: siteURL))
    }
  }

  /// "Go back" — the page's main action, and the only one on it that does not
  /// weaken protection.
  ///
  /// There is often nothing behind a blocked page. A link opened from another
  /// app, a `target="_blank"`, or an address typed into a fresh tab all land
  /// with no history, and that is precisely the case this browser exists for —
  /// the reason given for filtering the whole phone is that other apps open
  /// links in their own browsers.
  ///
  /// It used to do nothing at all there: the button was pressed, the screen
  /// did not change, and the only controls left that did anything were
  /// "Continue anyway" and "Always allow". A dead primary button that leaves
  /// two working ones, both of which give the page up, is worse than no button.
  ///
  /// With nothing behind it, the tab itself is what goes — the same path a
  /// page takes when it calls `window.close()`, which the browser already
  /// handles by removing the tab and remembering it as recently closed.
  private func goBack(tab: some TabState) {
    MainActor.assumeIsolated {
      if tab.canGoBack {
        tab.goBack()
        return
      }
      tab.delegate?.tabWebViewDidClose(tab)
    }
  }
}
