// Copyright (c) 2025 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Strings
import SwiftUI

public struct AddToDockOnboardingStep: OnboardingStep {
  public var id: String = "add-to-dock"
  public func makeTitle() -> some View {
    OnboardingTitleView(
      title: Strings.FocusOnboarding.addToDockScreenTitle,
      subtitle: Strings.FocusOnboarding.addToDockScreenDescription
    )
  }
  public func makeGraphic() -> some View {
    ScoutAddToDockIllustration()
  }
  public func makeActions(continueHandler: @escaping () -> Void) -> some View {
    Button {
      continueHandler()
    } label: {
      Text(Strings.FocusOnboarding.continueButtonTitle)
        .frame(maxWidth: .infinity)
    }
    .primaryContinueAction()
  }
}

extension OnboardingStep where Self == AddToDockOnboardingStep {
  public static var addToDock: Self { .init() }
}

#if DEBUG
#Preview {
  OnboardingStepView(step: .addToDock)
}
#endif
