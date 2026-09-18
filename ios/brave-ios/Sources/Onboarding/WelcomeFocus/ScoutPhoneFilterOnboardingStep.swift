// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveShared
import DesignSystem
import SwiftUI

/// Offers the phone-wide filter during setup.
///
/// It was only ever reachable through Settings, several screens deep — so the
/// one protection that reaches past the browser was the one nobody switched
/// on. Every other app opens links in its own browser where Scout never sees
/// them; this is the only thing that covers those, and setup is the moment a
/// parent is actually thinking about it.
///
/// Skippable, and it has to be: turning it on hands the decision to iOS, which
/// asks for its own approval afterwards.
public struct ScoutPhoneFilterOnboardingStep: OnboardingStep {
  public var id: String = "scout-phone-filter"

  public func makeTitle() -> some View {
    OnboardingTitleView(
      title: Strings.ScoutBlocking.phoneFilterTitle,
      subtitle: Strings.ScoutBlocking.phoneFilterDetail
    )
  }

  public func makeGraphic() -> some View {
    ScoutPhoneFilterGraphicView()
  }

  public func makeActions(continueHandler: @escaping () -> Void) -> some View {
    ScoutPhoneFilterActions(continueHandler: continueHandler)
  }
}

extension OnboardingStep where Self == ScoutPhoneFilterOnboardingStep {
  public static var scoutPhoneFilter: Self { .init() }
}

// MARK: - Graphic

private let scoutViolet = Color.scoutAccent
private let scoutMint = Color(red: 0x7E / 255, green: 0xC8 / 255, blue: 0xA8 / 255)

/// What the filter does, drawn: other apps sit outside Scout, and the filter is
/// the ring that goes around all of them.
private struct ScoutPhoneFilterGraphicView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var settled = false

  private static let apps: [(symbol: String, angle: Double)] = [
    ("message.fill", -90),
    ("envelope.fill", -18),
    ("play.rectangle.fill", 54),
    ("bubble.left.and.bubble.right.fill", 126),
    ("app.badge.fill", 198),
  ]

  /// Apps sit inside; the filter is the ring drawn around all of them.
  private static let appRadius: CGFloat = 78
  private static let ringDiameter: CGFloat = 232

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(scoutMint.opacity(0.5), style: .init(lineWidth: 2, dash: [5, 7]))
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
        .scaleEffect(settled ? 1 : 1.3)
        .opacity(settled ? 1 : 0)

      ForEach(Array(Self.apps.enumerated()), id: \.offset) { index, app in
        Image(systemName: app.symbol)
          .font(.system(size: 19))
          .foregroundStyle(scoutViolet.opacity(0.7))
          .frame(width: 44, height: 44)
          .background(
            Color(braveSystemName: .containerBackground),
            in: .rect(cornerRadius: 12, style: .continuous)
          )
          // Counter-rotate the icon, offset it, then orbit the whole thing:
          // the outer rotation carries the icon around the circle and undoes
          // the inner one, so it arrives upright.
          .rotationEffect(.degrees(-app.angle))
          .offset(x: Self.appRadius)
          .rotationEffect(.degrees(app.angle))
          .opacity(settled ? 1 : 0)
          .scaleEffect(settled ? 1 : 0.6)
          .animation(
            reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)
              .delay(0.3 + Double(index) * 0.06),
            value: settled
          )
      }

      Image(systemName: "checkmark.shield.fill")
        .font(.system(size: 42))
        .foregroundStyle(scoutViolet)
        .scaleEffect(settled ? 1 : 0.7)
        .opacity(settled ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75), value: settled)
    .onAppear { settled = true }
    .accessibilityElement()
    .accessibilityLabel(Strings.ScoutBlocking.phoneFilterTitle)
  }
}

// MARK: - Actions

private struct ScoutPhoneFilterActions: View {
  let continueHandler: () -> Void

  @ObservedObject private var filter = ScoutDNSFilter.shared
  @State private var isWorking = false

  var body: some View {
    VStack(spacing: 12) {
      switch filter.state {
      case .on, .needsApproval:
        // iOS asks for its own approval after this, so the wording stops short
        // of claiming it is already running.
        Label(
          filter.state == .on
            ? Strings.ScoutBlocking.phoneFilterOn : Strings.ScoutBlocking.phoneFilterApprovalNeeded,
          systemImage: "checkmark.circle.fill"
        )
        .font(.footnote)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

        Button(action: continueHandler) {
          Text(Strings.FocusOnboarding.continueButtonTitle)
            .frame(maxWidth: .infinity)
        }
        .primaryContinueAction()

      case .failed:
        Text(Strings.ScoutBlocking.phoneFilterFailed)
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        Button(action: continueHandler) {
          Text(Strings.FocusOnboarding.continueButtonTitle)
            .frame(maxWidth: .infinity)
        }
        .primaryContinueAction()

      case .off:
        Button {
          isWorking = true
          Task {
            await ScoutDNSFilter.shared.enable()
            isWorking = false
          }
        } label: {
          Text(Strings.ScoutBlocking.phoneFilterTurnOn)
            .frame(maxWidth: .infinity)
        }
        .disabled(isWorking)
        .primaryContinueAction()

        Button(action: continueHandler) {
          Text(Strings.ScoutBlocking.phoneFilterNotNow)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
        .font(.subheadline)
      }

      Text(Strings.ScoutBlocking.phoneFilterFootnote)
        .font(.caption2)
        .foregroundStyle(Color(braveSystemName: .textTertiary))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .task { await ScoutDNSFilter.shared.refresh() }
  }
}

#if DEBUG
#Preview {
  OnboardingStepView(step: .scoutPhoneFilter)
}
#endif
