#!/usr/bin/env python3
"""Select an available iPhone from `xcrun simctl list devices -j`."""
from __future__ import annotations
import json
import re
import sys

payload = json.load(sys.stdin)
devices = payload.get("devices", {})
choices: list[tuple[tuple[int, ...], str, str]] = []
for runtime, items in devices.items():
    if ".iOS-" not in runtime and "SimRuntime.iOS" not in runtime:
        continue
    version_match = re.search(r"iOS[-.]([0-9-]+)$", runtime)
    version = tuple(int(x) for x in version_match.group(1).split("-") if x.isdigit()) if version_match else (0,)
    for item in items:
        name = str(item.get("name", ""))
        if not name.startswith("iPhone") or not item.get("isAvailable", True):
            continue
        udid = item.get("udid")
        if udid:
            choices.append((version, name, udid))

if not choices:
    print("No available iPhone simulator was found", file=sys.stderr)
    raise SystemExit(1)

choices.sort(key=lambda item: (item[0], item[1]), reverse=True)
print(choices[0][2])
