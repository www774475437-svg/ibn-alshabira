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
    m = (re.search(r'"channelId":"(UC[\w-]{22})"', page)
         or re.search(r'channel_id=(UC[\w-]{22})', page)
         or re.search(r'"externalId":"(UC[\w-]{22})"', page))
    if not m:
        raise RuntimeError("channel id not found")
    feed = fetch(f"https://www.youtube.com/feeds/videos.xml?channel_id={m.group(1)}")
    videos = []
    for entry in feed.split("<entry>")[1:]:
        vid = re.search(r"<yt:videoId>([^<]+)</yt:videoId>", entry)
        title = re.search(r"<title>([^<]*)</title>", entry)
        pub = re.search(r"<published>([^<]+)</published>", entry)
        if vid and title:
            videos.append({"id": vid.group(1), "title": html.unescape(title.group(1)),
                           "published": (pub.group(1) if pub else "")[:10]})
    if videos:
        OUT.write_text(json.dumps(videos, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"channel {m.group(1)}: {len(videos)} videos")
except Exception as ex:
    print("YouTube not reachable:", ex)
