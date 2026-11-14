"""Lists the recordings of the sheikh's public channel (t.me/s/QaidSandVe) into
recordings.json: {"v": 2, "items": [{id, k, t, b, d, u}]}
  k: "v" voice note (the app plays it, asking Telegram for the link),
     "a" audio file (played in the app once the bot has it, else in Telegram)
  t: title, b: speaker, d: date, u: duration.
Each recording's title comes from the post that describes it (the post that
links to it, or the one right after it). The whole channel is read when the
list is new; later runs read only the newest pages. Never fails the run."""
import html
import json
import os
import re
import time
import urllib.request
from pathlib import Path

CHANNEL = "QaidSandVe"
VERSION = 6
OUT = Path(os.environ.get("MEDIA_ROOT", ".")) / "recordings.json"

msg_re = re.compile(r'<div class="tgme_widget_message_wrap.*?(?=<div class="tgme_widget_message_wrap|\Z)', re.S)
post_re = re.compile(r'data-post="%s/(\d+)"' % CHANNEL)
text_re = re.compile(r'<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>', re.S)
time_re = re.compile(r'<time[^>]*datetime="([^"]+)"')
vdur_re = re.compile(r'tgme_widget_message_voice_duration[^>]*>([^<]+)<')
dtitle_re = re.compile(r'tgme_widget_message_document_title[^>]*>([^<]*)<')
dextra_re = re.compile(r'tgme_widget_message_document_extra[^>]*>([^<]*)<')
link_re = re.compile(r't\.me/%s/(\d+)' % CHANNEL, re.I)
SKIP = ("http", "للإستماع", "للاستماع", "🎙", "⌚", "🗓", "🕌", "🦻", "المدة", "تفضل", "رابط")
PART = re.compile(r"^(المسألة|المسالة|الدرس|الحلقة|المجلس|الشريط|المحاضرة|الجزء|اللقاء|الفصل|الباب)")
LETTER = re.compile(r"[ء-ي0-9A-Za-z]")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Android 13) ibn-alshabira-build"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def clean(fragment):
    t = re.sub(r"<br\s*/?>", "\n", fragment)
    t = re.sub(r"<[^>]+>", "", t)
    return html.unescape(t).replace("‏", "").replace("‎", "").replace("\xa0", " ").strip()


def trim_edges(s):
    """Removes emojis, marks and spaces around the words."""
    i, j = 0, len(s)
    while i < j and not LETTER.match(s[i]) and s[i] not in "(«\"":
        i += 1
    while j > i and not LETTER.match(s[j - 1]) and s[j - 1] not in ")»?؟!\".":
        j -= 1
    return s[i:j].strip()


def shorten(s, n=110):
    s = re.sub(r"\s+", " ", s).strip()
    if len(s) <= n:
        return s
    cut = s[:n].rsplit(" ", 1)[0]
    return cut + "…"


def generic(s):
    return not s or s.startswith("مقطع صوتي") or s.lower() in ("audio", "voice")


def title_of(text):
    lines = []
    for raw in text.split("\n"):
        line = raw.strip()
        if trim_edges(line).startswith("محتويات"):
            break  # what follows is the list of the lesson's points
        if not line or line.startswith("#") or any(k in line for k in SKIP):
            continue
        core = trim_edges(line)
        if len(core) < 3 or core in ("سلسلة", "بعنوان") or core.endswith("بعنوان") or generic(core):
            continue
        decorated = not LETTER.match(line[0]) and not LETTER.match(line[-1]) and line[-1] not in ")»?؟!."
        lines.append((core, decorated))
    if not lines:
        return ""
    main = next((i for i, (_, d) in enumerate(lines) if d), None)
    if main is None:
        return shorten(lines[0][0])
    t = lines[main][0]
    if main + 1 < len(lines) and PART.match(lines[main + 1][0]):
        t += " — " + lines[main + 1][0]
    return shorten(t)


def lesson_title(text):
    """For lesson posts that list their points: series — lesson: first point."""
    series = lesson = point = ""
    for raw in text.split("\n"):
        line = raw.strip()
        if not series and line.startswith("#"):
            series = trim_edges(line.split()[0].replace("_", " "))
        core = trim_edges(line)
        if not lesson and PART.match(core) and len(core) < 40:
            lesson = core
        if not point and line.startswith("■"):
            point = re.sub(r"^[\d:]+\s*", "", trim_edges(line))
    parts = [x for x in (series, lesson) if x]
    t = " — ".join(parts)
    if point:
        t = f"{t}: {point}" if t else point
    return shorten(t) if t else ""


