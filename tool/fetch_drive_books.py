"""Runs on GitHub before each build: reads the sheikh's public Google Drive
folder and writes assets/data/books.json (title, file id, sub-folder).
If Drive can't be reached, the existing books.json is kept."""
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT_FOLDER = "19p5At8pu_DEPA6M50PF6N4j3HpoNUbD_"
OUT = Path("assets/data/books.json")
UA = {"User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"}


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read().decode("utf-8", "replace")


def list_folder(folder_id: str):
    page = fetch(f"https://drive.google.com/embeddedfolderview?id={folder_id}")
    entries = []
    for chunk in page.split('class="flip-entry"')[1:]:
        m_id = re.search(r'id="entry-([\w-]+)"', chunk)
        m_title = re.search(r'class="flip-entry-title">(.*?)</div>', chunk, re.S)
        m_href = re.search(r'href="([^"]+)"', chunk)
        if not (m_id and m_title):
            continue
        href = html.unescape(m_href.group(1)) if m_href else ""
        entries.append({
            "id": m_id.group(1),
            "name": html.unescape(re.sub(r"<[^>]+>", "", m_title.group(1))).strip(),
            "is_folder": "/folders/" in href,
        })
    if not entries:
        print("No entries parsed. Page start:\n", page[:1500])
    return entries


def clean_title(name: str) -> str:
    return re.sub(r"\.(pdf|docx?|epub)$", "", name, flags=re.I).strip()


def main():
    try:
        books = []
        for e in list_folder(ROOT_FOLDER):
            if e["is_folder"]:
                for s in list_folder(e["id"]):
                    if not s["is_folder"]:
                        books.append({"id": s["id"], "title": clean_title(s["name"]),
                                      "file": s["name"], "folder": e["name"]})
            else:
                books.append({"id": e["id"], "title": clean_title(e["name"]),
                              "file": e["name"], "folder": ""})
    except Exception as ex:  # keep the old list
        print("Drive not reachable:", ex)
        return 0
    if not books:
        print("No books found; keeping existing books.json")
        return 0
    OUT.write_text(json.dumps(books, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(books)} books written:")
    for b in books:
        print(" -", b["folder"] or "(root)", "|", b["title"], "|", b["id"])
    # Check that one book can actually be downloaded
    try:
        url = f"https://drive.usercontent.google.com/download?id={books[0]['id']}&export=download&confirm=t"
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=40) as r:
            head = r.read(8)
            print("Download test:", r.status, r.headers.get("Content-Type"), head)
    except Exception as ex:
        print("Download test failed:", ex)
    return 0


if __name__ == "__main__":
    sys.exit(main())
