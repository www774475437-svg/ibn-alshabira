"""Runs on GitHub after `flutter create --platforms web`: Arabic title,
description and right-to-left page for the website."""
import json
import re
from pathlib import Path

TITLE = "ابن الشابرة — أجوبة الشيخ قائد بن غانم الشابرة"
DESC = ("أجوبة ومقالات وكتب ورسائل الشيخ قائد بن غانم الشابرة حفظه الله، "
        "مرتبة على أبواب العقيدة والفقه والآداب، مع البحث بالموضوع.")

index = Path("web/index.html")
h = index.read_text(encoding="utf-8")
h = re.sub(r"<html[^>]*>", '<html lang="ar" dir="rtl">', h, count=1)
h = re.sub(r"<title>.*?</title>", f"<title>{TITLE}</title>", h, count=1, flags=re.S)
h = re.sub(r'<meta name="description" content="[^"]*">', f'<meta name="description" content="{DESC}">', h, count=1)
if 'property="og:title"' not in h:
    h = h.replace("</head>",
                  f'  <meta property="og:title" content="{TITLE}">\n'
                  f'  <meta property="og:description" content="{DESC}">\n</head>', 1)
h = h.replace('content="ibn_alshabira"', 'content="ابن الشابرة"')
index.write_text(h, encoding="utf-8")

manifest = Path("web/manifest.json")
data = json.loads(manifest.read_text(encoding="utf-8"))
data.update({"name": "ابن الشابرة", "short_name": "ابن الشابرة", "description": DESC,
             "background_color": "#1F5E3B", "theme_color": "#1F5E3B", "dir": "rtl", "lang": "ar"})
manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print("Web patched")

# Site icons (pre-made from the logo in tool/web_icons/)
import shutil
for name in ["Icon-192.png", "Icon-512.png", "Icon-maskable-192.png", "Icon-maskable-512.png"]:
    shutil.copy(f"tool/web_icons/{name}", f"web/icons/{name}")
shutil.copy("tool/web_icons/favicon.png", "web/favicon.png")
print("Web icons copied")
