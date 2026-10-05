#!/usr/bin/env python3
"""Verifies WCAG contrast of every text/background pair in Theme.swift."""
import re, sys
from pathlib import Path

src = (Path(__file__).resolve().parents[1] / "CoffeeAccess/DesignSystem/Theme.swift").read_text()
colors = {name: dict(zip(("light", "dark", "lightHC", "darkHC"), (int(v, 16) for v in vals)))
          for name, *vals in re.findall(r"static let (\w+) = dynamic\(light: 0x(\w+), dark: 0x(\w+), lightHC: 0x(\w+), darkHC: 0x(\w+)\)", src)}

def lum(c):
    ch = [((c >> s) & 0xFF) / 255 for s in (16, 8, 0)]
    ch = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in ch]
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]

def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

PAIRS = [(t, b, 4.5) for t in ("textPrimary", "textSecondary", "accent", "danger", "warning", "success")
         for b in ("background", "surface", "surfaceRaised")] + [("onAccent", "accent", 4.5), ("onAccent", "danger", 4.5),
     ("onInk", "ink", 4.5), ("onHotTag", "hotTag", 4.5), ("onColdTag", "coldTag", 4.5)] \
  + [(t, "sky", 4.5) for t in ("textPrimary", "textSecondary")] \
  + [("ink", b, 4.5) for b in ("background", "surface", "surfaceRaised")]
failures = 0
for text, bg, need in PAIRS:
    for mode in ("light", "dark", "lightHC", "darkHC"):
        r = ratio(colors[text][mode], colors[bg][mode])
        if r < need:
            failures += 1
            print(f"FAIL {text} on {bg} ({mode}): {r:.2f} < {need}")
print("Contrast check:", "PASS" if not failures else f"FAILED ({failures})")
sys.exit(1 if failures else 0)
