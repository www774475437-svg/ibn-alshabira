"""Runs on GitHub before each build: latest videos of the sheikh's YouTube
channel -> assets/data/videos.json. Never fails the build."""
import html
import json
import re
import urllib.request
from pathlib import Path

HANDLE = "qaidghsh"
OUT = Path("assets/data/videos.json")
HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
    "Accept-Language": "ar,en;q=0.8",
    "Cookie": "CONSENT=YES+1; SOCS=CAI",
}


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=40) as r:
        return r.read().decode("utf-8", "replace")


try:
    page = ""
    for url in (f"https://www.youtube.com/@{HANDLE}/videos", f"https://www.youtube.com/@{HANDLE}",
                f"https://m.youtube.com/@{HANDLE}", f"https://www.youtube.com/c/{HANDLE}",
                f"https://www.youtube.com/user/{HANDLE}"):
        try:
            page = fetch(url)
            if "UC" in page:
                break
        except Exception as e:
            print("tried", url, "->", e)
    title = re.search(r"<title>([^<]*)</title>", page)
    print("page:", len(page), "chars, title:", title.group(1) if title else None)
    ids = []
    for pat in (r'"externalId":"(UC[\w-]{22})"', r'"browseId":"(UC[\w-]{22})"', r'/channel/(UC[\w-]{22})',
                r'channel_id=(UC[\w-]{22})', r'"channelId":"(UC[\w-]{22})"'):
        for found in re.findall(pat, page):
            if found not in ids:
                ids.append(found)
    print("channel ids seen:", ids[:6])
    feed = ""
    for cid in ids[:6]:
        try:
            feed = fetch(f"https://www.youtube.com/feeds/videos.xml?channel_id={cid}")
            if "<entry>" in feed:
                print("feed of", cid)
                break
        except Exception as e:
            print("feed", cid, "->", e)
    if "<entry>" not in feed:
        try:
            feed = fetch(f"https://www.youtube.com/feeds/videos.xml?user={HANDLE}")
        except Exception as e:
            print("feed by name ->", e)
    videos = []
    for entry in feed.split("<entry>")[1:]:
        vid = re.search(r"<yt:videoId>([^<]+)</yt:videoId>", entry)
        title = re.search(r"<title>([^<]*)</title>", entry)
        pub = re.search(r"<published>([^<]+)</published>", entry)
        if vid and title:
            videos.append({"id": vid.group(1), "title": html.unescape(title.group(1)),
                           "published": (pub.group(1) if pub else "")[:10]})
    if not videos:
        # The feed is closed to this server: read the videos listed on the channel page itself.
        seen = set()
        for m in re.finditer(r'"videoRenderer":\{"videoId":"([\w-]{11})"', page):
            vid = m.group(1)
            if vid in seen:
                continue
            chunk = page[m.end():m.end() + 3000]
            t = re.search(r'"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"', chunk)
            if t:
                seen.add(vid)
                videos.append({"id": vid, "title": json.loads('"' + t.group(1) + '"'), "published": ""})
        print("from the channel page:", len(videos))
    if videos:
        OUT.write_text(json.dumps(videos, ensure_ascii=False, indent=1), encoding="utf-8")
    print(len(videos), "videos")
    if not videos:
        raise RuntimeError("empty feed")
except Exception as ex:
    print("YouTube not reachable:", ex)
    # Keep the last good list (the one the live site already shows).
    try:
        old = json.loads(fetch("https://ibnalshabira.com/assets/assets/data/videos.json"))
        if old:
            OUT.write_text(json.dumps(old, ensure_ascii=False, indent=1), encoding="utf-8")
            print("kept the last list:", len(old), "videos")
    except Exception as ex2:
        print("no earlier list:", ex2)
