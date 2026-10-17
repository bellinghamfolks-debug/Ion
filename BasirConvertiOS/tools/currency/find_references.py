#!/usr/bin/env python3
"""Look for reference images of current riyal notes (both faces, every issue).

Searches the Arabic and English Wikipedia articles on the riyal and the
Saudi central bank's currency pages, and records each image with its size
and licence. A reference image is used only to render synthetic training
photos of a face the real-photo dataset lacks; it is never shipped.
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

AGENT = "BasirCurrencyResearch/1.0 (accessibility app for blind users)"


def get(url: str) -> tuple[int, str]:
    time.sleep(1.0)
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            return response.status, response.read(4_000_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, ""
    except Exception as error:  # noqa: BLE001
        return 0, repr(error)


def wiki_images(lang: str, page: str) -> list[dict]:
    api = f"https://{lang}.wikipedia.org/w/api.php"
    params = {"action": "query", "titles": page, "prop": "images", "imlimit": "500", "format": "json", "redirects": 1}
    status, body = get(f"{api}?{urllib.parse.urlencode(params)}")
    try:
        pages = json.loads(body)["query"]["pages"].values()
        titles = [image["title"] for p in pages for image in p.get("images", [])]
    except Exception:
        return [{"error": status, "page": page}]
    titles = [t for t in titles if re.search(r"(riyal|rial|ريال|banknote|ورقة|نقد|sama)", t, re.I)]
    found = []
    for start in range(0, len(titles), 40):
        params = {"action": "query", "titles": "|".join(titles[start:start + 40]), "prop": "imageinfo",
                  "iiprop": "url|size|extmetadata", "format": "json"}
        status, body = get(f"{api}?{urllib.parse.urlencode(params)}")
        try:
            for item in json.loads(body)["query"]["pages"].values():
                info = (item.get("imageinfo") or [{}])[0]
                meta = info.get("extmetadata") or {}
                found.append({"title": item.get("title"), "url": info.get("url"), "width": info.get("width"),
                              "height": info.get("height"),
                              "licence": (meta.get("LicenseShortName") or {}).get("value"),
                              "description": re.sub(r"<[^>]+>", "", (meta.get("ImageDescription") or {}).get("value", ""))[:200]})
        except Exception:
            continue
    return found


def main() -> None:
    out = Path(sys.argv[1])
    report: dict = {}
    for lang, page in [("en", "Saudi riyal"), ("en", "Banknotes of the Saudi riyal"), ("ar", "ريال سعودي"),
                       ("ar", "الإصدار السادس من العملة السعودية"), ("en", "Saudi Central Bank")]:
        report[f"{lang}:{page}"] = wiki_images(lang, page)
    for url in ["https://www.sama.gov.sa/ar-sa/Currency/Pages/SixthIssue.aspx",
                "https://www.sama.gov.sa/en-US/Currency/Pages/SixthIssue.aspx",
                "https://en.numista.com/catalogue/banknotes-saudi_arabia.html"]:
        status, body = get(url)
        report[url] = {"status": status, "images": sorted(set(re.findall(r"""(?:src|href)=["']([^"']+\.(?:jpg|jpeg|png))""", body, re.I)))[:150]}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=1))
    print({k: (len(v) if isinstance(v, list) else v.get("status")) for k, v in report.items()})


if __name__ == "__main__":
    main()
