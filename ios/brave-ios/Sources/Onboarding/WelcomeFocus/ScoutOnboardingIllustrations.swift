// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

// Scout's onboarding artwork. These replace Brave's Lottie animations, whose
// Brave lion and "Brave" wordmark are baked into the vector shapes and cannot
// be recoloured or relabelled. Drawn in SwiftUI so they follow light/dark
// mode and every locale, and loop quietly (static under Reduce Motion).

private enum ScoutArt {
  static let appName = "Scout"
  static let violet = Color.scoutAccent
  static let violetLight = Color.scoutAccentLight
  static let mint = Color.scoutMint
  static let placeholder = Color(braveSystemName: .textSecondary).opacity(0.18)
  static let card = Color(braveSystemName: .containerBackground)
  static let ink = Color(braveSystemName: .textPrimary)
}

/// Runs `step` every `interval` until the view disappears.
private struct Looping: ViewModifier {
  var interval: Duration
  var step: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.task {
      guard !reduceMotion else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled else { return }
        step()
      }
    }
  }
}

// MARK: - Default browser

/// A Settings "Default Browser App" list; the check mark moves onto Scout.
struct ScoutDefaultBrowserIllustration: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var scoutChosen = false
  @State private var tapping = false

  private var isEnglish: Bool { Locale.current.language.languageCode == "en" }

  var body: some View {
    VStack(spacing: 18) {
      HStack {
        Image(systemName: "chevron.left")
          .font(.body.weight(.semibold))
          .foregroundStyle(ScoutArt.placeholder)
        Spacer()
        if isEnglish {
          Text(verbatim: "Default Browser App")
            .font(.headline)
            .foregroundStyle(ScoutArt.ink)
        } else {
          Capsule().fill(ScoutArt.placeholder).frame(width: 140, height: 12)
        }
        Spacer()
        Color.clear.frame(width: 12, height: 1)
      }
      .padding(.horizontal, 20)

      VStack(spacing: 0) {
        placeholderRow(width: 118, checked: !scoutChosen)
        divider
        scoutRow
        divider
        placeholderRow(width: 96, checked: false)
        divider
        placeholderRow(width: 132, checked: false)
      }
      .background(ScoutArt.card, in: .rect(cornerRadius: 14, style: .continuous))
      .padding(.horizontal, 16)
    }
    .padding(.vertical, 24)
    .frame(maxWidth: 360)
    .onAppear { if reduceMotion { scoutChosen = true } }
    .modifier(Looping(interval: .seconds(1.4)) { advance() })
    .accessibilityHidden(true)
  }

  private func advance() {
    if !scoutChosen && !tapping {
      withAnimation(.easeOut(duration: 0.25)) { tapping = true }
    } else if tapping {
      withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
        tapping = false
        scoutChosen = true
      }
    } else {
      withAnimation(.easeInOut(duration: 0.4)) { scoutChosen = false }
    }
  }

  private var divider: some View {
    Rectangle().fill(ScoutArt.placeholder).frame(height: 1).padding(.leading, 60)
  }

  private func placeholderRow(width: CGFloat, checked: Bool) -> some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(ScoutArt.placeholder)
        .frame(width: 32, height: 32)
      Capsule().fill(ScoutArt.placeholder).frame(width: width, height: 12)
      Spacer()
      checkmark(visible: checked)
    }
    .padding(.horizontal, 14)
    .frame(height: 52)
  }

  private var scoutRow: some View {
    HStack(spacing: 12) {
      BraveAppIcon(size: 32)
      Text(verbatim: ScoutArt.appName)
        .font(.body.weight(.medium))
        .foregroundStyle(ScoutArt.ink)
      Spacer()
      checkmark(visible: scoutChosen)
    }
    .padding(.horizontal, 14)
    .frame(height: 52)
    .background(ScoutArt.violet.opacity(tapping ? 0.14 : 0))
  }

  private func checkmark(visible: Bool) -> some View {
    Image(systemName: "checkmark")
      .font(.body.weight(.semibold))
      .foregroundStyle(ScoutArt.violet)
      .opacity(visible ? 1 : 0)
      .scaleEffect(visible ? 1 : 0.4)
  }
}

// MARK: - Add to dock

