"""Runs on GitHub before each build: the trusted scholars' short biographies and
lists of books, from the public data of «تراث» -> assets/data/scholars.json.
Only names, ids and sizes: no book text is bundled. Never fails the build."""
import gzip
import json
import urllib.request
from pathlib import Path

OUT = Path("assets/data/scholars.json")
# In the order the app shows them: (id on «تراث», name shown in the app)
SCHOLARS = [
    (54, "ابن تيمية"), (14, "ابن القيم"), (67, "ابن باز"), (57, "ابن عثيمين"), (62, "صالح الفوزان"),
    (414, "الألباني"), (223, "الدارقطني"), (202, "ابن حجر العسقلاني"), (362, "الذهبي"), (242, "مسلم"),
    (215, "البخاري"), (217, "الترمذي"),
    # No id known beforehand: found by these words in the author's name.
    (("مقبل", "الوادعي"), "مقبل الوادعي"), (("يحيى", "الحجوري"), "يحيى الحجوري"),
]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
        if r.headers.get("Content-Encoding") == "gzip":
            data = gzip.decompress(data)
    return json.loads(data.decode("utf-8"))


try:
    data = get("https://files.turath.io/data-v3.json")
    out = []
    for aid, shown in SCHOLARS:
        if isinstance(aid, tuple):
            words, aid = aid, None
            for k, v in data["authors"].items():
                if all(w in v.get("name", "") for w in words):
                    aid = int(k)
                    break
            print(shown, "-> author id", aid)
            if aid is None:
                # Not on «تراث»: listed by name only, with no invented text.
                out.append({"id": 0, "name": shown, "full": shown, "death": None, "bio": "", "books": []})
                continue
        a = data["authors"].get(str(aid)) or {}
        bio = ""
        try:
            bio = (get(f"https://api.turath.io/author?id={aid}&ver=3").get("biography") or "").strip()
        except Exception as e:
            print("no biography for", aid, e)
        books = []
        for bid in a.get("books", []):
            b = data["books"].get(str(bid))
            if b:
                books.append({"id": b["id"], "name": b["name"], "pages": b.get("page_count", 0),
                              "size": b.get("size", 0), "pdf": bool(b.get("has_pdf"))})
        books.sort(key=lambda b: -b["pages"])
        out.append({"id": aid, "name": shown, "full": a.get("name", shown), "death": a.get("death"),
                    "bio": bio, "books": books})
        print(shown, len(books), "books", len(bio), "chars of biography")
    if sum(len(s["books"]) for s in out) > 50:
        OUT.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
        print("scholars.json:", OUT.stat().st_size, "bytes")
except Exception as ex:
    print("«تراث» not reachable, keeping the bundled list:", ex)
