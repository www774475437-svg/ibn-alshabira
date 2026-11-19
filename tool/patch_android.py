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
    // A widget that was tapped: the app opens on its page.
    private var pendingOpen: String? = null

    override fun onNewIntent(intent: android.content.Intent) {{
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("open")?.let {{ pendingOpen = it }}
    }}

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        intent?.getStringExtra("open")?.let {{ pendingOpen = it }}
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
            }} else if (call.method == "widget") {{
                val a = call.arguments as? Map<*, *>
                getSharedPreferences("prayer_widget", MODE_PRIVATE).edit()
                    .putString("times", (a?.get("times") as? String) ?: "")
                    .putString("place", (a?.get("place") as? String) ?: "")
                    .putString("hijri", (a?.get("hijri") as? String) ?: "")
                    .apply()
                PrayerWidget.refresh(this)
                result.success(true)
            }} else if (call.method == "pinWidget") {{
                var ok = false
                val cls: Class<*> = when (call.arguments as? String) {{
                    "answer" -> AnswerWidget::class.java
                    "dhikr" -> DhikrWidget::class.java
                    "read" -> ReadWidget::class.java
                    "quiz" -> QuizWidget::class.java
                    "tour" -> TourWidget::class.java
                    else -> PrayerWidget::class.java
                }}
                if (android.os.Build.VERSION.SDK_INT >= 26) {{
                    val mgr = android.appwidget.AppWidgetManager.getInstance(this)
                    if (mgr.isRequestPinAppWidgetSupported) {{
                        ok = mgr.requestPinAppWidget(ComponentName(this, cls), null, null)
                    }}
                }}
                result.success(ok)
            }} else if (call.method == "widgets") {{
                val a = call.arguments as? Map<*, *>
                val e = getSharedPreferences("app_widgets", MODE_PRIVATE).edit()
                a?.forEach {{ (k, v) ->
                    when (v) {{
                        is String -> e.putString(k.toString(), v)
                        is Int -> e.putLong(k.toString(), v.toLong())
                        is Long -> e.putLong(k.toString(), v)
                    }}
                }}
                e.apply()
                InfoWidget.refreshAll(this)
                result.success(true)
            }} else if (call.method == "takeLaunch") {{
                val t = pendingOpen
                pendingOpen = null
                result.success(t)
            }} else {{
                result.notImplemented()
            }}
        }}
    }}
}}
""", encoding="utf-8")
    print("MainActivity: icon channel added")


# --- Prayer-times home-screen widget («مواقيت الصلاة») -------------------
# The app hands it the next three days of times (MainActivity "widget");
# the widget picks the next prayer itself, counts down, and changes its sky.
for f in glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True):
    pkg = re.search(r"^package\s+(\S+)", Path(f).read_text(encoding="utf-8"), re.M).group(1)
    Path(f).with_name("PrayerWidget.kt").write_text(f"""package {pkg}

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.SystemClock
import android.widget.RemoteViews
import java.util.Calendar

class PrayerWidget : AppWidgetProvider() {{
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {{
        for (id in ids) manager.updateAppWidget(id, build(context))
        schedule(context)
    }}

    override fun onReceive(context: Context, intent: Intent) {{
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) refresh(context)
    }}

    companion object {{
        const val ACTION_TICK = "com.ibnalshabira.PRAYER_TICK"
        private val names = listOf("الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء")
        private val timeIds = listOf(R.id.t0, R.id.t1, R.id.t2, R.id.t3, R.id.t4, R.id.t5)
        private val nameIds = listOf(R.id.n0, R.id.n1, R.id.n2, R.id.n3, R.id.n4, R.id.n5)
        private const val GOLD = 0xFFE0B35A.toInt()

        fun refresh(context: Context) {{
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, PrayerWidget::class.java))
            for (id in ids) mgr.updateAppWidget(id, build(context))
            schedule(context)
        }}

        private fun times(context: Context): List<Long> =
            (context.getSharedPreferences("prayer_widget", Context.MODE_PRIVATE).getString("times", "") ?: "")
                .split(",").mapNotNull {{ it.toLongOrNull() }}

        private fun hm(ms: Long): String {{
            val c = Calendar.getInstance().apply {{ timeInMillis = ms }}
            var h = c.get(Calendar.HOUR_OF_DAY) % 12
            if (h == 0) h = 12
            return "$h:" + c.get(Calendar.MINUTE).toString().padStart(2, '0')
        }}

