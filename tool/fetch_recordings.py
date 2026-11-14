"""Lists the sheikh's voice recordings from his public channel (t.me/s/QaidSandVe)
into recordings.json: [{id, title, date, dur}]. The files themselves stay on
Telegram; the app asks Telegram for the playable link when the listener taps.
The first run reads the whole channel; later runs read only the newest pages.
Never fails the run."""
import html
import json
import os
import re
import time
import urllib.request
from pathlib import Path

CHANNEL = "QaidSandVe"
OUT = Path(os.environ.get("MEDIA_ROOT", ".")) / "recordings.json"

msg_re = re.compile(r'<div class="tgme_widget_message_wrap.*?(?=<div class="tgme_widget_message_wrap|\Z)', re.S)
post_re = re.compile(r'data-post="%s/(\d+)"' % CHANNEL)
text_re = re.compile(r'<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>', re.S)
time_re = re.compile(r'<time[^>]*datetime="([^"]+)"')
dur_re = re.compile(r'tgme_widget_message_voice_duration[^>]*>([^<]+)<')


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Android 13) ibn-alshabira-build"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def clean(fragment):
    t = re.sub(r"<br\s*/?>", "\n", fragment)
    t = re.sub(r"<[^>]+>", "", t)
    return html.unescape(t).strip()


def title_from(text):
    """The first meaningful line: no hashtags, links or decoration."""
    for line in text.split("\n"):
        line = re.sub(r"#\S+|https?://\S+|@\w+", "", line)
        line = re.sub(r"^[\s\W_]+|[\s\W_]+$", "", line, flags=re.U)
        if len(line) >= 4:
            return line[:110]
    return ""


def read_page(before=None):
    body = get(f"https://t.me/s/{CHANNEL}" + (f"?before={before}" if before else ""))
    posts = []
    for block in msg_re.findall(body):
        m = post_re.search(block)
        if not m:
            continue
        tm = text_re.search(block)
        dt = time_re.search(block)
        du = dur_re.search(block)
        posts.append({
            "id": int(m.group(1)),
            "voice": "tgme_widget_message_voice" in block,
            "text": clean(tm.group(1)) if tm else "",
            "date": dt.group(1)[:10] if dt else "",
            "dur": du.group(1).strip() if du else "",
        })
    return posts


def main():
    old = json.loads(OUT.read_text("utf-8")) if OUT.exists() else []
    known = max((r["id"] for r in old), default=0)
    posts = {}
    before = None
    for _ in range(400):
        try:
            page = read_page(before)
        except Exception as e:
            print("page failed:", e)
            break
        if not page:
            break
        for p in page:
            posts[p["id"]] = p
        low = min(p["id"] for p in page)
        # Read a few pages back past what we have, for titles of new ones.
        if known and low < known - 40:
            break
        if before is not None and low >= before:
            break
        before = low
        if low <= 1:
            break
        time.sleep(0.2)
    if not posts:
        print("nothing read; keeping the list")
        return
    by_id = {r["id"]: r for r in old}
    last_text, last_text_id = "", -99
    prev_title, part = "", 1
    for p in sorted(posts.values(), key=lambda x: x["id"]):
        if not p["voice"]:
            if p["text"]:
                last_text, last_text_id = title_from(p["text"]), p["id"]
            continue
        title = title_from(p["text"])
        if not title and last_text and p["id"] - last_text_id <= 6:
            title = last_text  # the title post just before the recordings
        if title and title == prev_title:
            part += 1
            shown = f"{title} — الجزء {part}"
        else:
            part = 1
            shown = title
        prev_title = title
        if not shown:
            shown = f"تسجيل صوتي {p['date']}".strip()
        if p["id"] in by_id and p["id"] <= known - 40:
            continue  # settled long ago; keep as it was
        by_id[p["id"]] = {"id": p["id"], "title": shown, "date": p["date"], "dur": p["dur"]}
    items = sorted(by_id.values(), key=lambda r: -r["id"])
    OUT.write_text(json.dumps(items, ensure_ascii=False, separators=(",", ":")), "utf-8")
    print("recordings:", len(items), "new:", len(items) - len(old))
    for r in items[:15]:
        print(r["id"], r["date"], r["dur"], r["title"])


try:
    main()
except Exception as ex:
    print("recordings list failed:", ex)
