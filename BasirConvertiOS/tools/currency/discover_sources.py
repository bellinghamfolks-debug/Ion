#!/usr/bin/env python3
"""Find the Saudi riyal images the currency reader can be trained on.

Runs in CI, which can reach the internet. Writes a report of every source:
what it holds, how large it is, and its licence, so nothing is used before
its terms are known. Nothing is downloaded in bulk here.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

AGENT = "BasirCurrencyResearch/1.0 (accessibility app; contact via basir website)"


def get(url: str, *, limit: int = 3_000_000) -> tuple[int, str]:
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": "application/json, text/html"})
    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            return response.status, response.read(limit).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read(20_000).decode("utf-8", "replace")
    except Exception as error:  # noqa: BLE001 - the report records any failure
        return 0, f"{type(error).__name__}: {error}"


def mendeley(report: dict) -> None:
    base = "https://data.mendeley.com/public-api/datasets/7sys44td9c"
    status, body = get(base)
    entry: dict = {"status": status}
    try:
        meta = json.loads(body)
        entry["name"] = meta.get("name")
        entry["description"] = (meta.get("description") or "")[:3000]
        entry["licence"] = meta.get("data_licence") or meta.get("licence")
        entry["version"] = meta.get("version")
        entry["published"] = meta.get("publish_date")
        version = meta.get("version") or 1
        status, files = get(f"{base}/files?folder_id=root&version={version}")
        entry["files_status"] = status
        try:
            listing = json.loads(files)
            entry["files"] = [{"name": item.get("filename"), "size": item.get("size"),
                               "download": (item.get("content_details") or {}).get("download_url")}
                              for item in listing][:50]
        except Exception:
            entry["files_raw"] = files[:3000]
    except Exception:
        entry["raw"] = body[:3000]
    report["mendeley_saudi_currency"] = entry


def commons(report: dict) -> None:
    api = "https://commons.wikimedia.org/w/api.php"
    found: dict[str, dict] = {}
    queue = ["Category:Banknotes of Saudi Arabia"]
    seen: set[str] = set()
    while queue and len(seen) < 40:
        category = queue.pop(0)
        if category in seen:
            continue
        seen.add(category)
        params = {"action": "query", "list": "categorymembers", "cmtitle": category, "cmlimit": "500",
                  "format": "json", "cmtype": "file|subcat"}
        status, body = get(f"{api}?{urllib.parse.urlencode(params)}")
        try:
            members = json.loads(body)["query"]["categorymembers"]
        except Exception:
            report.setdefault("commons_errors", []).append({"category": category, "status": status, "body": body[:400]})
            continue
        for member in members:
            title = member["title"]
            if title.startswith("Category:"):
                queue.append(title)
            elif title.startswith("File:"):
                found[title] = {"category": category}
    titles = list(found)
    for start in range(0, len(titles), 40):
        batch = titles[start:start + 40]
        params = {"action": "query", "prop": "imageinfo", "titles": "|".join(batch), "format": "json",
                  "iiprop": "url|size|extmetadata|mime"}
        status, body = get(f"{api}?{urllib.parse.urlencode(params)}")
        try:
            pages = json.loads(body)["query"]["pages"].values()
        except Exception:
            continue
        for page in pages:
            info = (page.get("imageinfo") or [{}])[0]
            meta = info.get("extmetadata") or {}
            found[page["title"]].update({
                "url": info.get("url"), "width": info.get("width"), "height": info.get("height"),
                "mime": info.get("mime"),
                "licence": (meta.get("LicenseShortName") or {}).get("value"),
                "date": re.sub(r"<[^>]+>", "", (meta.get("DateTimeOriginal") or {}).get("value", ""))[:40],
            })
    report["wikimedia_commons"] = {"categories": sorted(seen), "files": found}


def sama(report: dict) -> None:
    pages = {
        "sixth": "https://www.sama.gov.sa/en-US/Currency/Pages/SixthIssue.aspx",
        "fifth": "https://www.sama.gov.sa/en-US/Currency/Pages/FifthIssue.aspx",
        "commemorative": "https://www.sama.gov.sa/en-US/Currency/Pages/CommemorativeBanknotes.aspx",
        "currency": "https://www.sama.gov.sa/en-US/Currency/Pages/default.aspx",
    }
    result = {}
    for key, url in pages.items():
        status, body = get(url)
        images = sorted(set(re.findall(r"""src=["']([^"']+\.(?:jpg|jpeg|png|webp))["']""", body, re.I)))
        links = sorted(set(re.findall(r"""href=["']([^"']*(?:Issue|Banknote|Currency)[^"']*)["']""", body, re.I)))[:60]
        result[key] = {"status": status, "images": images[:120], "links": links,
                       "text": re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", body))[:2500]}
    report["sama"] = result


def roboflow(report: dict) -> None:
    result = {}
    for url in ("https://universe.roboflow.com/disha-fxfg8", "https://universe.roboflow.com/bin-mibxd/banknote-detection-2amdt"):
        status, body = get(url)
        result[url] = {"status": status,
                       "licence": sorted(set(re.findall(r"(CC BY[^\"<]{0,20}|Public Domain|MIT|Private)", body)))[:5],
                       "projects": sorted(set(re.findall(r'/disha-fxfg8/([a-z0-9-]+)', body)))[:20]}
    report["roboflow"] = result


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "currency_sources.json")
    report: dict = {}
    for step in (mendeley, commons, sama, roboflow):
        try:
            step(report)
        except Exception as error:  # noqa: BLE001
            report[f"{step.__name__}_error"] = repr(error)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=1))
    files = report.get("wikimedia_commons", {}).get("files", {})
    print(f"mendeley={report.get('mendeley_saudi_currency', {}).get('status')} commons_files={len(files)} "
          f"sama={[v.get('status') for v in report.get('sama', {}).values()]}")


if __name__ == "__main__":
    main()