        private fun build(context: Context): RemoteViews {{
            val v = RemoteViews(context.packageName, R.layout.prayer_widget)
            val prefs = context.getSharedPreferences("prayer_widget", Context.MODE_PRIVATE)
            val all = times(context)
            val now = System.currentTimeMillis()
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (open != null) {{
                v.setOnClickPendingIntent(R.id.root, PendingIntent.getActivity(context, 0, open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }}
            if (all.size < 6) {{
                v.setTextViewText(R.id.nextName, "افتح التطبيق")
                v.setTextViewText(R.id.nextTime, "لحساب المواقيت")
                return v
            }}
            // Today = the first six times whose day is today (or the next set).
            var start = 0
            while (start + 6 <= all.size && all[start + 5] < now - 6 * 3600000L) start += 6
            if (start + 6 > all.size) start = all.size - 6
            val day = all.subList(start, start + 6)
            var nextIdx = -1
            var nextAt = 0L
            for (i in start until all.size) {{
                if ((i - start) % 6 == 1) continue
                if (all[i] > now) {{ nextIdx = (i - start) % 6; nextAt = all[i]; break }}
            }}
            for (i in 0 until 6) {{
                v.setTextViewText(timeIds[i], hm(day[i]))
                val c = if (i == nextIdx) GOLD else Color.WHITE
                v.setTextColor(timeIds[i], c)
                v.setTextColor(nameIds[i], c)
            }}
            if (nextIdx >= 0) {{
                v.setTextViewText(R.id.nextName, names[nextIdx])
                v.setTextViewText(R.id.nextTime, hm(nextAt))
                val base = SystemClock.elapsedRealtime() + (nextAt - now)
                v.setChronometer(R.id.count, base, null, true)
                if (Build.VERSION.SDK_INT >= 24) v.setChronometerCountDown(R.id.count, true)
            }}
            v.setTextViewText(R.id.hijri, prefs.getString("hijri", "") ?: "")
            v.setTextViewText(R.id.place, prefs.getString("place", "") ?: "")
            // The sky for this moment.
            val sky = when {{
                now < day[0] -> R.drawable.sky_night
                now < day[1] -> R.drawable.sky_dawn
                now < day[1] + 3600000L -> R.drawable.sky_sunrise
                now < day[3] -> R.drawable.sky_morning
                now < day[4] - 40 * 60000L -> R.drawable.sky_afternoon
                now < day[4] + 25 * 60000L -> R.drawable.sky_sunset
                now < day[5] -> R.drawable.sky_dusk
                else -> R.drawable.sky_night
            }}
            v.setInt(R.id.root, "setBackgroundResource", sky)
            return v
        }}

        /** Wakes the widget at the next change (next prayer or sky). */
        private fun schedule(context: Context) {{
            val now = System.currentTimeMillis()
            val all = times(context)
            val marks = all.flatMap {{ listOf(it - 40 * 60000L, it, it + 25 * 60000L, it + 3600000L) }}
            val next = marks.filter {{ it > now + 1000 }}.minOrNull() ?: (now + 30 * 60000L)
            val i = Intent(context, PrayerWidget::class.java).setAction(ACTION_TICK)
            val pi = PendingIntent.getBroadcast(context, 7, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.set(AlarmManager.RTC, next, pi)
        }}
    }}
}}
""", encoding="utf-8")
    print("PrayerWidget.kt written")

res_main = Path("android/app/src/main/res")
(res_main / "layout").mkdir(parents=True, exist_ok=True)
(res_main / "xml").mkdir(parents=True, exist_ok=True)
(res_main / "drawable").mkdir(parents=True, exist_ok=True)
skies = {
    "night": ("#070B1E", "#1B2A5C", "#0B1230"),
    "dawn": ("#14204A", "#8E6A9E", "#E59A7A"),
    "sunrise": ("#3D5A9E", "#F2A65A", "#E76F51"),
    "morning": ("#1E6FB8", "#6FB6EA", "#3A86C8"),
    "afternoon": ("#2C77B5", "#9CC2DE", "#DDA35A"),
    "sunset": ("#2B1E4F", "#D25F5D", "#F6B15D"),
    "dusk": ("#0E1638", "#5A3C76", "#1C2350"),
}
for k, (a, b, c) in skies.items():
    (res_main / "drawable" / f"sky_{k}.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <corners android:radius="24dp"/>
    <gradient android:angle="315" android:startColor="{a}" android:centerColor="{b}" android:endColor="{c}" android:type="linear"/>
</shape>
""", encoding="utf-8")
(res_main / "drawable" / "pill.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <corners android:radius="14dp"/>
    <solid android:color="#33000000"/>
</shape>
""", encoding="utf-8")
cells = "".join(f"""
        <LinearLayout android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
            android:orientation="vertical" android:gravity="center" android:background="@drawable/pill"
            android:layout_marginStart="2dp" android:layout_marginEnd="2dp" android:paddingTop="5dp" android:paddingBottom="5dp">
            <TextView android:id="@+id/n{i}" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="{n}" android:textColor="#FFFFFF" android:textSize="11sp" android:textStyle="bold"/>
            <TextView android:id="@+id/t{i}" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="--:--" android:textColor="#FFFFFF" android:textSize="13sp" android:textStyle="bold"/>
        </LinearLayout>""" for i, n in enumerate(["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]))
(res_main / "layout" / "prayer_widget.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/root" android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="vertical" android:padding="12dp" android:layoutDirection="rtl"
    android:background="@drawable/sky_night">
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical">
        <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content" android:orientation="vertical">
            <TextView android:id="@+id/nextName" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="مواقيت الصلاة" android:textColor="#E0B35A" android:textSize="18sp" android:textStyle="bold"/>
            <TextView android:id="@+id/nextTime" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="" android:textColor="#FFFFFF" android:textSize="16sp" android:textStyle="bold"/>
        </LinearLayout>
        <TextView android:id="@+id/hijri" android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
            android:gravity="center" android:text="" android:textColor="#FFFFFF" android:textSize="14sp"/>
        <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content" android:orientation="vertical" android:gravity="end">
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="بعد"
                android:textColor="#DDFFFFFF" android:textSize="12sp"/>
            <Chronometer android:id="@+id/count" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="#E0B35A" android:textSize="18sp" android:textStyle="bold"/>
        </LinearLayout>
    </LinearLayout>
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal"
        android:layout_marginTop="8dp">{cells}
    </LinearLayout>
    <TextView android:id="@+id/place" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:gravity="center" android:layout_marginTop="5dp" android:text="" android:textColor="#CCFFFFFF" android:textSize="11sp"/>
</LinearLayout>
""", encoding="utf-8")
(res_main / "xml" / "prayer_widget_info.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp" android:minHeight="110dp"
    android:targetCellWidth="4" android:targetCellHeight="2"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/prayer_widget"
    android:previewLayout="@layout/prayer_widget"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:description="@string/prayer_widget_desc"/>
""", encoding="utf-8")
(res_main / "values").mkdir(parents=True, exist_ok=True)
strings = res_main / "values" / "widget_strings.xml"
strings.write_text("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="prayer_widget_desc">مواقيت الصلاة</string>
</resources>
""", encoding="utf-8")
m = manifest.read_text(encoding="utf-8")
if "PrayerWidget" not in m:
    m = m.replace("</application>", """        <receiver android:name=".PrayerWidget" android:exported="false" android:label="مواقيت الصلاة">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
                <action android:name="com.ibnalshabira.PRAYER_TICK"/>
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/prayer_widget_info"/>
        </receiver>
    </application>""", 1)
