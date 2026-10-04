#!/usr/bin/env python3
"""Check reviewed teaching material and its generated integration in memory.

Use --allow-partial while authoring checkpointed batches. The default requires
guides for all 360 lessons. This command does not write generated resources.
"""
import argparse
import json
import re

from expand_curriculum import (
    PATH, apply_quality_fixes, arabic_policy, expand_lesson, load_enrichment,
    load_quality_fixes, merge_new_vocabulary, model_sentence,
)
from lesson_guides import load_guides, validate_guides, apply_lesson_updates
from build_new_lessons import load_seeds, build_unit
from build_seed_json import SRC, parse


def hydrate_authored_sources(catalog):
    """Audit current source edits, even before generated resources are rebuilt."""
    seeds = load_seeds()
    for path in sorted(SRC.glob("*_expansion.txt")):
        code, units = parse(path)
        authored_ids = {u["id"] for u in units}
        seeds[code] = [u for u in seeds[code] if u["id"] not in authored_ids] + units
    for level in catalog["levels"]:
        code = level["level"]
        if code not in seeds:
            continue
        replacements = {u["id"]: u for u in seeds[code]}
        level["units"] = [build_unit(code, replacements[u["id"]], u["order"])
                          if u["id"] in replacements else u for u in level["units"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-partial", action="store_true")
    args = parser.parse_args()
    catalog = json.loads(PATH.read_text(encoding="utf-8"))
    hydrate_authored_sources(catalog)
    guides = load_guides()
    validate_guides(guides, catalog, require_complete=not args.allow_partial)
    apply_lesson_updates(catalog, guides)
    fixes = load_quality_fixes()
    apply_quality_fixes(catalog, fixes, require_all=False)
    enrichment = load_enrichment()
    for level in catalog["levels"]:
        for unit in level["units"]:
            for lesson in unit["lessons"]:
                payload = enrichment.get(lesson["id"])
                if payload:
                    _, duplicates = merge_new_vocabulary(lesson, payload)
                    assert not duplicates, (lesson["id"], duplicates)
    apply_quality_fixes(catalog, fixes)
    checked = 0
    for level in catalog["levels"]:
        for unit in level["units"]:
            en = [w["english"] for ls in unit["lessons"] for w in ls["vocabulary"]]
            ar = [w["arabic"] for ls in unit["lessons"] for w in ls["vocabulary"]]
            for lesson in unit["lessons"]:
                lid = lesson["id"]
                if lid not in guides:
                    continue
                guide = guides[lid]
                sentence = model_sentence(lesson)
                assert any(re.search(rf"\b{re.escape(w['english'])}\b", sentence)
                           for w in lesson["vocabulary"]), f"{lid}: no literal model vocabulary"
                expand_lesson(lesson, en, ar, enrichment.get(lid, {}).get("extraExamples", {}),
                              arabic_policy(level["level"]), guide)
                exercises = lesson["exercises"]
                assert guide["focusAr"] in exercises[0]["explanationAr"], lid
                assert guide["taskAr"] in exercises[-1]["explanationAr"], lid
                assert guide["exampleEn"] in exercises[-1]["explanationAr"], lid
                matches = [e for e in exercises if e.get("promptEn") == guide["check"]["promptEn"]]
                assert len(matches) == 1, f"{lid}: missing/duplicate authored assessment"
                assert matches[0]["explanationAr"] == guide["check"]["explanationAr"], lid
                assert len(exercises) == len({e["id"] for e in exercises}), lid
                assert lesson["estimatedMinutes"] <= 25, f"{lid}: lesson exceeds 25 minutes"
                checked += 1
    print(f"Reviewed guide audit: PASS ({checked}/360 lessons; in-memory integration).")


if __name__ == "__main__":
    main()
