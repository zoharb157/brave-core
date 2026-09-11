// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Scout
import Shared
import Web

/// Retains the guard for a tab.
///
/// `AnyTabPolicyDecider` holds deciders **weakly**, so a decider nothing else
/// owns is silently dropped and the guard never runs — a failure that looks
/// exactly like "the browser isn't checking anything". Storing the helper in
/// `TabDataValues` is how Brave's own helpers stay alive; we follow that.
extension TabDataValues {
  private struct ScoutTabHelperKey: TabDataKey {
    static var defaultValue: ScoutTabHelper?
  }
  public var scoutTabHelper: ScoutTabHelper? {
    get { self[ScoutTabHelperKey.self] }
    set { self[ScoutTabHelperKey.self] = newValue }
  }
}

@MainActor
public class ScoutTabHelper: TabPolicyDecider {
  weak var tab: (any TabState)?

  public init(tab: some TabState) {
    self.tab = tab
    tab.addPolicyDecider(self)
  }

  public func tab(
    _ tab: some TabState,
    shouldAllowRequest request: URLRequest,
    requestInfo: WebRequestInfo
  ) async -> WebPolicyDecision {
    guard let requestURL = request.url else { return .allow }

    // Only gate top-level document loads. `requestInfo.isMainFrame` is the
    // reliable test — Brave's Shields decider documents that
    // `sourceFrame.isMainFrame` is unreliable on session restore.
    guard ["http", "https", "data", "blob", "file"].contains(requestURL.scheme),
      requestInfo.isMainFrame
    else { return .allow }

    // Never gate internal pages (our own interstitial, error pages, NTP).
    if InternalURL(requestURL) != nil {
      return .allow
    }

    // Reuse Brave's existing per-tab "user proceeded" set rather than adding a
    // parallel one — the interstitial's proceed action writes into it.
    if let etldP1 = requestURL.baseDomain,
      tab.proceedAnywaysDomainList?.contains(etldP1) == true
    {
      return .allow
    }

    let decision = await ScoutServices.shared.guard_.decide(requestURL)
    guard decision.type != .allow else { return .allow }

    let matched = decision.verdict?.categories
      .intersection(ScoutServices.shared.policy.blockedCategories) ?? []
    var html = ScoutInterstitial.html(
      type: decision.type,
      verdict: decision.verdict,
      reason: decision.reason,
      matchedCategories: matched)

    // The generated page posts to a fixed channel name; rewrite it to the
    // script handler's real (UUID-suffixed) name so the buttons reach native.
    html = html.replacingOccurrences(
      of: "webkit.messageHandlers.scout",
      with: "webkit.messageHandlers.\(ScoutScriptHandler.messageHandlerName)")

    ScoutInterstitialState.shared.record(blockedURL: requestURL, in: tab)
    tab.loadHTMLString(html, baseURL: nil)
    return .cancel
  }
}

/// Remembers which URL a tab's interstitial is standing in for, so "continue
/// anyway" knows where to go. Keyed by tab identity and deliberately tiny.
@MainActor
public final class ScoutInterstitialState {
  public static let shared = ScoutInterstitialState()
  private var blocked: [ObjectIdentifier: URL] = [:]

  public func record(blockedURL: URL, in tab: some TabState) {
    blocked[ObjectIdentifier(tab)] = blockedURL
  }

  public func take(for tab: some TabState) -> URL? {
    blocked.removeValue(forKey: ObjectIdentifier(tab))
  }
}
