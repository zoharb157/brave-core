# Scout colour rebrand

Leo's palette is Brave blue. Scout's is violet (`#544096`). These two scripts
move the first onto the second and are **not** one-time: Leo lives in
`node_modules`, so any dependency install restores the blue and they have to be
run again.

    # 1. Rotate the token sources
    python3 rebrand-colors.py <path-to>/@brave/leo/tokens/ios-swift/Colors.xcassets --apply

    # 2. Recompile them into the prebuilt framework the app actually links
    ./rebrand-assets.sh <same-catalog> \
      ../../../out/ios_Debug_arm64_simulator/NalaAssets.xcframework/ios-arm64-simulator/NalaAssets.framework \
      ../../../out/ios_Release_arm64/NalaAssets.xcframework/ios-arm64/NalaAssets.framework

Step 2 exists because `NalaAssets` ships as a binary xcframework containing a
compiled `Assets.car`. Editing the `.colorset` sources alone changes nothing
you can see — the first attempt at this looked like it had failed for that
reason. A full gn build regenerates the framework from the sources, so after
one of those only step 1 matters.

**Hue only.** Saturation and lightness are left exactly as Leo set them, so
every contrast ratio the design system was built around still holds in both
light and dark. Primary and secondary are three degrees apart in hue and are
told apart by saturation, so rotating both to one hue keeps them distinct.
Greens, ambers, reds and greys are outside the window and untouched.
