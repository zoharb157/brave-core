// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShared
import BraveShields
import BraveUI
import Combine
import Data
import DesignSystem
import Favicon
import Shared
import SnapKit
import Strings
import SwiftUI
import Web

struct ShieldsPanelView: View {
  enum Action {
    enum NavigationTarget {
      case shareStats
      case reportBrokenSite
      case globalShields
    }
    case navigate(NavigationTarget, dismiss: Bool)
    case changedShieldSettings
    case shredSiteData
    /// The user set or cleared a standing decision about this site, so the
    /// page has to be loaded again under it.
    case changedSiteRule
  }

  private let url: URL
  private var tab: any TabState
  private let displayHost: String
  @AppStorage("advancedShieldsExpanded") private var advancedShieldsExpanded = false
  @ObservedObject private var viewModel: ShieldsPanelViewModel
  private var actionCallback: (Action) -> Void

  @MainActor init(
    url: URL,
    tab: some TabState,
    domain: Domain,
    isAdvancedControlsEnabled: Bool,
    callback: @escaping (Action) -> Void
  ) {
    self.url = url
    self.tab = tab
    self.viewModel = ShieldsPanelViewModel(
      tab: tab,
      stats: tab.contentBlocker?.$stats.eraseToAnyPublisher()
        ?? Just(.init()).eraseToAnyPublisher(),
      blockedRequests: tab.contentBlocker?.$blockedRequests.map(Array.init)
        .eraseToAnyPublisher() ?? Just([]).eraseToAnyPublisher(),
      isAdvancedControlsEnabled: isAdvancedControlsEnabled
    )
    self.actionCallback = callback
    self.displayHost =
      "\u{200E}\(URLFormatter.formatURLOrigin(forDisplayOmitSchemePathAndTrivialSubdomains: url.strippingBlobURLAuth.absoluteString))"
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        siteHeaderView

        // Scout's own read on this site comes first: it is the reason the
        // browser exists, and it is the part that is otherwise invisible when
        // the answer is "this is fine". Brave's ad and tracker controls stay
        // below, unchanged.
        ScoutSitePanelView(url: url) { _ in
          actionCallback(.changedSiteRule)
        }

        adBlockingCard

        if viewModel.shieldsEnabled {
          Text(Strings.Shields.siteBroken)
            .font(.caption)
            .foregroundStyle(Color(braveSystemName: .textSecondary))
            .multilineTextAlignment(.leading)
            .padding(.horizontal)
            .padding(.bottom, viewModel.advancedControlsEnabled ? nil : 16)
          if viewModel.advancedControlsEnabled {
            DisclosureGroup(isExpanded: $advancedShieldsExpanded) {
              advancedShieldsSection
            } label: {
              Text(Strings.Shields.advancedControls)
                .foregroundStyle(Color(braveSystemName: .textPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)
            }.disclosureGroupStyle(ShieldsPanelDisclosureStyle())
          }
        } else {
          shieldsOffFooterView
        }
      }
      .padding(.top)
    }
    .background(Color(braveSystemName: .containerBackground))
    .frame(idealWidth: 360, alignment: .center)
    .toolbarVisibility(.hidden, for: .navigationBar)
  }

  /// The site this panel is about. Split out from the shields toggle so
  /// Scout's read on that site can sit directly under its name, where it
  /// answers the question the panel was opened to answer.
  @ViewBuilder @MainActor private var siteHeaderView: some View {
    HStack(alignment: .center, spacing: 8) {
      StyledFaviconImage(
        url: url.absoluteString,
        isPrivateBrowsing: viewModel.isPrivateBrowsing
      )
      URLElidedText(text: displayHost)
        .font(.title2)
        .foregroundStyle(Color(braveSystemName: .textPrimary))
    }
    .frame(minWidth: .zero, maxWidth: .infinity, alignment: .center)
    .padding(.horizontal)
  }

  /// Ad and tracker blocking, as one row.
  ///
  /// It used to open with a switch the size of a thumb, unlabelled until you
  /// read the caption under it — the largest thing in a panel opened to find
  /// out whether a site is safe, controlling the part of the panel that
  /// answers that question least. A setting that belongs to this site reads
  /// like the other per-site settings below it instead, and the number it
  /// blocked moves under it where it says what the setting is doing.
  @ViewBuilder @MainActor private var adBlockingCard: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        Image(braveSystemName: "leo.shield.done")
          .font(.body)
          .foregroundStyle(Color(braveSystemName: .iconDefault))
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(Strings.Shields.statusTitle)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(braveSystemName: .textPrimary))
          if viewModel.shieldsEnabled {
            Text(verbatim: "\(viewModel.stats.total) \(Strings.Shields.blockedCountLabel)")
              .font(.caption)
              .foregroundStyle(Color(braveSystemName: .textSecondary))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Toggle(Strings.Shields.statusTitle, isOn: $viewModel.shieldsEnabled)
          .labelsHidden()
          .tint(scoutViolet)
          .onChange(of: viewModel.shieldsEnabled) { _, _ in
            actionCallback(.changedShieldSettings)
          }
      }
      .padding(14)

      Divider().padding(.leading, 50)

      // The link owns only its own label; the Spacer and the trailing
      // controls sit in the row around it. A Spacer inside the label makes the
      // row's ideal width unbounded, and this panel is sized from its
      // content's preferred size — an unbounded one and it never appears.
      HStack(spacing: 12) {
        NavigationLink {
          AboutBraveShieldsView()
        } label: {
          HStack(spacing: 12) {
            Image(braveSystemName: "leo.help.outline")
              .font(.body)
              .foregroundStyle(Color(braveSystemName: .iconDefault))
              .frame(width: 24)
            Text(Strings.Shields.aboutBraveShieldsTitle)
              .font(.subheadline)
              .foregroundStyle(Color(braveSystemName: .textPrimary))
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)

        Spacer(minLength: 8)

        if viewModel.shieldsEnabled, viewModel.stats.total > 0 {
          Button {
            actionCallback(.navigate(.shareStats, dismiss: false))
          } label: {
            Image(braveSystemName: "leo.share")
              .font(.footnote)
              .foregroundStyle(Color(braveSystemName: .iconDefault))
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Strings.share)
        }

        Image(braveSystemName: "leo.carat.right")
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .iconDefault))
      }
      .padding(14)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(braveSystemName: .containerBackground),
      in: .rect(cornerRadius: 14, style: .continuous)
    )
    .padding(.horizontal)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var shieldsOffFooterView: some View {
    VStack(alignment: .center, spacing: 16) {
      Text(Strings.Shields.shieldsDownDisclaimer)
        .font(.caption)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
        .multilineTextAlignment(.leading)
      if ScoutFeatures.webcompatReporter {
        Button {
          actionCallback(.navigate(.reportBrokenSite, dismiss: true))
        } label: {
          Text(Strings.Shields.reportABrokenSite)
            .foregroundStyle(Color(braveSystemName: .textPrimary))
        }
        .buttonStyle(.outline)
        .frame(maxWidth: .infinity, alignment: .center)
      }
    }
    .padding(.horizontal)
    .padding(.bottom)
  }

  @ViewBuilder private var advancedShieldsSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      shieldSettingsSectionView
      globalSettingsSectionView
    }
    .padding(0)
  }

  @ViewBuilder private var shieldSettingsSectionView: some View {
    ShieldSettingSectionHeader(
      title: displayHost
    )
    ShieldSettingRow {
      HStack {
        Text(Strings.Shields.trackersAndAdsBlocking)
          .foregroundStyle(Color(braveSystemName: .textPrimary))
          .frame(maxWidth: .infinity, alignment: .leading)

        Picker(selection: $viewModel.blockAdsAndTrackingLevel) {
          ForEach(ShieldLevel.allCases) { level in
            Text(level.localizedTitle).tag(level)
          }
        } label: {
          // The label will not show outside of a form or list
          Text(Strings.Shields.trackersAndAdsBlocking)
        }
        .tint(Color(braveSystemName: .textSecondary))
        .buttonStyle(.plain)
        .padding(.horizontal, -10)
        .onChange(of: viewModel.blockAdsAndTrackingLevel) { _, newValue in
          actionCallback(.changedShieldSettings)
        }
      }
    }
    ShieldSettingRow {
      ToggleView(
        title: Strings.Shields.blockScripts,
        subtitle: nil,
        toggle: $viewModel.blockScripts
      ) { _ in
        actionCallback(.changedShieldSettings)
      }
    }
    ShieldSettingRow {
      ToggleView(
        title: Strings.Shields.fingerprintingProtection,
        subtitle: nil,
        toggle: $viewModel.fingerprintProtection
      ) { _ in
        actionCallback(.changedShieldSettings)
      }
    }
    if FeatureList.kBraveShredFeature.enabled {
      ShieldSettingRow {
        NavigationLink {
          ShredSiteSettingsView(
            viewModel: viewModel
          ) {
            actionCallback(.shredSiteData)
          }
        } label: {
          ShieldSettingsNavigationWrapper {
            HStack {
              Text(Strings.Shields.shredSiteData)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Color(braveSystemName: .textPrimary))
              Text(viewModel.autoShredLevel.localizedTitle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color(braveSystemName: .textSecondary))
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
      }
    }
    if FeatureList.kBraveIOSDebugAdblock.enabled {
      ShieldSettingRow {
        NavigationLink {
          AdblockBlockedRequestsView(
            url: url.baseDomain ?? url.absoluteDisplayString,
            blockedRequests: viewModel.blockedRequests
          )
        } label: {
          ShieldSettingsNavigationWrapper {
            Text(Strings.Shields.blockedRequestsTitle)
              .frame(maxWidth: .infinity, alignment: .leading)
              .multilineTextAlignment(.leading)
          }
        }
        .foregroundStyle(Color(braveSystemName: .textPrimary))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
      }
    }
  }

  @ViewBuilder private var globalSettingsSectionView: some View {
    ShieldSettingSectionHeader(title: Strings.Shields.globalControls)
    ShieldSettingRow {
      Button {
        actionCallback(.navigate(.globalShields, dismiss: true))
      } label: {
        ShieldSettingsNavigationWrapper {
          Label(
            Strings.Shields.globalChangeButton,
            braveSystemImage: "leo.globe.block"
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          .multilineTextAlignment(.leading)
          .foregroundStyle(Color(braveSystemName: .textPrimary))
          .labelStyle(.titleAndIcon)
        }
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct ShieldSettingRow<Contents>: View where Contents: View {
  @ViewBuilder var contents: () -> Contents

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      contents()
        .frame(minHeight: 32, alignment: .center)
        .padding(.horizontal)
        .padding(.vertical, 4)
      Divider()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct ShieldSettingsNavigationWrapper<Contents>: View where Contents: View {
  @ViewBuilder var contents: () -> Contents

  var body: some View {
    HStack {
      contents()
      // Hack to showing the navigation chevron
      Image(systemName: "chevron.right")
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
    }.contentShape(Rectangle())
  }
}

private struct ShieldSettingSectionHeader: View {
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      URLElidedText(text: title)
        .font(.footnote)
        .foregroundStyle(Color(braveSystemName: .textTertiary))
        .textCase(.uppercase)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 0)
      Divider()
    }.padding(.top, 8)
  }
}

class ShieldsPanelViewController: UIHostingController<ShieldsPanelView>, PopoverContentComponent {
  private let shieldsPanelView: ShieldsPanelView

  init(
    url: URL,
    tab: some TabState,
    domain: Domain,
    isAdvancedControlsEnabled: Bool = true,
    callback: @escaping (ShieldsPanelView.Action) -> Void
  ) {
    let shieldsPanelView = ShieldsPanelView(
      url: url,
      tab: tab,
      domain: domain,
      isAdvancedControlsEnabled: isAdvancedControlsEnabled,
      callback: callback
    )
    self.shieldsPanelView = shieldsPanelView
    super.init(rootView: shieldsPanelView)
  }

  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    sizingOptions = .preferredContentSize
  }
}

private struct ShieldsPanelDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation {
          configuration.isExpanded.toggle()
        }
      } label: {
        VStack(spacing: 0) {
          Divider()
          HStack {
            configuration.label
            Group {
              if configuration.isExpanded {
                Image(systemName: "chevron.down")
              } else {
                Image(systemName: "chevron.right")
              }
            }
            .foregroundStyle(Color(braveSystemName: .textSecondary))
            .font(.body)
          }
          .frame(maxWidth: .infinity, alignment: .center)
          .padding()
          .contentShape(Rectangle())
        }
      }
      .padding(0)
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .center)
      .background(Color(braveSystemName: .pageBackground))
      .hoverEffect()

      if configuration.isExpanded {
        configuration.content
      }
    }
  }
}
