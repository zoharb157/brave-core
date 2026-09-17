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
/// What a block looks like. The same rose the block page uses, so the page
/// that stopped a site and the list that records it agree on sight; the brand
/// violet cannot do this job because everything else on the screen is violet.
let scoutRose = Color(red: 0xB3 / 255, green: 0x62 / 255, blue: 0x6B / 255)

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
  /// The app's engine list, so the search row can check what the user's own
  /// default actually supports rather than describing the common case.
  var searchEngines: SearchEngines?

  @State private var blocked = Preferences.ScoutBlocking.chosen
  @ObservedObject private var safeSearch = Preferences.Scout.safeSearch
  @ObservedObject private var askWhenCheckFails = Preferences.Scout.askWhenCheckFails
  /// Re-read on every appearance rather than observed: rules and the log are
  /// written from the browser, not from this screen, so the counts only need
  /// to be right when someone is looking at them.
  @State private var allowedCount = 0
  @State private var blockedCount = 0
  @State private var recent: [BlockRecord] = []
  @State private var checkedCount = 0
  @State private var blockedTally = 0
  @State private var continuedTally = 0
  /// Supervision forces the ask-on-failed-check setting on, so the row has to
  /// say so rather than offer a choice that is not there. Read on appearance
  /// like the other state written from outside this screen.
  @State private var supervised = false
  /// Asking for the PIN before search filtering goes off.
  @State private var askingPINForSearch = false
  /// Read fresh each time the screen appears: the user may have just come back
  /// from changing it in iOS Settings.
  @State private var isDefaultBrowser = false
  /// The name of the default search engine when Scout cannot filter it, and
  /// nil when it can. Read on appearance because the engine is changed on a
  /// different screen.
  @State private var unfilterableEngine: String?

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

        Toggle(isOn: searchFilterBinding) {
          row(
            symbol: "magnifyingglass",
            // Amber, not rose: nothing is broken and nothing was blocked. The
            // setting simply cannot reach this one engine, which is the same
            // kind of unfinished the status card uses amber for.
            tint: unfilterableEngine == nil ? scoutViolet : scoutAmber,
            title: Strings.ScoutProtection.safeSearchTitle,
            detail: unfilterableEngine.map {
              String(format: Strings.ScoutProtection.safeSearchUnfilteredDetail, $0)
            } ?? Strings.ScoutProtection.safeSearchDetail
          )
        }
        .tint(scoutViolet)

        Toggle(isOn: supervised ? .constant(true) : $askWhenCheckFails.value) {
          row(
            symbol: "questionmark.circle",
            title: Strings.ScoutProtection.askWhenCheckFails,
            detail: supervised
              ? Strings.ScoutProtection.askWhenCheckFailsSupervised
              : Strings.ScoutProtection.askWhenCheckFailsDetail
          )
        }
        .disabled(supervised)
        .tint(scoutViolet)
      }

      Section(Strings.ScoutProtection.beyondScout) {
        NavigationLink {
          ScoutSupervisionView()
        } label: {
          row(
            symbol: "person.2",
            title: Strings.ScoutProtection.supervisionTitle,
            detail: Strings.ScoutProtection.supervisionDetail
          )
        }
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
            tint: scoutRose,
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
    .sheet(isPresented: $askingPINForSearch) {
      ScoutPINSheet(mode: .confirm) { _ in safeSearch.value = false }
    }
    .onChange(of: blocked) { _, new in
      Preferences.ScoutBlocking.chosen = new
    }
  }

  /// Switching search filtering off takes away search engines' safe modes and
  /// YouTube's Restricted Mode at once, so a supervised phone asks for the PIN
  /// first, as it does for a category. It used to switch with a tap. Turning
  /// it on is never gated.
  private var searchFilterBinding: Binding<Bool> {
    Binding(
      get: { safeSearch.value },
      set: { on in
        if !on, ScoutSupervision.shared.needsPIN(.relaxSearchFilter) {
          askingPINForSearch = true
        } else {
          safeSearch.value = on
        }
      })
  }

  private func refresh() {
    let services = ScoutServices.shared
    blocked = Preferences.ScoutBlocking.chosen
    allowedCount = services.siteRules.sites(.allow).count
    blockedCount = services.siteRules.sites(.block).count
    recent = services.blockLog.entries
    checkedCount = services.checkedSiteCount
    // Not `recent.count`: the list below is capped, so past that cap the card
    // would stop counting while blocks kept happening.
    blockedTally = services.blockedSiteCount
    // Not `allowedCount`: that is how many sites carry a standing "always
    // allow" rule, which is a different question and is usually zero. Beside
    // "Sites checked" and "Blocked" — both lifetime counts of what happened —
    // this slot has to be one too, or the row reads as three of a kind and
    // is not.
    continuedTally = Preferences.Scout.sitesContinued.value
    supervised = Preferences.Scout.supervised.value
    // "Scout is checking every site" is only true when the system hands Scout
    // the links. Until then this screen says the narrower thing that is
    // actually true, rather than promising cover the browser doesn't have.
    let helper = DefaultBrowserHelper()
    helper.performAccurateDefaultCheckNow()
    isDefaultBrowser = helper.status == .defaulted
    unfilterableEngine = unfilterableDefaultEngine()
  }

  /// The default engine's name when the setting cannot deliver what it
  /// promises for it, and nil when it can.
  ///
  /// Asked of the engine's own search URL rather than of a list of names kept
  /// here, so an engine added later is judged by the same rules that do the
  /// filtering, and a second list cannot drift out of step with the first.
  ///
  /// An engine that filters itself is deliberately not reported. Naver and
  /// Daum take no parameter because Korean law already excludes adult results
  /// for a signed-out user, so warning about them would push people off a
  /// working default for nothing.
  private func unfilterableDefaultEngine() -> String? {
    guard let engine = searchEngines?.defaultEngine(forType: .standard),
      let url = engine.searchURLForQuery("scout"),
      SafeSearch.coverage(of: url) == .unfiltered
    else { return nil }
    return engine.displayName
  }

  // MARK: - The status card

  /// What Scout has actually done, up front.
  ///
  /// A check that passes leaves no trace: the page just opens, exactly as it
  /// would in any browser. Without a count of them the only visible evidence
  /// of the product working is the times it got in the way.
  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Top-aligned: at accessibility text sizes the headline runs to four
      // lines, and a centred icon then floats in the middle of them.
      HStack(alignment: .top, spacing: 12) {
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
      // Top-aligned so the three figures sit on one line. Centred, each
      // column centres inside its own height, and at larger text sizes — where
      // "Sites checked" wraps but "Blocked" does not — the numbers stagger.
      HStack(alignment: .top, spacing: 0) {
        statistic(checkedCount, Strings.ScoutProtection.statusChecked)
        divider
        statistic(blockedTally, Strings.ScoutProtection.statusBlocked)
        divider
        statistic(continuedTally, Strings.ScoutProtection.statusAllowed)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(scoutViolet, in: .rect(cornerRadius: 18, style: .continuous))
  }

  /// Stretches to the tallest column rather than a fixed 28pt, which at
  /// larger text sizes left a stub floating beside two-line labels.
  private var divider: some View {
    Rectangle()
      .fill(.white.opacity(0.2))
      .frame(width: 1)
      .frame(maxHeight: .infinity)
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

  private func row(
    symbol: String, tint: Color = scoutViolet, title: String, detail: String
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 17))
        .foregroundStyle(tint)
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
        .foregroundStyle(record.continued ? Color(braveSystemName: .textSecondary) : scoutRose)
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
    // Said apart from "Unsafe", which is the check's own reading of a page.
    // This one was never opened: its address is already on a public list.
    case .knownThreat: return Strings.ScoutProtection.blockedReasonKnownThreat
    case .policyList: return Strings.ScoutProtection.blockedReasonYourList
    // Both of these are "couldn't be checked", and they are one row here on
    // purpose. The difference between them is what the address looked like
    // while nothing was checking it, which is a thing to say on the page that
    // stopped it, in the moment — not a second entry in a list whose job is to
    // tell a parent, at a glance, what their settings have been doing.
    case .unavailable, .uncheckedAddress: return Strings.ScoutProtection.blockedReasonUnchecked
    case .scheme: return Strings.ScoutProtection.blockedReasonLinkType
    // A certificate that does not check out is the site failing to prove it is
    // itself, which is what "unsafe" means on this screen.
    case .insecureCertificate: return Strings.ScoutProtection.blockedReasonUnsafe
    // The setting that stopped it, by the name it has on this screen.
    case .unfilteredSearch: return Strings.ScoutProtection.safeSearchTitle
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
