#!/usr/bin/env bash
# Recompiles NalaAssets' colour catalog from the (violet) Leo tokens.
#
# NalaAssets ships as a prebuilt xcframework, so editing the .colorset sources
# alone changes nothing — the app links a compiled Assets.car. This rebuilds
# that car with actool and drops it into every slice that exists.
set -euo pipefail
# Every catalog that belongs in the framework, not just the colours. NalaAssets
# carries Leo's symbols too, and compiling only Colors.xcassets produces an
# Assets.car with no icons in it — which looks exactly like a toolbar whose
# buttons have vanished.
COLORS="$1"; SYMBOLS="$2"
shift 2
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

for FW in "$@"; do
  [ -f "$FW/Assets.car" ] || { echo "skip (no Assets.car): $FW"; continue; }
  case "$FW" in
    *simulator*) PLATFORM=iphonesimulator ;;
    *)           PLATFORM=iphoneos ;;
  esac
  rm -rf "$TMP/out"; mkdir -p "$TMP/out"
  xcrun actool "$COLORS" "$SYMBOLS" \
    --compile "$TMP/out" \
    --platform "$PLATFORM" \
    --enable-on-demand-resources NO \
    --minimum-deployment-target 18.0 \
    --output-format human-readable-text \
    --notices --warnings > /dev/null
  cp "$TMP/out/Assets.car" "$FW/Assets.car"
  echo "recompiled ($PLATFORM): $FW/Assets.car"
done
