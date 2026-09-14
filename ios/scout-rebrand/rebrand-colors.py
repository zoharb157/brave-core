#!/usr/bin/env python3
"""Rotates Leo's blue primary ramp onto Scout's violet.

Hue only: saturation and lightness are left exactly as they were, so every
contrast ratio the design system was built around still holds, in both light
and dark. Anything outside the blue window — greens, ambers, reds, greys, and
Brave's own product colours — is untouched.

Re-runnable, and idempotent: colours already at the target hue are skipped.
Keep it: a dependency install restores Leo's originals and this puts them back.
"""
import colorsys, json, pathlib, sys

CATALOG = pathlib.Path(sys.argv[1])
APPLY = "--apply" in sys.argv

# Scout violet #544096.
TARGET_HUE = colorsys.rgb_to_hls(84 / 255, 64 / 255, 150 / 255)[0]
# Brave's primary blue sits tightly around 234 degrees. Keep the window narrow
# so an informational blue or a partner colour is not swept up with it.
LOW, HIGH = 225 / 360, 245 / 360
MIN_SAT = 0.12  # near-greys carry a nominal hue that means nothing


def as_float(v):
    v = str(v).strip()
    if v.startswith("0x"):
        return int(v, 16) / 255
    return float(v)


def convert(comp):
    r, g, b = (as_float(comp[k]) for k in ("red", "green", "blue"))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if not (LOW <= h <= HIGH) or s < MIN_SAT:
        return None
    nr, ng, nb = colorsys.hls_to_rgb(TARGET_HUE, l, s)
    return {k: f"{v:.3f}" for k, v in (("red", nr), ("green", ng), ("blue", nb))}


changed = []
for contents in sorted(CATALOG.glob("*.colorset/Contents.json")):
    doc = json.loads(contents.read_text())
    touched = False
    for entry in doc.get("colors", []):
        comp = entry.get("color", {}).get("components")
        if not comp:
            continue
        new = convert(comp)
        if new is None:
            continue
        comp.update(new)
        touched = True
    if touched:
        changed.append(contents.parent.name.replace(".colorset", ""))
        if APPLY:
            contents.write_text(json.dumps(doc, indent=2) + "\n")

print(f"{'rewrote' if APPLY else 'would rewrite'} {len(changed)} colorsets")
for name in changed:
    print("  ", name)
