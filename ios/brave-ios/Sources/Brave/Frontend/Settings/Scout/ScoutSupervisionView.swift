// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Preferences
import Scout
import Shared
import Strings
import SwiftUI

/// Turning supervision on, handing a parent a code, and taking it back.
///
/// Everything here happens on the phone being supervised. There is no way in
/// from the parent's side, by design — the only lever that ends a watch belongs
/// to the phone it is watching.
struct ScoutSupervisionView: View {
  @ObservedObject private var supervised = Preferences.Scout.supervised
  @State private var code: String?
  @State private var isWorking = false
  @State private var failedToMakeCode = false
  @State private var askingPIN = false
  @State private var settingPIN = false

  var body: some View {
    List {
      if supervised.value {
        pairingSection
        endingSection
      } else {
        invitationSection
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(Strings.ScoutProtection.supervisionTitle)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $settingPIN) {
      ScoutPINSheet(mode: .set) { pin in
        ScoutSupervision.shared.turnOn(pin: pin)
        Task { await refreshCode() }
      }
    }
    .sheet(isPresented: $askingPIN) {
      ScoutPINSheet(mode: .confirm) { _ in
        Task {
          isWorking = true
          await ScoutSupervision.shared.turnOff()
          code = nil
          isWorking = false
        }
      }
    }
    .task { if supervised.value, code == nil { await refreshCode() } }
  }

  // MARK: - Off

  @ViewBuilder private var invitationSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Text(Strings.ScoutProtection.supervisionDetail)
          .font(.subheadline)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .fixedSize(horizontal: false, vertical: true)
        Button(Strings.ScoutProtection.supervisionTurnOn) { settingPIN = true }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(scoutViolet)
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - On

  @ViewBuilder private var pairingSection: some View {
    Section(Strings.ScoutProtection.supervisionCodeTitle) {
      VStack(alignment: .leading, spacing: 10) {
        if let code {
          Text(code)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .kerning(6)
            .foregroundStyle(scoutViolet)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(code.map(String.init).joined(separator: " "))
        } else if isWorking {
          ProgressView().frame(maxWidth: .infinity)
        }
        if failedToMakeCode {
          Text(Strings.ScoutProtection.supervisionCodeFailed)
            .font(.caption)
            .foregroundStyle(scoutRose)
        }
        Text(
          String(
            format: Strings.ScoutProtection.supervisionCodeDetail, ScoutSupervision.watchURL)
        )
        .font(.caption)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
        .fixedSize(horizontal: false, vertical: true)
        Button(Strings.ScoutProtection.supervisionNewCode) { Task { await refreshCode() } }
          .font(.subheadline.weight(.medium))
          .foregroundStyle(scoutViolet)
          .disabled(isWorking)
      }
      .padding(.vertical, 4)
    }
  }

  @ViewBuilder private var endingSection: some View {
    Section {
      Button(Strings.ScoutProtection.supervisionStopSharing) {
        Task {
          isWorking = true
          await ScoutSupervision.shared.stopSharing()
          isWorking = false
        }
      }
      .foregroundStyle(scoutRose)
      .disabled(isWorking)

      Button(Strings.ScoutProtection.supervisionTurnOff) { askingPIN = true }
        .foregroundStyle(scoutRose)
    } footer: {
      Text(Strings.ScoutProtection.supervisionStopSharingDetail)
    }
  }

  private func refreshCode() async {
    isWorking = true
    failedToMakeCode = false
    let fresh = await ScoutSupervision.shared.pairingCode()
    code = fresh
    failedToMakeCode = fresh == nil
    isWorking = false
  }
}

/// Asks for a PIN, either setting a new one or checking the one on file.
struct ScoutPINSheet: View {
  enum Mode { case set, confirm }

  let mode: Mode
  let onDone: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var first = ""
  @State private var second = ""
  @State private var problem: String?

  var body: some View {
    NavigationView {
      List {
        Section {
          SecureField(
            mode == .set
              ? Strings.ScoutProtection.supervisionSetPIN
              : Strings.ScoutProtection.supervisionEnterPIN,
            text: $first
          )
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)

          if mode == .set {
            SecureField(Strings.ScoutProtection.supervisionConfirmPIN, text: $second)
              .keyboardType(.numberPad)
              .textContentType(.oneTimeCode)
          }
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            if let problem {
              Text(problem).foregroundStyle(scoutRose)
            }
            if mode == .set {
              Text(Strings.ScoutProtection.supervisionPINDetail)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle(
        mode == .set
          ? Strings.ScoutProtection.supervisionSetPIN
          : Strings.ScoutProtection.supervisionEnterPIN
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Strings.CancelString) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(Strings.done) { submit() }.disabled(first.count < 4)
        }
      }
    }
  }

  /// "5 minutes", "1 minute", "30 seconds" — enough to know whether to wait
  /// or put the phone down.
  private static func spell(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds < 60 ? [.second] : [.minute]
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 1
    return formatter.string(from: max(seconds, 1)) ?? "a moment"
  }

  private func submit() {
    switch mode {
    case .set:
      guard first == second else {
        problem = Strings.ScoutProtection.supervisionPINMismatch
        return
      }
      onDone(first)
      dismiss()
    case .confirm:
      // Ask about the wait before trying, so the message can be true. A
      // locked attempt is refused without the PIN being read at all, and
      // reporting that as "wrong PIN" would both mislead and leave someone
      // tapping a button that cannot succeed yet.
      let wait = ScoutSupervision.shared.pinWait
      guard wait == 0 else {
        problem = String(
          format: Strings.ScoutProtection.supervisionPINWait, Self.spell(wait))
        return
      }
      guard ScoutSupervision.shared.verify(pin: first) else {
        problem = Strings.ScoutProtection.supervisionWrongPIN
        return
      }
      onDone(first)
      dismiss()
    }
  }
}
