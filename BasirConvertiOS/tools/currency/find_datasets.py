#!/usr/bin/env python3
"""Looks for more public photo sets of Saudi riyal notes.

The first set has one face of each note on one background, which is not
enough. This lists what Hugging Face, GitHub, Kaggle and Roboflow Universe
offer for the current notes, with size and licence where they say, so a
source is chosen on evidence before anything is downloaded.

usage: find_datasets.py <report.json>
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

AGENT = "BasirCurrencyResearch/1.0 (accessibility app for blind users)"
QUERIES = ["saudi riyal", "saudi currency", "saudi banknote", "riyal banknote", "sar banknote",
           "saudi arabia currency detection", "عملة سعودية"]


def get(url: str, headers: dict | None = None) -> tuple[int, str]:
    time.sleep(1.0)
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            return response.status, response.read(3_000_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read(2000).decode("utf-8", "replace")
    except Exception as error:  # noqa: BLE001
        return 0, repr(error)


def hugging_face() -> list[dict]:
    found = {}
    for query in QUERIES:
        status, body = get("https://huggingface.co/api/datasets?" + urllib.parse.urlencode({"search": query, "limit": 50, "full": "true"}))
        if status != 200:
            found[f"error:{query}"] = {"status": status}
            continue
        for item in json.loads(body):
            tags = item.get("tags", [])
            found[item["id"]] = {
                "url": f"https://huggingface.co/datasets/{item['id']}",
                "downloads": item.get("downloads"), "modified": item.get("lastModified"),
                "licence": next((t.split(":", 1)[1] for t in tags if t.startswith("license:")), None),
                "size": next((t.split(":", 1)[1] for t in tags if t.startswith("size_categories:")), None),
                "task": [t for t in tags if t.startswith("task_categories:")],
                "description": (item.get("description") or "")[:300],
            }
    return [{"id": key, **value} for key, value in found.items()]


def github() -> list[dict]:
    found = {}
    headers = {"Accept": "application/vnd.github+json"}
    if os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    for query in QUERIES:
        status, body = get("https://api.github.com/search/repositories?" +
                           urllib.parse.urlencode({"q": query, "per_page": 30, "sort": "stars"}), headers)
        if status != 200:
            found[f"error:{query}"] = {"status": status, "body": body[:200]}
            continue
        for repo in json.loads(body).get("items", []):
            found[repo["full_name"]] = {
                "url": repo["html_url"], "stars": repo["stargazers_count"], "size_kb": repo["size"],
                "licence": (repo.get("license") or {}).get("spdx_id"), "pushed": repo["pushed_at"],
                "description": (repo.get("description") or "")[:300],
            }
    return [{"id": key, **value} for key, value in found.items()]


def kaggle() -> dict:
    out = {}
    for query in QUERIES[:4]:
        status, body = get("https://www.kaggle.com/api/v1/datasets/list?" + urllib.parse.urlencode({"search": query}))
        try:
            out[query] = {"status": status, "items": [
                {"ref": d.get("ref"), "title": d.get("title"), "size": d.get("totalBytes"),
                 "licence": d.get("licenseName"), "downloads": d.get("downloadCount")} for d in json.loads(body)]}
        except Exception:  # noqa: BLE001
            out[query] = {"status": status, "body": body[:200]}
    return out


def roboflow() -> dict:
    out = {}
    for query in QUERIES[:4]:
        status, body = get("https://universe.roboflow.com/search?" + urllib.parse.urlencode({"q": query}))
        links = sorted(set(re.findall(r'href="(/[\w-]+/[\w-]+)"', body)))
        out[query] = {"status": status, "projects": [l for l in links if not l.startswith(("/search", "/browse"))][:60]}
    return out


def main() -> None:
    report = {"hugging_face": hugging_face(), "github": github(), "kaggle": kaggle(), "roboflow": roboflow()}
    with open(sys.argv[1], "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=1)
    print(json.dumps({k: len(v) for k, v in report.items()}))


if __name__ == "__main__":
    main()
