"""Temporary: prints the shape of Turath's public data, to build on real ids."""
import gzip, json, urllib.request, urllib.parse

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
        if r.headers.get("Content-Encoding") == "gzip":
            data = gzip.decompress(data)
    return data.decode("utf-8", "replace")

def show(name, url, n=1800):
    print("=====", name, url)
    try:
        t = get(url)
        print(len(t), t[:n])
        return t
    except Exception as e:
        print("FAILED", e)

q = urllib.parse.quote("حكم قتل النمل")
show("search", f"https://api.turath.io/search?q={q}&ver=3")
show("search-author", f"https://api.turath.io/search?q={q}&author=57&ver=3")
show("search-book", f"https://api.turath.io/search?q={q}&book=12293&ver=3")
show("author", "https://api.turath.io/author?id=57&ver=3")
show("book", "https://api.turath.io/book?id=7339&ver=3", 900)
show("page", "https://api.turath.io/page?book_id=7339&pg=10&ver=3", 900)
t = show("data", "https://files.turath.io/data-v3.json", 300)
if t:
    d = json.loads(t)
    print("keys", {k: (len(v) if hasattr(v, "__len__") else v) for k, v in d.items()})
    authors = d.get("authors") or {}
    books = d.get("books") or {}
    items = authors.items() if isinstance(authors, dict) else enumerate(authors)
    sample = list(items)[:2]
    print("author sample", json.dumps(sample, ensure_ascii=False)[:600])
    bitems = list(books.items())[:2] if isinstance(books, dict) else books[:2]
    print("book sample", json.dumps(bitems, ensure_ascii=False)[:600])
    want = ["تيمية", "قيم الجوزية", "بن باز", "العثيمين", "الفوزان", "الألباني", "الدارقطني", "ابن حجر", "الذهبي",
            "مسلم بن الحجاج", "البخاري", "الترمذي"]
    alist = authors.items() if isinstance(authors, dict) else [(a.get("id"), a) for a in authors]
    for aid, a in alist:
        name = a.get("name", "") if isinstance(a, dict) else str(a)
        if any(w in name for w in want):
            print("AUTHOR", aid, json.dumps(a, ensure_ascii=False)[:260])
