"""Runs on GitHub after `flutter create`: sets the Arabic app name."""
import re
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text(encoding="utf-8")
text = re.sub(r'android:label="[^"]*"', 'android:label="ابن الشابرة"', text, count=1)
manifest.write_text(text, encoding="utf-8")
print("App label set to: ابن الشابرة")
