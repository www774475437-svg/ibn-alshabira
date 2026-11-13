"""Pull the sheikh's public Telegram channel posts (t.me/s/qaidghsh) into
assets/data/channel.json, verbatim. Runs in the build; on any failure the
existing file is kept so the build never breaks."""
import html
import json
import os
import re
import sys
import time
import urllib.request

CHANNEL = 'qaidghsh'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'data', 'channel.json')
MAX_PAGES = 120

msg_re = re.compile(r'<div class="tgme_widget_message_wrap.*?(?=<div class="tgme_widget_message_wrap|\Z)', re.S)
post_re = re.compile(r'data-post="%s/(\d+)"' % CHANNEL)
text_re = re.compile(r'<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>', re.S)
time_re = re.compile(r'<time[^>]*datetime="([^"]+)"')


def clean(fragment):
    t = re.sub(r'<br\s*/?>', '\n', fragment)
    t = re.sub(r'<[^>]+>', '', t)
    t = html.unescape(t)
    t = re.sub(r'[ \t]+\n', '\n', t)
    t = re.sub(r'\n{3,}', '\n\n', t)
    return t.strip()


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Android 13) ibn-alshabira-build'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode('utf-8', 'replace')


def main():
    posts = {}
    before = None
    for page in range(MAX_PAGES):
        url = 'https://t.me/s/%s' % CHANNEL + ('?before=%d' % before if before else '')
        try:
            body = get(url)
        except Exception as e:
            print('fetch failed:', e)
            break
        found = []
        for block in msg_re.findall(body):
            m = post_re.search(block)
            if not m:
                continue
            pid = int(m.group(1))
            found.append(pid)
            tm = text_re.search(block)
            text = clean(tm.group(1)) if tm else ''
            if len(text) < 20:
                continue
            dt = time_re.search(block)
            posts[pid] = {'id': pid, 'text': text, 'date': dt.group(1)[:10] if dt else ''}
        if not found:
            break
        low = min(found)
        if before is not None and low >= before:
            break
        before = low
        if low <= 1:
            break
        time.sleep(0.4)
    if not posts:
        print('no posts fetched; keeping the existing file')
        return
    items = sorted(posts.values(), key=lambda p: -p['id'])
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(items, f, ensure_ascii=False)
    print('channel posts:', len(items), 'pages:', page + 1)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print('telegram fetch error:', e)
    sys.exit(0)