/// A home screen; the Scout icon lifts out of the grid and settles in the dock.
struct ScoutAddToDockIllustration: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var inDock = false

  private let tileColors: [Color] = [
    ScoutArt.violetLight.opacity(0.35), ScoutArt.mint.opacity(0.45), ScoutArt.placeholder,
    ScoutArt.placeholder, ScoutArt.mint.opacity(0.3), ScoutArt.violet.opacity(0.25),
    ScoutArt.placeholder, ScoutArt.violetLight.opacity(0.25), ScoutArt.mint.opacity(0.35),
    ScoutArt.placeholder, ScoutArt.violet.opacity(0.2),
  ]

  var body: some View {
    GeometryReader { proxy in
      // A 1:2 phone that fits the space in both directions.
      let phoneWidth = min(proxy.size.width * 0.62, proxy.size.height * 0.5, 230)
      let phone = CGSize(width: phoneWidth, height: phoneWidth * 2)
      let tile = phone.width / 6
      let gap = (phone.width - tile * 4) / 5
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
          .fill(Color(braveSystemName: .containerHighlight))
          .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
              .strokeBorder(ScoutArt.ink.opacity(0.7), lineWidth: 1.5)
          )

        // Grid: 3 rows of 4, the last slot is where Scout starts.
        ForEach(0..<12, id: \.self) { index in
          if index < tileColors.count {
            RoundedRectangle(cornerRadius: tile / 4.4, style: .continuous)
              .fill(tileColors[index])
              .frame(width: tile, height: tile)
              .offset(gridOffset(index, tile: tile, gap: gap))
          }
        }

        // Dock.
        RoundedRectangle(cornerRadius: tile / 2.2, style: .continuous)
          .fill(ScoutArt.card.opacity(0.9))
          .frame(width: phone.width - gap * 2, height: tile + gap * 1.6)
          .offset(x: gap, y: phone.height - tile - gap * 3.2)
        ForEach(0..<3, id: \.self) { index in
          RoundedRectangle(cornerRadius: tile / 4.4, style: .continuous)
            .fill(ScoutArt.placeholder)
            .frame(width: tile, height: tile)
            .offset(dockOffset(index, tile: tile, gap: gap, height: phone.height))
        }

        BraveAppIcon(size: tile)
          .scaleEffect(inDock ? 1 : 1.12)
          .shadow(color: ScoutArt.violet.opacity(inDock ? 0 : 0.35), radius: 8, y: 6)
          .offset(
            inDock
              ? dockOffset(3, tile: tile, gap: gap, height: phone.height)
              : gridOffset(11, tile: tile, gap: gap)
          )
      }
      .frame(width: phone.width, height: phone.height)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(.vertical, 24)
    .onAppear { if reduceMotion { inDock = true } }
    .modifier(
      Looping(interval: .seconds(1.8)) {
        withAnimation(inDock ? .easeInOut(duration: 0.5) : .spring(duration: 0.8, bounce: 0.25)) {
          inDock.toggle()
        }
      }
    )
    .accessibilityHidden(true)
  }

  private func gridOffset(_ index: Int, tile: CGFloat, gap: CGFloat) -> CGSize {
    let row = CGFloat(index / 4)
    let column = CGFloat(index % 4)
    return CGSize(width: gap + column * (tile + gap), height: gap * 2.2 + row * (tile + gap * 1.3))
  }

  private func dockOffset(_ index: Int, tile: CGFloat, gap: CGFloat, height: CGFloat) -> CGSize {
    CGSize(width: gap + CGFloat(index) * (tile + gap), height: height - tile - gap * 2.4)
  }
}

// MARK: - Product insights

/// The Scout mark with a small, anonymous chart beside it.
struct ScoutInsightsIllustration: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var grown = false

  private let bars: [CGFloat] = [0.35, 0.6, 0.45, 0.85]

  var body: some View {
    HStack(alignment: .bottom, spacing: 22) {
      BraveAppIcon(size: 96)
      HStack(alignment: .bottom, spacing: 8) {
        ForEach(bars.indices, id: \.self) { index in
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(index == bars.count - 1 ? ScoutArt.mint : ScoutArt.violetLight.opacity(0.55))
            .frame(width: 18, height: 96 * (grown ? bars[index] : 0.12))
        }
      }
      .frame(height: 96, alignment: .bottom)
      .padding(14)
      .background(ScoutArt.card, in: .rect(cornerRadius: 18, style: .continuous))
      .overlay(alignment: .topTrailing) {
        Image(systemName: "lock.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          .padding(7)
          .background(ScoutArt.violet, in: .circle)
          .offset(x: 8, y: -8)
      }
    }
    .onAppear {
      withAnimation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.3).delay(0.2)) {
        grown = true
      }
    }
    .accessibilityHidden(true)
  }
}
