"""Temporary: prints the shape of Turath's public data, to build on real ids."""
import gzip, json, urllib.request, urllib.parse

def req(url, headers=None):
    h = {"User-Agent": "Mozilla/5.0", "Accept-Encoding": "gzip"}
    h.update(headers or {})
    return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=120)

def get(url):
    with req(url) as r:
        data = r.read()
        if r.headers.get("Content-Encoding") == "gzip":
            data = gzip.decompress(data)
    return data.decode("utf-8", "replace")

for u in ["https://api.turath.io/search?q=test&author=57&ver=3", "https://api.turath.io/author?id=57&ver=3",
          "https://files.turath.io/data-v3.json"]:
    with req(u, {"Origin": "https://ibnalshabira.com"}) as r:
        print("CORS", u, {k: v for k, v in r.headers.items() if k.lower().startswith("access-control")})

d = json.loads(get("https://files.turath.io/data-v3.json"))
for aid, a in d["authors"].items():
    n = a.get("name", "")
    if "القيم" in n or n.startswith("مسلم") or "عثيمين" in n or a.get("death") in (261, 751):
        print("AUTHOR", aid, n, a.get("death"), len(a.get("books", [])))
for aid in ("54", "57", "62", "67", "202", "215", "217", "223", "362", "414"):
    a = d["authors"][aid]
    print("N", aid, a["name"], len(a["books"]), sum(d["books"][str(b)]["size"] for b in a["books"] if str(b) in d["books"]))