if "ACCESS_COARSE_LOCATION" not in m:
    m = m.replace("<application", '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <application', 1)
manifest.write_text(m, encoding="utf-8")
print("Prayer widget added")


# --- More home-screen widgets ---------------------------------------------
# One calm card design in four colours; the app writes their text
# (MainActivity "widgets") and a tap opens the app on that page.
for f in glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True):
    pkg = re.search(r"^package\s+(\S+)", Path(f).read_text(encoding="utf-8"), re.M).group(1)
    Path(f).with_name("InfoWidget.kt").write_text(f"""package {pkg}

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews

abstract class InfoWidget : AppWidgetProvider() {{
    abstract val key: String
    abstract val bg: Int
    abstract val label: String
    abstract val code: Int

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {{
        for (id in ids) manager.updateAppWidget(id, build(context))
    }}

    fun build(context: Context): RemoteViews {{
        val p = context.getSharedPreferences("app_widgets", Context.MODE_PRIVATE)
        val v = RemoteViews(context.packageName, R.layout.info_widget)
        v.setInt(R.id.wroot, "setBackgroundResource", bg)
        v.setTextViewText(R.id.wlabel, p.getString(key + "_label", label) ?: label)
        v.setTextViewText(R.id.wtitle, p.getString(key + "_title", "افتح التطبيق مرة") ?: "")
        v.setTextViewText(R.id.wbody, p.getString(key + "_body", "") ?: "")
        v.setTextViewText(R.id.wfoot, p.getString(key + "_foot", "ابن الشابرة") ?: "")
        val at = p.getLong(key + "_at", 0L)
        val now = System.currentTimeMillis()
        if (at > now) {{
            v.setViewVisibility(R.id.wcount, View.VISIBLE)
            v.setChronometer(R.id.wcount, SystemClock.elapsedRealtime() + (at - now), null, true)
            if (Build.VERSION.SDK_INT >= 24) v.setChronometerCountDown(R.id.wcount, true)
        }} else {{
            v.setViewVisibility(R.id.wcount, View.GONE)
        }}
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (open != null) {{
            open.putExtra("open", p.getString(key + "_open", key) ?: key)
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            v.setOnClickPendingIntent(R.id.wroot, PendingIntent.getActivity(context, code, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }}
        return v
    }}

    companion object {{
        fun refreshAll(context: Context) {{
            val mgr = AppWidgetManager.getInstance(context)
            for (w in listOf(AnswerWidget(), DhikrWidget(), ReadWidget(), QuizWidget(), TourWidget())) {{
                val ids = mgr.getAppWidgetIds(ComponentName(context, w.javaClass))
                for (id in ids) mgr.updateAppWidget(id, w.build(context))
            }}
        }}
    }}
}}

class AnswerWidget : InfoWidget() {{
    override val key = "answer"; override val bg = R.drawable.w_navy; override val label = "جواب اليوم"; override val code = 31
}}
class DhikrWidget : InfoWidget() {{
    override val key = "dhikr"; override val bg = R.drawable.w_green; override val label = "ذِكر"; override val code = 32
}}
class ReadWidget : InfoWidget() {{
    override val key = "read"; override val bg = R.drawable.w_gold; override val label = "قراءتي هذا الشهر"; override val code = 33
}}
class QuizWidget : InfoWidget() {{
    override val key = "quiz"; override val bg = R.drawable.w_night; override val label = "سؤال اليوم"; override val code = 34
}}
class TourWidget : InfoWidget() {{
    override val key = "tour"; override val bg = R.drawable.w_navy; override val label = "بطولة الجمعة"; override val code = 35
}}
""", encoding="utf-8")
    print("InfoWidget.kt written")

