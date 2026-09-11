// Copyright (c) 2025 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

struct DefaultBrowserActions: View {
  @Environment(\.windowScene) private var windowScene

  var continueHandler: () -> Void
  var body: some View {
    HStack {
      Button {
        continueHandler()
      } label: {
        Text(Strings.FocusOnboarding.notNowActionButtonTitle)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .buttonStyle(.outline)
      Button {
        Task {
          if let openSettingsURL = URL(string: UIApplication.openSettingsURLString) {
            if let windowScene {
              await DefaultBrowserPictureInPictureController.present(in: windowScene)
            }
            await UIApplication.shared.open(openSettingsURL)
          }
          continueHandler()
        }
      } label: {
        Text(Strings.FocusOnboarding.systemSettingsButtonTitle)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .primaryContinueAction()
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

public struct DefaultBrowserOnboardingStep: OnboardingStep {
  public var id: String = "default-browsing"
  public func makeTitle() -> some View {
    OnboardingTitleView(
      title: Strings.FocusOnboarding.defaultBrowserScreenTitle,
      subtitle: Strings.FocusOnboarding.defaultBrowserScreenDescription
    )
  }
  public func makeGraphic() -> some View {
    ScoutDefaultBrowserIllustration()
  }
  public func makeActions(continueHandler: @escaping () -> Void) -> some View {
    DefaultBrowserActions(continueHandler: continueHandler)
      .prepareWindowSceneEnvironment()
  }
}

extension OnboardingStep where Self == DefaultBrowserOnboardingStep {
  public static var defaultBrowsing: Self { .init() }
}

#if DEBUG
#Preview {
  OnboardingStepView(step: .defaultBrowsing)
}
#endif
