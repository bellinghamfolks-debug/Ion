#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Views/Components.swift"
if not path.is_file():
    raise SystemExit("R12 visual polish: Components.swift is missing")

text = path.read_text(encoding="utf-8")
marker = "BASIR_POLISHED_BACKGROUND_R12"

if marker not in text:
    start = text.find("struct AuroraBackground: View {")
    if start < 0:
        raise SystemExit("R12 visual polish: AuroraBackground was not found")

    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit("R12 visual polish: AuroraBackground opening brace was not found")

    depth = 0
    end = None
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        raise SystemExit("R12 visual polish: AuroraBackground closing brace was not found")

    replacement = '''struct AuroraBackground: View {
    @Environment(\\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // BASIR_POLISHED_BACKGROUND_R12
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.010, green: 0.035, blue: 0.075),
                        Color(red: 0.012, green: 0.075, blue: 0.145),
                        Color(red: 0.008, green: 0.030, blue: 0.065)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if !reduceTransparency {
                    Circle()
                        .fill(BasirPalette.cyan.opacity(0.10))
                        .frame(width: geometry.size.width * 0.78)
                        .blur(radius: 72)
                        .offset(x: -geometry.size.width * 0.35,
                                y: -geometry.size.height * 0.22)

                    Circle()
                        .fill(BasirPalette.violet.opacity(0.12))
                        .frame(width: geometry.size.width * 0.92)
                        .blur(radius: 86)
                        .offset(x: geometry.size.width * 0.45,
                                y: geometry.size.height * 0.10)

                    RoundedRectangle(cornerRadius: 120, style: .continuous)
                        .fill(BasirPalette.cyanDeep.opacity(0.10))
                        .frame(width: geometry.size.width * 1.18,
                               height: geometry.size.height * 0.30)
                        .blur(radius: 72)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -geometry.size.width * 0.18,
                                y: geometry.size.height * 0.34)

                    RoundedRectangle(cornerRadius: 140, style: .continuous)
                        .fill(BasirPalette.cyan.opacity(0.055))
                        .frame(width: geometry.size.width * 1.10,
                               height: geometry.size.height * 0.20)
                        .blur(radius: 80)
                        .offset(x: geometry.size.width * 0.10,
                                y: geometry.size.height * 0.48)
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}'''

    text = text[:start] + replacement + text[end:]
    path.write_text(text, encoding="utf-8")

final = path.read_text(encoding="utf-8")
for required in (
    marker,
    "LinearGradient(",
    "accessibilityReduceTransparency",
    ".allowsHitTesting(false)",
):
    if required not in final:
        raise SystemExit(f"R12 visual polish missing {required!r}")

if "struct AuroraBackground: View" not in final:
    raise SystemExit("R12 visual polish removed AuroraBackground")

print("BASIR_R12_VISUAL_POLISH=AMBIENT_FULL_SCREEN_BACKGROUND")