for k, (a, b, c) in {
    "navy": ("#0B2230", "#16404B", "#2E6B73"),
    "green": ("#082E22", "#14532D", "#2F7A4D"),
    "gold": ("#3A2A0C", "#7A5A22", "#C9A54C"),
    "night": ("#0B1230", "#1B2A5C", "#3A2E6B"),
}.items():
    (res_main / "drawable" / f"w_{k}.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <corners android:radius="26dp"/>
    <gradient android:angle="315" android:startColor="{a}" android:centerColor="{b}" android:endColor="{c}" android:type="linear"/>
</shape>
""", encoding="utf-8")
(res_main / "layout" / "info_widget.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wroot" android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="vertical" android:padding="14dp" android:layoutDirection="rtl"
    android:background="@drawable/w_navy">
    <TextView android:id="@+id/wlabel" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="" android:textColor="#E0B35A" android:textSize="12sp" android:textStyle="bold" android:gravity="start"/>
    <TextView android:id="@+id/wtitle" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="4dp" android:text="" android:textColor="#FFFFFF" android:textSize="16sp"
        android:textStyle="bold" android:maxLines="2" android:ellipsize="end" android:gravity="start"/>
    <TextView android:id="@+id/wbody" android:layout_width="match_parent" android:layout_height="0dp" android:layout_weight="1"
        android:layout_marginTop="4dp" android:text="" android:textColor="#E6FFFFFF" android:textSize="13sp"
        android:maxLines="4" android:ellipsize="end" android:lineSpacingMultiplier="1.15" android:gravity="start"/>
    <Chronometer android:id="@+id/wcount" android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:textColor="#E0B35A" android:textSize="22sp" android:textStyle="bold" android:visibility="gone"/>
    <TextView android:id="@+id/wfoot" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="ابن الشابرة" android:textColor="#AAFFFFFF" android:textSize="11sp" android:gravity="end"/>
</LinearLayout>
""", encoding="utf-8")
names = {"answer": ("AnswerWidget", "جواب اليوم"), "dhikr": ("DhikrWidget", "ذِكر"), "read": ("ReadWidget", "قراءتي هذا الشهر"),
         "quiz": ("QuizWidget", "سؤال اليوم"), "tour": ("TourWidget", "بطولة الجمعة")}
st = strings.read_text(encoding="utf-8")
for k, (cls, label) in names.items():
    (res_main / "xml" / f"{k}_widget_info.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp" android:minHeight="110dp"
    android:targetCellWidth="4" android:targetCellHeight="2"
    android:updatePeriodMillis="3600000"
    android:initialLayout="@layout/info_widget"
    android:previewLayout="@layout/info_widget"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:description="@string/{k}_widget_desc"/>
""", encoding="utf-8")
    if f"{k}_widget_desc" not in st:
        st = st.replace("</resources>", f'    <string name="{k}_widget_desc">{label}</string>\n</resources>')
strings.write_text(st, encoding="utf-8")
m = manifest.read_text(encoding="utf-8")
for k, (cls, label) in names.items():
    if f'.{cls}"' in m:
        continue
    m = m.replace("</application>", f"""        <receiver android:name=".{cls}" android:exported="false" android:label="{label}">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/{k}_widget_info"/>
        </receiver>
    </application>""", 1)
manifest.write_text(m, encoding="utf-8")
print("Info widgets added")
