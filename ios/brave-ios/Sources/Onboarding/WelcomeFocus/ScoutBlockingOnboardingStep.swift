// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import Preferences
import Scout
import SwiftUI

// MARK: - The user's choice

extension Preferences {
  /// What Scout blocks beyond unsafe links, as the user chose it in onboarding
  /// or Settings. The browser's navigation guard reads this on every decision
  /// (via `UserCategoryPolicy`), so a change applies to the next page load.
  public enum ScoutBlocking {
    public static let categories = Option<[String]>(
      key: "scout.blocked-categories",
      default: ContentCategory.wire(Policy.recommendedBlockedCategories)
    )

    public static var chosen: Set<ContentCategory> {
      get { ContentCategory.set(fromWire: categories.value) }
      set { categories.value = ContentCategory.wire(newValue) }
    }
  }
}

// MARK: - Copy

extension Strings {
  public struct ScoutBlocking {
    public static let screenTitle = NSLocalizedString(
      "scoutBlocking.screenTitle",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "What Should Scout Block?",
      comment: "Title of the onboarding screen where the user picks which kinds of sites to block"
    )
    public static let screenDescription = NSLocalizedString(
      "scoutBlocking.screenDescription",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Unsafe links are always blocked. Choose what else to keep out. You can change this anytime in Settings.",
      comment: "Subtitle of the onboarding screen where the user picks which kinds of sites to block"
    )
    public static let settingsTitle = NSLocalizedString(
      "scoutBlocking.settingsTitle",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Blocked Content",
      comment: "Settings row and screen title for choosing which kinds of sites Scout blocks"
    )
    public static let phoneFilterTitle = NSLocalizedString(
      "scoutBlocking.phoneFilterTitle",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Filter This Whole Phone",
      comment: "Title of the setting that filters every app on the device, not just Scout"
    )
    public static let phoneFilterDetail = NSLocalizedString(
      "scoutBlocking.phoneFilterDetail",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Other apps open links in their own browsers, where Scout can't check them. Turn this on and adult and unsafe sites are refused everywhere on the phone, in every app.",
      comment: "Explanation of the setting that filters every app on the device"
    )
    public static let phoneFilterApprovalNeeded = NSLocalizedString(
      "scoutBlocking.phoneFilterApprovalNeeded",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Almost there: open Settings › General › VPN, DNS & Device Management › DNS and choose Scout.",
      comment: "Shown when the device-wide filter is installed but iOS still needs the user to allow it"
    )
    public static let phoneFilterOn = NSLocalizedString(
      "scoutBlocking.phoneFilterOn",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "On. Every app on this phone is filtered.",
      comment: "Shown when the device-wide filter is active"
    )
    public static let phoneFilterFailed = NSLocalizedString(
      "scoutBlocking.phoneFilterFailed",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Scout couldn't set this up on this device.",
      comment: "Shown when the system refuses to install the device-wide filter"
    )
    public static let phoneFilterFootnote = NSLocalizedString(
      "scoutBlocking.phoneFilterFootnote",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "This filters by site name, so it is coarser than the checks inside Scout, and a few apps that bring their own settings can get around it.",
      comment: "Footnote setting expectations for the device-wide filter"
    )
    public static let settingsFooter = NSLocalizedString(
      "scoutBlocking.settingsFooter",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Scout checks each new site before it opens. You can always choose to continue to a blocked site.",
      comment: "Footer under the list of blockable content categories in Settings"
    )
    public static let alwaysOnTitle = NSLocalizedString(
      "scoutBlocking.alwaysOnTitle",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Unsafe links",
      comment: "Row title for the protection that can't be turned off"
    )
    public static let alwaysOnDetail = NSLocalizedString(
      "scoutBlocking.alwaysOnDetail",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Phishing, scams, and malware are always blocked.",
      comment: "Row description for the protection that can't be turned off"
    )
    public static let alwaysOnBadge = NSLocalizedString(
      "scoutBlocking.alwaysOnBadge",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Always on",
      comment: "Badge on the protection that can't be turned off"
    )
    static let adultTitle = NSLocalizedString(
      "scoutBlocking.adultTitle",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Adult content",
      comment: "Blockable category: pornography and explicit material"
    )
    static let adultDetail = NSLocalizedString(
      "scoutBlocking.adultDetail",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Pornography and explicit material.",
      comment: "Description of the adult content category"
    )
    static let gamblingTitle = NSLocalizedString(
      "scoutBlocking.gamblingTitle",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Gambling",
      comment: "Blockable category: betting and casino sites"
    )
    static let gamblingDetail = NSLocalizedString(
      "scoutBlocking.gamblingDetail",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Betting, casinos, and lotteries.",
      comment: "Description of the gambling category"
    )
    static let adsTitle = NSLocalizedString(
      "scoutBlocking.adsTitle",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Ad-heavy sites",
      comment: "Blockable category: whole pages that exist mainly to show ads"
    )
    static let adsDetail = NSLocalizedString(
      "scoutBlocking.adsDetail",
      tableName: "FocusOnboarding",
      bundle: .module,
      value: "Pages that exist mainly to show ads. Shields already removes ads inside pages.",
      comment: "Description of the ad-heavy sites category"
    )
  }
}

