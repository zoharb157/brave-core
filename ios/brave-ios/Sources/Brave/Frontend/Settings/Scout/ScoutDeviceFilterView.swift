// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveShared
import DesignSystem
import Onboarding
import Strings
import SwiftUI

/// Turns the phone-wide DNS filter on and off, and says plainly what it does
/// and doesn't cover.
struct ScoutDeviceFilterView: View {
  @StateObject private var filter = ScoutDNSFilter.shared
  @Environment(\.scenePhase) private var scenePhase
  @State private var isWorking = false

  private var isOn: Binding<Bool> {
    Binding(
      get: { filter.state == .on || filter.state == .needsApproval },
      set: { wanted in
        isWorking = true
        Task {
          if wanted { await filter.enable() } else { await filter.disable() }
          isWorking = false
        }
      }
    )
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          Toggle(isOn: isOn) {
            Text(Strings.ScoutBlocking.phoneFilterTitle)
              .font(.headline)
          }
          .disabled(isWorking)
          Text(Strings.ScoutBlocking.phoneFilterDetail)
            .font(.subheadline)
            .foregroundStyle(Color(braveSystemName: .textSecondary))
          status
        }
        .padding(16)
        .background(Color(braveSystemName: .containerBackground).cornerRadius(12))

        Text(Strings.ScoutBlocking.phoneFilterFootnote)
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .padding(.horizontal, 4)
      }
      .padding(16)
    }
    .foregroundStyle(Color(braveSystemName: .textPrimary))
    .background(Color(braveSystemName: .pageBackground))
    .navigationTitle(Strings.ScoutBlocking.phoneFilterTitle)
    .navigationBarTitleDisplayMode(.inline)
    .task { await filter.refresh() }
    // Choosing Scout happens in Settings, so the answer changes while this
    // screen is off-screen. Without this it kept saying "almost there" after
    // the person had already done it.
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await filter.refresh() }
    }
  }

  @ViewBuilder private var status: some View {
    switch filter.state {
    case .needsApproval:
      label(
        Strings.ScoutBlocking.phoneFilterApprovalNeeded, systemImage: "exclamationmark.circle",
        tint: scoutAmber)
    case .on:
      label(Strings.ScoutBlocking.phoneFilterOn, systemImage: "checkmark.circle", tint: scoutMint)
    case .failed:
      // The system's own wording ("IPC failed") means nothing to a parent.
      VStack(alignment: .leading, spacing: 8) {
        label(
          Strings.ScoutBlocking.phoneFilterFailed, systemImage: "exclamationmark.triangle",
          tint: scoutRose)
        // Turning this on can fail for reasons that pass — no network when the
        // profile is installed, another DNS profile briefly winning. Saying so
        // and stopping there leaves a parent with the most important setting in
        // the app switched off and nothing to press.
        Button(Strings.ScoutProtection.activityRetry) {
          isWorking = true
          Task {
            await filter.enable()
            isWorking = false
          }
        }
        .buttonStyle(.plain)
        .font(.footnote.weight(.medium))
        .foregroundStyle(scoutViolet)
        .disabled(isWorking)
      }
    case .off:
      EmptyView()
    }
  }

  /// Status carries its own colour: a failure styled like a success is read as
  /// one, and this row is the only thing that says whether the filter is up.
  private func label(_ text: String, systemImage: String, tint: Color) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
      Text(text)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
    }
    .font(.footnote)
  }
}
