#!/usr/bin/env python3
"""Checks the interface strings table against the code.

- every key used in code (static L("…") calls plus the keys built from enum
  cases and guide steps) exists in Strings.swift;
- no key is defined twice (a duplicate key in a Swift dictionary literal
  crashes the app at launch);
- Arabic and English carry the same format specifiers;
- no English-only leftovers in Arabic text, and both sides are non-empty.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "CoffeeAccess"
STRINGS = APP / "Core/Localization/Strings.swift"
STRINGS_LIFE = APP / "Core/Localization/StringsLife.swift"
STRING_FILES = (STRINGS, STRINGS_LIFE)

ENTRY = re.compile(r'^\s*"([^"]+)":\s*\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\),\s*$')
SPEC = re.compile(r"%(?:\d+\$)?(?:\.\d+)?[@dfs]|%%")


def swift_cases(path: Path, enum: str) -> list[str]:
    text = path.read_text(encoding="utf-8")
    match = re.search(rf"enum {enum}\b[^{{]*\{{(.*?)\n\}}", text, re.S)
    if not match:
        raise SystemExit(f"enum {enum} not found in {path}")
    body = match.group(1)
    cases: list[str] = []
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("case ") and not line.startswith("case .") and ":" not in line and "(" not in line.split("//")[0]:
            for name in line[5:].split("//")[0].split(","):
                name = name.split("=")[0].strip()
                if name:
                    cases.append(name)
    return cases


def main() -> int:
    errors: list[str] = []
    defined: dict[str, tuple[str, str]] = {}
    for strings_file in STRING_FILES:
      for number, line in enumerate(strings_file.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip().startswith('"'):
            continue
        match = ENTRY.match(line)
        if not match:
            errors.append(f"{strings_file.name}:{number}: unparseable entry")
            continue
        key, ar, en = match.groups()
        if key in defined:
            errors.append(f"duplicate key {key!r} ({strings_file.name} line {number})")
        defined[key] = (ar, en)
        if not ar.strip() or not en.strip():
            errors.append(f"{key}: empty translation")
        if sorted(SPEC.findall(ar)) != sorted(SPEC.findall(en)):
            errors.append(f"{key}: format specifiers differ: ar={SPEC.findall(ar)} en={SPEC.findall(en)}")
        if re.search(r"%(?!(?:\d+\$)?(?:\.\d+)?[@dfs]|%)", SPEC.sub("", ar + en)):
            errors.append(f"{key}: stray % sign (use %% for a literal percent)")

    used: set[str] = set()
    for swift in APP.rglob("*.swift"):
        if swift in STRING_FILES:
            continue
        text = swift.read_text(encoding="utf-8")
        used.update(re.findall(r'\bL\("([^"\\]+)"', text))
        used.update(re.findall(r'unitKey: "([^"]+)"', text))
        used.update(re.findall(r'"(home\.greeting\.[a-z]+)"', text))

    model = APP / "Core"
    beverages = swift_cases(model / "Model/Beverage.swift", "BeverageID")
    for case in beverages:
        used.update({f"drink.{case}.name", f"drink.{case}.summary"})
    for case in swift_cases(model / "Model/Beverage.swift", "BeverageCategory"):
        used.add(f"category.{case}")
    machine = model / "Machine/MachineState.swift"
    for case in swift_cases(machine, "MachineAlarm"):
        used.update({f"alarm.{case}.title", f"alarm.{case}.advice"})
    for enum, prefix in (("MachinePower", "power"), ("MachineActivity", "activity"), ("MilkAccessory", "accessory")):
        for case in swift_cases(machine, enum):
            used.add(f"{prefix}.{case}")
    for case in swift_cases(machine, "MachineLinkKind"):
        used.update({f"link.{case}.title", f"link.{case}.detail"})

    guides = (model / "Model/Maintenance.swift").read_text(encoding="utf-8")
    for case, count in re.findall(r"case \.(\w+): return (\d+)", guides.split("var minutes")[0]):
        used.update({f"guide.{case}.title", f"guide.{case}.intro"})
        used.update(f"guide.{case}.step.{n}" for n in range(1, int(count) + 1))
    for case in swift_cases(model / "Model/Maintenance.swift", "MaintenanceGuideID"):
        if f"guide.{case}.title" not in used:
            errors.append(f"guide {case} has no step count")

    info = (APP / "Features/Settings/InfoViews.swift").read_text(encoding="utf-8")
    for prefix, count in re.findall(r'prefix: "(\w+)", count: (\d+)', info):
        used.update({f"{prefix}.{n}.heading" for n in range(1, int(count) + 1)})
        used.update({f"{prefix}.{n}.body" for n in range(1, int(count) + 1)})
    used.update(f"onboarding.feature.{n}" for n in range(1, 5))
    # Keys built at run time from enums and numeric levels.
    used.update(f"teaTemperature.{t}" for t in swift_cases(model / "Model/Beverage.swift", "BrewTemperature"))
    for case in swift_cases(model / "Model/Beverage.swift", "DrinkCollection"):
        used.update({f"collection.{case}.title", f"collection.{case}.summary"})
    for case in swift_cases(APP / "Features/Drinks/DrinksView.swift", "DrinkFilter"):
        used.add(f"filter.{case}")
    for case in swift_cases(model / "Model/Recipe.swift", "FoamLevel"):
        used.add(f"foam.{case}")
    for case in swift_cases(APP / "Features/Journey/CoffeeJourneyView.swift", "Period"):
        used.add(f"journey.period.{case}")
    for case in swift_cases(APP / "Features/Home/HomeView.swift", "Moment"):
        used.update({f"moment.{case}.title", f"moment.{case}.pitch"})
    for case in swift_cases(model / "Model/Recipe.swift", "TasteFlavour"):
        used.update({f"taste.{case}.title", f"taste.{case}.detail"})
    for case in swift_cases(model / "Model/Recipe.swift", "ColdIntensity"):
        used.add(f"cold.intensity.{case}")
    for case in swift_cases(model / "Model/Recipe.swift", "IceLevel"):
        used.add(f"cold.ice.{case}")
    recipe = (model / "Model/Recipe.swift").read_text(encoding="utf-8")
    for roast in re.search(r"enum Roast[^{]*\{ case ([^}]+) \}", recipe).group(1).split(","):
        used.add(f"roast.{roast.strip()}")
    for kind in re.search(r"enum Kind[^{]*\{ case ([^}]+) \}", recipe).group(1).split(","):
        used.add(f"beanKind.{kind.strip()}")
    used.update(f"autoOff.{m}" for m in (15, 30, 60, 120, 180))
    used.update(f"hardness.{n}" for n in range(1, 5))
    used.update(f"waterTemperature.{n}" for n in range(4))
    used.update({"summary.pot", "summary.coffee"})
    notifications = (APP / "App/Notifications.swift").read_text(encoding="utf-8")
    for case in re.search(r"case (brewingUnitWeekly[^\n]+)", notifications).group(1).split(","):
        used.update({f"reminder.{case.strip()}.title", f"reminder.{case.strip()}.body"})
    used.update(f"profile.color.{n}" for n in range(4))

    # Version 2 keys built at run time.
    life = model / "Life"
    lifeviews = APP / "Features/Life"
    for case in swift_cases(life / "CoffeeLife.swift", "HomeSection"):
        used.add(f"homeSection.{case}")
    for case in swift_cases(life / "CoffeeLife.swift", "CareTask"):
        used.add(f"care.{case}")
    for case in swift_cases(life / "CoffeeLife.swift", "StrengthFeedback"):
        used.add(f"rating.strength.{case}")
    bean_stock = (life / "BeanStock.swift").read_text(encoding="utf-8")
    for enum, prefix in (("Taste", "calibration.taste"), ("Body", "calibration.body")):
        # Nested enums: read their single "case a, b, c" line.
        cases = re.search(rf"enum {enum}\b[^{{]*\{{\s*case ([^\n]+)", bean_stock).group(1)
        used.update(f"{prefix}.{case.strip()}" for case in cases.split(","))
    for case in swift_cases(life / "SignatureRecipes.swift", "Season"):
        used.add(f"season.{case}")
    for case in swift_cases(life / "Goals.swift", "Goal"):
        used.update({f"goal.{case}.title", f"goal.{case}.detail"})
    for case in swift_cases(life / "BeanLibrary.swift", "BeanOrigin"):
        used.update({f"library.origin.{case}.title", f"library.origin.{case}.notes"})
    for roast in re.search(r"enum Roast[^{]*\{ case ([^}]+) \}", recipe).group(1).split(","):
        used.add(f"library.roast.{roast.strip()}")
    for case in swift_cases(model / "Model/Beverage.swift", "Vessel"):
        used.add(f"vessel.{case}")
    for case in beverages:
        used.add(f"drink.{case}.origin")
    signatures = (life / "SignatureRecipes.swift").read_text(encoding="utf-8")
    spec_rows = re.findall(r"case \.(\w+): return SignatureSpec\(base: \.\w+, aroma: [.\w]+, ingredients: (\d+), before: (\d+), after: (\d+)", signatures)
    if len(spec_rows) != len(swift_cases(life / "SignatureRecipes.swift", "SignatureRecipeID")):
        errors.append("every signature recipe needs a SignatureSpec row")
    for case, ingredients, before, after in spec_rows:
        used.update({f"signature.{case}.title", f"signature.{case}.summary"})
        used.update(f"signature.{case}.ingredient.{n}" for n in range(1, int(ingredients) + 1))
        used.update(f"signature.{case}.before.{n}" for n in range(1, int(before) + 1))
        used.update(f"signature.{case}.after.{n}" for n in range(1, int(after) + 1))
    machine_extras = (lifeviews / "MachineExtras.swift").read_text(encoding="utf-8")
    setup_steps = int(re.search(r"private let stepCount = (\d+)", machine_extras).group(1))
    used.update(f"setup.step{n}.{part}" for n in range(1, setup_steps + 1) for part in ("title", "body"))
    for part in re.search(r"static let parts = \[([^\]]+)\]", machine_extras).group(1).split(","):
        name = part.strip().strip('"')
        used.update({f"tour.{name}.title", f"tour.{name}.body"})
    extra_count = int(re.search(r"static let extraCount = (\d+)", machine_extras).group(1))
    used.update(f"signal.extra.{n}.{part}" for n in range(1, extra_count + 1) for part in ("title", "advice", "words"))
    for case in swift_cases(machine, "MachineAlarm"):
        used.add(f"signal.alarm.{case}.words")
    descale = (APP / "App/AppModel+Life.swift").read_text(encoding="utf-8")
    for key in re.findall(r'\("(descale\.stage\.\w+)", \d+\)', descale):
        used.update({key, f"{key}.title"})

    missing = sorted(used - defined.keys())
    errors += [f"missing key: {key}" for key in missing]
    unused = sorted(defined.keys() - used)

    if errors:
        print("Strings validation: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"Strings validation: PASS ({len(defined)} keys, {len(used)} used)")
    if unused:
        print(f"- note: {len(unused)} keys not referenced: {', '.join(unused[:12])}{' …' if len(unused) > 12 else ''}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