def speaker_of(text, extra):
    for line in text.split("\n"):
        if "🎙" in line:
            s = trim_edges(line.replace("🎙", ""))
            s = re.sub(r"^(لشيخنا|لفضيلة الشيخ|لفضيلة|للشيخ|لسماحة الشيخ)\s+", "", s)
            s = re.sub(r"\s*(حفظه الله.*|رحمه الله.*|-?\s*حفظه.*)$", "", s)
            return shorten(s, 60)
    e = trim_edges(re.sub(r"-?\s*حفظه الله.*$", "", extra or ""))
    return shorten(e, 60) if len(e) > 3 and "MB" not in e and "KB" not in e else ""


def read_page(before=None):
    body = get(f"https://t.me/s/{CHANNEL}" + (f"?before={before}" if before else ""))
    posts = []
    for block in msg_re.findall(body):
        m = post_re.search(block)
        if not m:
            continue
        kind = ""
        if "tgme_widget_message_voice" in block:
            kind = "v"
        elif "tgme_widget_message_document" in block:
            ex = dextra_re.search(block)
            # Only sound files (the extra line shows a duration or a performer, not a size like 2.1 MB).
            extra = clean(ex.group(1)) if ex else ""
            kind = "a" if not re.search(r"\b\d+(\.\d+)?\s*(KB|MB|GB)\b", extra) else ""
        tm = text_re.search(block)
        dt = time_re.search(block)
        du = vdur_re.search(block)
        dti = dtitle_re.search(block)
        dex = dextra_re.search(block)
        posts.append({
            "id": int(m.group(1)), "kind": kind,
            "text": clean(tm.group(1)) if tm else "",
            "date": dt.group(1)[:10] if dt else "",
            "dur": du.group(1).strip() if du else "",
            "dtitle": clean(dti.group(1)) if dti else "",
            "dextra": clean(dex.group(1)) if dex else "",
        })
    return posts


def main():
    old = {}
    if OUT.exists():
        try:
            j = json.loads(OUT.read_text("utf-8"))
            if isinstance(j, dict) and j.get("v") == VERSION:
                old = {r["id"]: r for r in j["items"]}
        except Exception:
            pass
    known = max(old, default=0)
    posts, before = {}, None
    for _ in range(500):
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
        if known and low < known - 30:
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
    # The post that links to a recording describes it.
    linked = {}
    for p in posts.values():
        if not p["kind"]:
            for n in link_re.findall(p["text"]):
                linked.setdefault(int(n), p)
    ids = sorted(posts)
    items = dict(old)
    for idx, i in enumerate(ids):
        p = posts[i]
        if not p["kind"]:
            continue
        desc = linked.get(i)
        if desc is None:
            # Else the text post right after it, if it does not belong to another recording.
            for nxt in ids[idx + 1: idx + 3]:
                q = posts[nxt]
                if q["kind"]:
                    break
                if q["text"] and not link_re.search(q["text"]):
                    desc = q
                    break
        text = desc["text"] if desc else ""
        t = title_of(text) or lesson_title(text) or title_of(p["text"])
        file_title = "" if generic(p["dtitle"]) else shorten(trim_edges(p["dtitle"].replace("#", " ").replace("_", " ")))
        if (not t or t.startswith("محتويات")) and len(file_title) > 6:
            t = file_title
        t = re.sub(r"\s+", " ", t.replace("#", " ").replace("_", " ")).strip()

        if not t:
            t = f"تسجيل صوتي {p['date']}".strip()
        dur = p["dur"] if p["dur"] not in ("", "0:00") else ""
        if not dur:
            m = re.search(r"المدة\s*:?\s*([\d:]{4,8})", text)
            dur = m.group(1) if m else ""
        items[i] = {"id": i, "k": p["kind"], "t": t, "b": speaker_of(text or p["text"], p["dextra"]),
                    "d": p["date"], "u": dur}
    out = sorted(items.values(), key=lambda r: -r["id"])
    OUT.write_text(json.dumps({"v": VERSION, "items": out}, ensure_ascii=False, separators=(",", ":")), "utf-8")
    print("recordings:", len(out), "voice:", sum(r["k"] == "v" for r in out), "files:", sum(r["k"] == "a" for r in out))
    for r in out[:12] + out[len(out) // 2: len(out) // 2 + 12] + out[-8:]:
        print(r["id"], r["k"], r["d"], r["u"], "|", r["t"], "|", r["b"])


try:
    main()
except Exception as ex:
    print("recordings list failed:", ex)
