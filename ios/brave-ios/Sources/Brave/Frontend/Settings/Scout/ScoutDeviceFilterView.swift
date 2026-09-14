// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import Onboarding
import Strings
import SwiftUI

/// Turns the phone-wide DNS filter on and off, and says plainly what it does
/// and doesn't cover.
struct ScoutDeviceFilterView: View {
  @StateObject private var filter = ScoutDNSFilter.shared
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
  }

  @ViewBuilder private var status: some View {
    switch filter.state {
    case .needsApproval:
      label(Strings.ScoutBlocking.phoneFilterApprovalNeeded, systemImage: "exclamationmark.circle")
    case .on:
      label(Strings.ScoutBlocking.phoneFilterOn, systemImage: "checkmark.circle")
    case .failed:
      // The system's own wording ("IPC failed") means nothing to a parent.
      label(Strings.ScoutBlocking.phoneFilterFailed, systemImage: "exclamationmark.triangle")
    case .off:
      EmptyView()
    }
  }

  private func label(_ text: String, systemImage: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: systemImage)
      Text(text)
    }
    .font(.footnote)
    .foregroundStyle(Color(braveSystemName: .textSecondary))
  }
}
