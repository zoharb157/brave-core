// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Onboarding
import Scout
import Shared
import Strings
import SwiftUI

/// What Scout knows about the page you're on, at the top of the panel behind
/// the URL bar.
///
/// A check that passes is invisible: the page opens exactly as it would in a
/// browser doing nothing. That leaves the only evidence of the product working
/// being the times it got in the way — and leaves the user no way to change
/// their mind about a site except by triggering the block again. This says what
/// Scout found, when, and gives the standing decision a home.
struct ScoutSitePanelView: View {
  let url: URL
  /// Whether the panel is for a private tab, so a recheck keeps its verdict off disk.
  var isPrivate = false
  /// Called after a rule changes, so the page can be reloaded under it.
  var onRuleChanged: (URL) -> Void

  @State private var status: ScoutServices.SiteStatus?
  @State private var isRechecking = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 20))
          .foregroundStyle(tint)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(headline)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(braveSystemName: .textPrimary))
            .fixedSize(horizontal: false, vertical: true)
          if let checkedAt = status?.checkedAt {
            Text(
              String(
                format: Strings.ScoutSitePanel.checkedAt,
                checkedAt.formatted(.relative(presentation: .numeric)))
            )
            .font(.caption)
            .foregroundStyle(Color(braveSystemName: .textSecondary))
          }
        }
        Spacer(minLength: 0)
      }

      HStack(spacing: 8) {
        if status?.rule == nil {
          action(Strings.ScoutSitePanel.allow, symbol: "checkmark.circle") { set(.allow) }
          action(Strings.ScoutSitePanel.block, symbol: "minus.circle") { set(.block) }
        } else {
          action(Strings.ScoutSitePanel.undo, symbol: "arrow.uturn.backward") { set(nil) }
        }
      }

      action(
        isRechecking ? Strings.ScoutSitePanel.checking : Strings.ScoutSitePanel.recheck,
        symbol: "arrow.clockwise",
        action: recheck
      )
      .disabled(isRechecking)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(braveSystemName: .containerBackground),
      in: .rect(cornerRadius: 14, style: .continuous)
    )
    .padding(.horizontal)
    .onAppear { status = ScoutServices.shared.status(for: url) }
  }

  // MARK: - What it says

  private var headline: String {
    guard let status else { return Strings.ScoutSitePanel.notChecked }
    switch status.rule {
    case .allow: return Strings.ScoutSitePanel.alwaysAllowed
    case .block: return Strings.ScoutSitePanel.alwaysBlocked
    case nil: break
    }
    guard let verdict = status.verdict else { return Strings.ScoutSitePanel.notChecked }
    if verdict.security == .malicious { return Strings.ScoutSitePanel.checkedUnsafe }
    if !status.blockedCategories.isEmpty {
      let names = status.blockedCategories.map(\.title).sorted()
      return String(
        format: Strings.ScoutSitePanel.checkedBlockedCategory,
        ListFormatter.localizedString(byJoining: names))
    }
    if verdict.security == .suspicious { return Strings.ScoutSitePanel.checkedSuspicious }
    return Strings.ScoutSitePanel.checkedSafe
  }

  private var symbol: String {
    guard let status else { return "questionmark.circle" }
    switch status.rule {
    case .allow: return "checkmark.circle.fill"
    case .block: return "minus.circle.fill"
    case nil: break
    }
    guard let verdict = status.verdict else { return "questionmark.circle" }
    if verdict.security == .malicious || !status.blockedCategories.isEmpty {
      return "exclamationmark.triangle.fill"
    }
    if verdict.security == .suspicious { return "exclamationmark.circle.fill" }
    return "checkmark.shield.fill"
  }

  private var tint: Color {
    guard let status else { return Color(braveSystemName: .textSecondary) }
    if status.rule == .block { return scoutRose }
    if status.rule == .allow { return scoutMint }
    guard let verdict = status.verdict else { return Color(braveSystemName: .textSecondary) }
    if verdict.security == .malicious || !status.blockedCategories.isEmpty {
      return Color(braveSystemName: .systemfeedbackErrorIcon)
    }
    if verdict.security == .suspicious { return Color(braveSystemName: .systemfeedbackWarningIcon) }
    return scoutMint
  }

  // MARK: - Acting on it

  private func set(_ rule: SiteRule?) {
    ScoutServices.shared.siteRules.set(rule, for: url)
    status = ScoutServices.shared.status(for: url)
    onRuleChanged(url)
  }

  private func recheck() {
    isRechecking = true
    Task { @MainActor in
      await ScoutServices.shared.recheck(url, isPrivate: isPrivate)
      status = ScoutServices.shared.status(for: url)
      isRechecking = false
    }
  }

  private func action(
    _ title: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: symbol)
        Text(title).lineLimit(1)
      }
      .font(.footnote.weight(.medium))
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity)
      .background(scoutViolet.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(scoutViolet)
  }
}
