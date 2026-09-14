// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveShields
import BraveStrings
import BraveUI
import Foundation
import Preferences
import Scout
import Shared
import SwiftUI
import UIKit

class StatsSectionProvider: NSObject, NTPSectionProvider {
  private let isPrivateBrowsing: Bool
  var openProtectionPressed: () -> Void
  var hidePrivacyHubPressed: () -> Void

  init(
    isPrivateBrowsing: Bool,
    openProtectionPressed: @escaping () -> Void,
    hidePrivacyHubPressed: @escaping () -> Void
  ) {
    self.isPrivateBrowsing = isPrivateBrowsing
    self.openProtectionPressed = openProtectionPressed
    self.hidePrivacyHubPressed = hidePrivacyHubPressed
  }

  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    return Preferences.NewTabPage.showNewTabPrivacyHub.value ? 1 : 0
  }

  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(StatsNTPWidgetCell.self)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(for: indexPath) as StatsNTPWidgetCell
    cell.contentConfiguration = UIHostingConfiguration {
      StatsNTPWidget(
        isPrivateBrowsing: isPrivateBrowsing
      ) { [weak self] in
        self?.openProtectionPressed()
      } hidePrivacyHubPressed: { [weak self] in
        self?.hidePrivacyHubPressed()
      }
      .frame(maxWidth: 640)
      .fixedSize(horizontal: false, vertical: true)
    }
    .margins(.all, 0)
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    var size = fittingSizeForCollectionView(collectionView, section: indexPath.section)
    size.height = 110
    return size
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {
    let insets = horizontalInsets(for: collectionView, maxWidth: 640, minimumInset: 16)
    return UIEdgeInsets(top: 8, left: insets.left, bottom: 8, right: insets.right)
  }
}

class StatsNTPWidgetCell: UICollectionViewCell, CollectionViewReusable {
  override func preferredLayoutAttributesFitting(
    _ layoutAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutAttributes {
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
    attributes.size.height =
      systemLayoutSizeFitting(
        layoutAttributes.size,
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
      ).height
    return attributes
  }
}

/// The new tab's summary of what Scout has done.
///
/// Brave's version of this widget counts trackers and ads it removed from
/// inside pages. That is real work, but it isn't what Scout is for, and it
/// left the browser's actual job — deciding whether a site should open at
/// all — with no presence on the screen someone sees most often. These are
/// Scout's own numbers, and tapping them opens Settings → Protection.
struct StatsNTPWidget: View {
  var isPrivateBrowsing: Bool

  var openProtectionPressed: () -> Void
  var hidePrivacyHubPressed: () -> Void

  /// Read once, when the new tab appears. These change on navigation, not
  /// while a new tab sits on screen.
  @State private var checked = 0
  @State private var blocked = 0
  @State private var allowed = 0

  private struct StatLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
      VStack(spacing: 2) {
        configuration.content
          .font(.title2)
        configuration.label
          .font(.caption)
          .foregroundStyle(.white)
        // Pushes the label up so every column is as tall as the tallest,
        // which is what keeps the three figures on one line once a label
        // wraps at larger text sizes and its neighbours do not.
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
    }
  }

  private struct StatsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .osAvailabilityModifiers { content in
          if #available(iOS 26.0, *) {
            content
              .glassEffect(.regular.interactive(isEnabled), in: .rect(cornerRadius: 16))
          } else {
            content
              .background(.thinMaterial, in: .rect(cornerRadius: 16))
              .animation(.spring(response: 0.3, dampingFraction: 0.8)) { content in
                content.scaleEffect(configuration.isPressed ? 0.95 : 1)
              }
          }
        }
    }
  }

  var body: some View {
    Button {
      openProtectionPressed()
    } label: {
      VStack(spacing: 8) {
        Label(Strings.ScoutProtection.title, systemImage: "checkmark.shield.fill")
          .foregroundStyle(.white)
          .font(.footnote.weight(.semibold))
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack(alignment: .top) {
          LabeledContent {
            Text(checked.kFormattedNumber)
              .foregroundStyle(.white)
          } label: {
            Text(Strings.ScoutProtection.statusChecked)
          }
          LabeledContent {
            Text(blocked.kFormattedNumber)
              .foregroundStyle(Color(braveSystemName: .primitiveOrange70))
          } label: {
            Text(Strings.ScoutProtection.statusBlocked)
          }
          LabeledContent {
            Text(allowed.kFormattedNumber)
              .foregroundStyle(Color(braveSystemName: .primitiveBlurple70))
          } label: {
            Text(Strings.ScoutProtection.statusAllowed)
          }
        }
        .labeledContentStyle(StatLabeledContentStyle())
      }
      .padding()
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(StatsButtonStyle())
    .colorScheme(.dark)
    .contextMenu {
      Button {
        hidePrivacyHubPressed()
      } label: {
        Label(Strings.PrivacyHub.hidePrivacyHubWidgetActionTitle, braveSystemImage: "leo.eye.off")
      }
    }
    .disabled(isPrivateBrowsing)
    .dynamicTypeSize(.xSmall..<DynamicTypeSize.xLarge)
    .onAppear {
      let services = ScoutServices.shared
      checked = services.checkedSiteCount
      blocked = services.blockedSiteCount
      allowed = services.siteRules.sites(.allow).count
    }
  }
}
