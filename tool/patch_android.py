"""Runs on GitHub after `flutter create`: Arabic app name, permissions,
notification receivers and core-library desugaring (needed by notifications)."""
import re
from pathlib import Path

# --- AndroidManifest.xml -------------------------------------------------
manifest = Path("android/app/src/main/AndroidManifest.xml")
m = manifest.read_text(encoding="utf-8")
m = re.sub(r'android:label="[^"]*"', 'android:label="ابن الشابرة"', m, count=1)

permissions = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.RECORD_AUDIO",
]
for p in permissions:
    if p not in m:
        m = m.replace("<application", f'<uses-permission android:name="{p}"/>\n    <application', 1)

# Voice search and «اقرأ لي» need to see the phone's speech services.
if "android.speech.RecognitionService" not in m:
    q = ('<intent><action android:name="android.speech.RecognitionService"/></intent>'
         '<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>')
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>" + q, 1)
    else:
        m = m.replace("<application", "<queries>" + q + "</queries>\n    <application", 1)

receivers = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", receivers + "    </application>", 1)
manifest.write_text(m, encoding="utf-8")
print("Manifest patched")

# --- build.gradle(.kts): desugaring ------------------------------------
kts = Path("android/app/build.gradle.kts")
groovy = Path("android/app/build.gradle")
if kts.exists():
    g = kts.read_text(encoding="utf-8")
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
    if "desugar_jdk_libs" not in g:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(g, encoding="utf-8")
    print("build.gradle.kts patched")
elif groovy.exists():
    g = groovy.read_text(encoding="utf-8")
    if "coreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", g, count=1)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(g, encoding="utf-8")
    print("build.gradle patched")

# --- Permanent release signing key (decrypted by the workflow when the
#     KEY_PASSWORD secret exists; otherwise the debug key is used) --------
if kts.exists():
    g = kts.read_text(encoding="utf-8")
    if "keyProps" not in g:
        g = "import java.util.Properties\n" + g
        g = g.replace("android {", '''val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {''', 1)
        g = g.replace("    buildTypes {", '''    signingConfigs {
        if (keyProps.isNotEmpty()) {
            create("release") {
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
            }
        }
    }

    buildTypes {''', 1)
        g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = if (keyProps.isNotEmpty()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")', 1)
        kts.write_text(g, encoding="utf-8")
        print("Release signing configured")

# --- Launch screen background: dark green instead of white ---------------
for d in ["drawable", "drawable-v21"]:
    lb = Path(f"android/app/src/main/res/{d}/launch_background.xml")
    if lb.exists():
        lb.write_text('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item><color android:color="#0A2417" /></item>
</layer-list>
''', encoding="utf-8")
print("Launch background set")

# --- Choosable phone icon («شعار التطبيق»): launcher aliases -------------
import glob, shutil
res = Path("android/app/src/main/res/mipmap-xxxhdpi")
res.mkdir(parents=True, exist_ok=True)
for n in ("logo_green", "logo3"):
    shutil.copy(f"tool/launcher/ic_{n}.png", res / f"ic_{n}.png")
m = manifest.read_text(encoding="utf-8")
if "activity-alias" not in m:
    launcher = re.compile(r'\s*<intent-filter>\s*<action android:name="android.intent.action.MAIN"\s*/>\s*'
                          r'<category android:name="android.intent.category.LAUNCHER"\s*/>\s*</intent-filter>')
    assert launcher.search(m), "launcher intent-filter not found"
    m = launcher.sub("", m, count=1)
    def alias(name, icon, on):
        return (f'\n        <activity-alias android:name=".{name}" android:targetActivity=".MainActivity"'
                f' android:enabled="{"true" if on else "false"}" android:exported="true"'
                f' android:icon="@mipmap/{icon}" android:label="ابن الشابرة">'
                '<intent-filter><action android:name="android.intent.action.MAIN"/>'
                '<category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity-alias>')
    aliases = alias("IconMain", "ic_launcher", True) + alias("IconGreen", "ic_logo_green", False) + alias("IconGold", "ic_logo3", False)
    i = m.index("</activity>") + len("</activity>")
    m = m[:i] + aliases + m[i:]
    manifest.write_text(m, encoding="utf-8")
    print("Icon aliases added")

for f in glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True):
    k = Path(f).read_text(encoding="utf-8")
    if "ibn_alshabira/icon" in k:
        continue
    pkg = re.search(r"^package\s+(\S+)", k, re.M).group(1)
    base = re.search(r"class MainActivity\s*:\s*(\w+)", k).group(1)
    Path(f).write_text(f"""package {pkg}

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.{base}
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : {base}() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ibn_alshabira/icon").setMethodCallHandler {{ call, result ->
            if (call.method == "set") {{
                val chosen = (call.arguments as? Int) ?: 0
                val names = listOf("IconMain", "IconGreen", "IconGold")
                val pm = packageManager
                try {{
                    // The chosen icon first, so the app is never without one.
                    pm.setComponentEnabledSetting(ComponentName(this, "$packageName.${{names[chosen]}}"),
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                    names.forEachIndexed {{ i, n ->
                        if (i != chosen) pm.setComponentEnabledSetting(ComponentName(this, "$packageName.$n"),
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                    }}
                    result.success(true)
                }} catch (e: Exception) {{
                    result.error("icon", e.message, null)
                }}
            }} else {{
                result.notImplemented()
            }}
        }}
    }}
}}
""", encoding="utf-8")
    print("MainActivity: icon channel added")
