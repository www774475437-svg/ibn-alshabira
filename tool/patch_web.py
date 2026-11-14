"""Runs on GitHub after `flutter create --platforms web`: Arabic title,
description and right-to-left page for the website."""
import json
import re
from pathlib import Path

TITLE = "ابن الشابرة — أجوبة الشيخ قايد بن غانم الشابرة"
DESC = ("أجوبة ومقالات وكتب ورسائل الشيخ قايد بن غانم الشابرة حفظه الله، "
        "مرتبة على أبواب العقيدة والفقه والآداب، مع البحث بالموضوع.")

index = Path("web/index.html")
h = index.read_text(encoding="utf-8")
h = re.sub(r"<html[^>]*>", '<html lang="ar" dir="rtl">', h, count=1)
h = re.sub(r"<title>.*?</title>", f"<title>{TITLE}</title>", h, count=1, flags=re.S)
h = re.sub(r'<meta name="description" content="[^"]*">', f'<meta name="description" content="{DESC}">', h, count=1)
SITE = "https://ibnalshabira.com/"
if 'property="og:title"' not in h:
    h = h.replace("</head>",
                  f'  <meta property="og:title" content="{TITLE}">\n'
                  f'  <meta property="og:description" content="{DESC}">\n'
                  f'  <meta property="og:image" content="{SITE}icons/Icon-512.png">\n'
                  f'  <meta property="og:url" content="{SITE}">\n'
                  f'  <meta property="og:type" content="website">\n'
                  f'  <meta name="twitter:card" content="summary">\n</head>', 1)
h = h.replace('content="ibn_alshabira"', 'content="ابن الشابرة"')
# A loading screen with the logo, shown until the app draws its first frame.
if 'id="loading"' not in h:
    h = h.replace("<body>", '''<body>
  <style>
    #loading { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
      justify-content: center; background: #1F5E3B; z-index: 9; transition: opacity .4s; }
    #loading img { width: 132px; height: 132px; border-radius: 50%; animation: pulse 1.6s ease-in-out infinite; }
    #loading p { color: #fff; font: 16px sans-serif; margin-top: 22px; }
    @keyframes pulse { 0%,100% { transform: scale(1); opacity: 1; } 50% { transform: scale(1.06); opacity: .8; } }
  </style>
  <div id="loading"><img src="icons/Icon-192.png" alt=""><p>جارٍ فتح «ابن الشابرة»…</p></div>
  <script>
    window.addEventListener('flutter-first-frame', function () {
      var l = document.getElementById('loading');
      if (l) { l.style.opacity = 0; setTimeout(function () { l.remove(); }, 450); }
    });
  </script>''', 1)
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