extension ContentCategory {
  public var title: String {
    switch self {
    case .adult: return Strings.ScoutBlocking.adultTitle
    case .gambling: return Strings.ScoutBlocking.gamblingTitle
    case .ads: return Strings.ScoutBlocking.adsTitle
    }
  }

  public var detail: String {
    switch self {
    case .adult: return Strings.ScoutBlocking.adultDetail
    case .gambling: return Strings.ScoutBlocking.gamblingDetail
    case .ads: return Strings.ScoutBlocking.adsDetail
    }
  }

  public var symbol: String {
    switch self {
    case .adult: return "eye.slash"
    case .gambling: return "suit.club"
    case .ads: return "rectangle.stack.badge.minus"
    }
  }
}

// MARK: - Picker

private let scoutViolet = Color(red: 0x54 / 255, green: 0x40 / 255, blue: 0x96 / 255)
private let scoutMint = Color(red: 0x7E / 255, green: 0xC8 / 255, blue: 0xA8 / 255)

/// Unsafe links are stated, not offered — security is never optional — then
/// one toggle per content category.
struct ScoutBlockingPicker: View {
  @Binding var blocked: Set<ContentCategory>

  var body: some View {
    VStack(spacing: 10) {
      alwaysOnRow
      ForEach(ContentCategory.allCases, id: \.self) { category in
        categoryRow(category)
      }
    }
  }

  private var alwaysOnRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark.shield.fill")
        .font(.system(size: 19))
        .foregroundStyle(scoutMint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.ScoutBlocking.alwaysOnTitle)
          .font(.headline)
        Text(Strings.ScoutBlocking.alwaysOnDetail)
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      Text(Strings.ScoutBlocking.alwaysOnBadge)
        .font(.caption.weight(.semibold))
        .foregroundStyle(scoutViolet)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(scoutMint.opacity(0.25), in: .capsule)
    }
    .padding(14)
    .background(scoutMint.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private func categoryRow(_ category: ContentCategory) -> some View {
    let isOn = Binding(
      get: { blocked.contains(category) },
      set: { on in
        if on { blocked.insert(category) } else { blocked.remove(category) }
      }
    )
    return Toggle(isOn: isOn) {
      HStack(spacing: 12) {
        Image(systemName: category.symbol)
          .font(.system(size: 18))
          .foregroundStyle(isOn.wrappedValue ? scoutViolet : Color(braveSystemName: .textSecondary))
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(category.title)
            .font(.headline)
          Text(category.detail)
            .font(.footnote)
            .foregroundStyle(Color(braveSystemName: .textSecondary))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .tint(scoutViolet)
    .padding(14)
    .background(
      Color(braveSystemName: .containerBackground),
      in: .rect(cornerRadius: 14, style: .continuous)
    )
  }
}

// MARK: - Onboarding step

struct ScoutBlockingGraphicView: View {
  @Bindable var state: ScoutBlockingOnboardingStep.State

  var body: some View {
    ScrollView {
      ScoutBlockingPicker(blocked: $state.blocked)
        .padding(20)
    }
    .scrollBounceBehavior(.basedOnSize)
    .foregroundStyle(Color(braveSystemName: .textPrimary))
  }
}

public struct ScoutBlockingOnboardingStep: OnboardingStep {
  @Observable class State {
    var blocked = Preferences.ScoutBlocking.chosen
  }
  public var id: String = "scout-blocking"
  private var state: State = .init()

  public func makeTitle() -> some View {
    OnboardingTitleView(
      title: Strings.ScoutBlocking.screenTitle,
      subtitle: Strings.ScoutBlocking.screenDescription
    )
  }
  public func makeGraphic() -> some View {
    ScoutBlockingGraphicView(state: state)
  }
  public func makeActions(continueHandler: @escaping () -> Void) -> some View {
    Button {
      Preferences.ScoutBlocking.chosen = state.blocked
      continueHandler()
    } label: {
      Text(Strings.FocusOnboarding.continueButtonTitle)
        .frame(maxWidth: .infinity)
    }
    .primaryContinueAction()
  }
}

extension OnboardingStep where Self == ScoutBlockingOnboardingStep {
  public static var scoutBlocking: Self { .init() }
}

// MARK: - Settings

/// Settings → Blocked Content: the same choice as onboarding, changed later.
public struct ScoutBlockingSettingsView: View {
  @ObservedObject private var categories = Preferences.ScoutBlocking.categories

  public init() {}

  public var body: some View {
    let blocked = Binding(
      get: { ContentCategory.set(fromWire: categories.value) },
      set: { categories.value = ContentCategory.wire($0) }
    )
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        ScoutBlockingPicker(blocked: blocked)
        Text(Strings.ScoutBlocking.settingsFooter)
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .padding(.horizontal, 4)
      }
      .padding(16)
    }
    .foregroundStyle(Color(braveSystemName: .textPrimary))
    .background(Color(braveSystemName: .pageBackground))
    .navigationTitle(Strings.ScoutBlocking.settingsTitle)
    .navigationBarTitleDisplayMode(.inline)
  }
}

#if DEBUG
#Preview {
  OnboardingStepView(step: .scoutBlocking)
}
#endif
