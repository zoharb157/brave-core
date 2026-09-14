// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import Onboarding
import Preferences
import Scout
import Shared
import Strings
import SwiftUI
import UIKit

/// Scout's colours. Defined here as well as in the onboarding module because
/// the two live in separate targets and a shared design token for one brand
/// colour isn't worth a new module.
let scoutViolet = Color(red: 0x54 / 255, green: 0x40 / 255, blue: 0x96 / 255)
let scoutMint = Color(red: 0x7E / 255, green: 0xC8 / 255, blue: 0xA8 / 255)
/// For the one thing on the violet status card that needs to read as unfinished
/// rather than wrong. A design-system orange would be tuned for a page
/// background, not for sitting on the accent itself.
let scoutAmber = Color(red: 0xF5 / 255, green: 0xC2 / 255, blue: 0x6B / 255)

/// Everything Scout does to keep sites out, on one screen.
///
/// These settings were spread across two unrelated Settings rows, which made
/// the protection look like two small features instead of the thing the
/// browser is for. Gathering them also gives the one honest place to say what
/// each layer does and does not cover.
struct ScoutProtectionView: View {
  /// Set when the screen is presented as a sheet (from the new tab) rather
  /// than pushed inside Settings, where the back button already does this.
  var onDone: (() -> Void)?

  @State private var blocked = Preferences.ScoutBlocking.chosen
  @ObservedObject private var safeSearch = Preferences.Scout.safeSearch
  /// Re-read on every appearance rather than observed: rules and the log are
  /// written from the browser, not from this screen, so the counts only need
  /// to be right when someone is looking at them.
  @State private var allowedCount = 0
  @State private var blockedCount = 0
  @State private var recent: [BlockRecord] = []
  @State private var checkedCount = 0
  /// Read fresh each time the screen appears: the user may have just come back
  /// from changing it in iOS Settings.
  @State private var isDefaultBrowser = false

  var body: some View {
    List {
      Section {
        statusCard
          .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
          .listRowBackground(Color.clear)
      }

      Section(Strings.ScoutProtection.whatScoutBlocks) {
        NavigationLink {
          ScoutBlockingSettingsView()
        } label: {
          row(
            symbol: "hand.raised.fill",
            title: Strings.ScoutBlocking.settingsTitle,
            detail: String(
              format: Strings.ScoutProtection.categoriesSummary,
              blocked.count, ContentCategory.allCases.count)
          )
        }

        Toggle(isOn: $safeSearch.value) {
          row(
            symbol: "magnifyingglass",
            title: Strings.ScoutProtection.safeSearchTitle,
            detail: Strings.ScoutProtection.safeSearchDetail
          )
        }
        .tint(scoutViolet)
      }

      Section(Strings.ScoutProtection.beyondScout) {
        NavigationLink {
          ScoutDeviceFilterView()
        } label: {
          row(
            symbol: "iphone.gen3",
            title: Strings.ScoutBlocking.phoneFilterTitle,
            detail: Strings.ScoutBlocking.phoneFilterDetail
          )
        }
      }

      Section(Strings.ScoutProtection.yourDecisions) {
        NavigationLink {
          ScoutSiteListView(rule: .allow)
        } label: {
          countRow(
            symbol: "checkmark.circle.fill",
            tint: scoutMint,
            title: Strings.ScoutProtection.allowedSites,
            count: allowedCount)
        }
        NavigationLink {
          ScoutSiteListView(rule: .block)
        } label: {
          countRow(
            symbol: "minus.circle.fill",
            tint: scoutViolet,
            title: Strings.ScoutProtection.blockedSites,
            count: blockedCount)
        }
      }

      recentSection
    }
    .listStyle(.insetGrouped)
    .navigationTitle(Strings.ScoutProtection.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let onDone {
        ToolbarItem(placement: .topBarTrailing) {
          Button(Strings.done, action: onDone)
        }
      }
    }
    .onAppear(perform: refresh)
    .onChange(of: blocked) { _, new in
      Preferences.ScoutBlocking.chosen = new
    }
  }

  private func refresh() {
    let services = ScoutServices.shared
    blocked = Preferences.ScoutBlocking.chosen
    allowedCount = services.siteRules.sites(.allow).count
    blockedCount = services.siteRules.sites(.block).count
    recent = services.blockLog.entries
    checkedCount = services.checkedSiteCount
    // "Scout is checking every site" is only true when the system hands Scout
    // the links. Until then this screen says the narrower thing that is
    // actually true, rather than promising cover the browser doesn't have.
    let helper = DefaultBrowserHelper()
    helper.performAccurateDefaultCheckNow()
    isDefaultBrowser = helper.status == .defaulted
  }

  // MARK: - The status card

