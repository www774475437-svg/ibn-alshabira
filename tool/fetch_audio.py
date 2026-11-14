"""Takes the sheikh's voice recordings from his Telegram channel through the bot
(added there as an admin) and keeps them in the `media` folder:
media/audio.json + media/audio/<channel>_<message>.<ext>. Never fails the run."""
import json
import os
import time
import urllib.request
from pathlib import Path

TOKEN = os.environ.get("BOT_TOKEN", "").strip()
ROOT = Path(os.environ.get("MEDIA_ROOT", "."))
LIST = ROOT / "audio.json"
STATE = ROOT / "state.json"
MAX = 20 * 1024 * 1024  # the Bot API gives files up to 20 MB


def api(method, **params):
    q = "&".join(f"{k}={urllib.request.quote(str(v))}" for k, v in params.items())
    with urllib.request.urlopen(f"https://api.telegram.org/bot{TOKEN}/{method}?{q}", timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def main():
    if not TOKEN:
        print("no bot token")
        return
    (ROOT / "audio").mkdir(parents=True, exist_ok=True)
    items = json.loads(LIST.read_text("utf-8")) if LIST.exists() else []
    state = json.loads(STATE.read_text("utf-8")) if STATE.exists() else {"offset": 0}
    have = {i["key"] for i in items}
    res = api("getUpdates", offset=state["offset"], timeout=0, allowed_updates='["channel_post"]')
    added = 0
    for u in res.get("result", []):
        state["offset"] = u["update_id"] + 1
        post = u.get("channel_post") or {}
        media = post.get("audio") or post.get("voice")
        if not media:
            continue
        key = f'{post["chat"]["id"]}_{post["message_id"]}'
        if key in have:
            continue
        if media.get("file_size", 0) > MAX:
            print("too large:", key)
            continue
        info = api("getFile", file_id=media["file_id"])["result"]
        path = info["file_path"]
        ext = path.rsplit(".", 1)[-1] if "." in path else "ogg"
        name = f"audio/{key}.{ext}"
        urllib.request.urlretrieve(f"https://api.telegram.org/file/bot{TOKEN}/{path}", ROOT / name)
        title = (post.get("caption") or media.get("title") or "").strip().split("\n")[0][:120]
        date = time.strftime("%Y-%m-%d", time.gmtime(post.get("date", 0)))
        items.append({"key": key, "file": name, "title": title or f"تسجيل صوتي {date}",
                      "date": date, "seconds": media.get("duration", 0)})
        have.add(key)
        added += 1
    LIST.write_text(json.dumps(items, ensure_ascii=False, indent=1), "utf-8")
    STATE.write_text(json.dumps(state), "utf-8")
    print("new recordings:", added, "total:", len(items))


try:
    main()
except Exception as ex:
    print("audio fetch failed:", ex)
