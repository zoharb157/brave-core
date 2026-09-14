// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Onboarding
import Preferences
import Scout
import Shared
import Web
import WebKit

/// Checks what actually rendered, once it has.
///
/// Everything else Scout knows describes a site: the verdict, the cache, the
/// rules. An injected page on a hacked but legitimate domain inherits that
/// site's honest, clean verdict, and re-fetching cannot tell them apart —
/// because the rest of the domain really is clean. The address catches such a
/// page only when the address says what it is.
///
/// The page's own title is the one thing that describes the page rather than
/// the site, and an injected spam page states plainly what it is: that is the
/// whole point of it. Acting on it means the page has already appeared for a
/// moment, which is worse than never loading it and far better than leaving it
/// up.
class ScoutPageTitleScriptHandler: TabContentScript {
  private struct Report: Decodable {
    let securityToken: String
    let title: String
    let url: URL
  }

  static let scriptName = "ScoutPageTitleScript"
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
      let report = try? JSONDecoder().decode(Report.self, from: data)
    else { return }

    MainActor.assumeIsolated {
      Self.act(on: report, in: tab)
    }
  }

  @MainActor
  private static func act(on report: Report, in tab: some TabState) {
    guard Preferences.ScoutBlocking.chosen.contains(.adult),
      ExplicitURL.looksExplicit(title: report.title)
    else { return }
    // Scout's own pages have no business being judged by this.
    guard InternalURL(report.url) == nil else { return }
    // Someone who chose to allow this site has already answered the question,
    // and so has someone who just tapped "continue anyway" on it.
    let services = ScoutServices.shared
    guard services.siteRules.rule(for: report.url) != .allow else { return }
    if let etldP1 = report.url.baseDomain,
      tab.proceedAnywaysDomainList?.contains(etldP1) == true
    { return }
    // Only act on the page actually on screen: a title arriving late from a
    // page the user has already left must not replace what they moved on to.
    guard tab.visibleURL == report.url else { return }

    // The stored verdict described this site and was wrong about this page.
    // Dropping it means the next visit is decided freshly rather than from an
    // answer this page just disproved.
    services.forget(report.url)

    let decision = Scout.Decision(
      type: .block, reason: .address, matchedCategories: [.adult])
    if !tab.isPrivate, let host = report.url.host {
      services.blockLog.record(site: host, reason: .address, categories: [.adult])
    }
    ScoutActivityReporter.shared.record(
      decision, for: report.url, source: .none, isPrivate: tab.isPrivate)
    ScoutPages.record(decision, for: report.url)
    if let request = ScoutPages.pageRequest(for: report.url) {
      tab.loadRequest(request)
    }
  }
}