  /// What Scout has actually done, up front.
  ///
  /// A check that passes leaves no trace: the page just opens, exactly as it
  /// would in any browser. Without a count of them the only visible evidence
  /// of the product working is the times it got in the way.
  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: isDefaultBrowser ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
          .font(.system(size: 26))
          .foregroundStyle(isDefaultBrowser ? scoutMint : scoutAmber)
        Text(
          isDefaultBrowser
            ? Strings.ScoutProtection.statusHeadline
            : Strings.ScoutProtection.statusNotDefault
        )
          .font(.headline)
          .foregroundStyle(.white)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      HStack(spacing: 0) {
        statistic(checkedCount, Strings.ScoutProtection.statusChecked)
        divider
        statistic(recent.count, Strings.ScoutProtection.statusBlocked)
        divider
        statistic(allowedCount, Strings.ScoutProtection.statusAllowed)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(scoutViolet, in: .rect(cornerRadius: 18, style: .continuous))
  }

  private var divider: some View {
    Rectangle()
      .fill(.white.opacity(0.2))
      .frame(width: 1, height: 28)
  }

  private func statistic(_ value: Int, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text("\(value)")
        .font(.title2.weight(.semibold).monospacedDigit())
        .foregroundStyle(.white)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.75))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Recently blocked

  @ViewBuilder private var recentSection: some View {
    Section {
      if recent.isEmpty {
        Text(Strings.ScoutProtection.nothingBlocked)
          .font(.subheadline)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
      } else {
        ForEach(recent.prefix(5)) { BlockRecordRow(record: $0) }
        if recent.count > 5 {
          NavigationLink(Strings.ScoutProtection.seeAll) {
            ScoutBlockLogView()
          }
          .foregroundStyle(scoutViolet)
        }
      }
    } header: {
      Text(Strings.ScoutProtection.recentlyBlocked)
    } footer: {
      Text(Strings.ScoutProtection.recentlyBlockedFooter)
    }

    // Its own section, not part of the list above: that one is blocks,
    // instantly and offline. This is everything, including what was allowed
    // and what was decided without a fresh check.
    Section {
      NavigationLink {
        ScoutActivityView()
      } label: {
        row(
          symbol: "list.bullet.rectangle",
          title: Strings.ScoutProtection.activityTitle,
          detail: Strings.ScoutProtection.activityFooter
        )
      }
    }
  }

  // MARK: - Row shapes

  private func row(symbol: String, title: String, detail: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 17))
        .foregroundStyle(scoutViolet)
        .frame(width: 26)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func countRow(symbol: String, tint: Color, title: String, count: Int) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 17))
        .foregroundStyle(tint)
        .frame(width: 26)
      Text(title)
      Spacer(minLength: 8)
      Text("\(count)")
        .font(.body.monospacedDigit())
        .foregroundStyle(Color(braveSystemName: .textSecondary))
    }
  }
}

// MARK: - One blocked navigation

struct BlockRecordRow: View {
  let record: BlockRecord

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: record.continued ? "arrow.turn.down.right" : "hand.raised.fill")
        .font(.system(size: 15))
        .foregroundStyle(record.continued ? Color(braveSystemName: .textSecondary) : scoutViolet)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(record.site)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(Self.why(record))
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text(record.date, format: .relative(presentation: .numeric))
          .font(.caption2)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
        if record.continued {
          Text(Strings.ScoutProtection.continuedAnyway)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color(braveSystemName: .textSecondary))
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// Why this navigation was stopped, in the words the user chose it in. A
  /// category block names the category, because "blocked" alone tells a
  /// parent nothing about whether their settings are doing what they wanted.
  static func why(_ record: BlockRecord) -> String {
    switch record.reason {
    case .category, .address:
      let names = record.categories.map(\.title).sorted()
      return names.isEmpty ? Strings.ScoutProtection.blockedReasonUnsafe : ListFormatter
        .localizedString(byJoining: names)
    case .security: return Strings.ScoutProtection.blockedReasonUnsafe
    case .policyList: return Strings.ScoutProtection.blockedReasonYourList
    case .unavailable: return Strings.ScoutProtection.blockedReasonUnchecked
    case .scheme: return Strings.ScoutProtection.blockedReasonLinkType
    }
  }
}

/// The full list, when five rows on the Protection screen aren't enough.
struct ScoutBlockLogView: View {
  @State private var recent: [BlockRecord] = []

  var body: some View {
    List {
      Section {
        if recent.isEmpty {
          Text(Strings.ScoutProtection.nothingBlocked)
            .font(.subheadline)
            .foregroundStyle(Color(braveSystemName: .textSecondary))
        } else {
          ForEach(recent) { BlockRecordRow(record: $0) }
        }
      } footer: {
        Text(Strings.ScoutProtection.recentlyBlockedFooter)
      }

      if !recent.isEmpty {
        Section {
          Button(Strings.ScoutProtection.clearList, role: .destructive) {
            ScoutServices.shared.blockLog.removeAll()
            recent = []
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(Strings.ScoutProtection.recentlyBlocked)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { recent = ScoutServices.shared.blockLog.entries }
  }
}

extension UIColor {
  /// Scout's brand colours for UIKit surfaces (the URL bar's status mark).
  static let scoutViolet = UIColor(red: 0x54 / 255, green: 0x40 / 255, blue: 0x96 / 255, alpha: 1)
  static let scoutMint = UIColor(red: 0x4E / 255, green: 0xA3 / 255, blue: 0x80 / 255, alpha: 1)
}
