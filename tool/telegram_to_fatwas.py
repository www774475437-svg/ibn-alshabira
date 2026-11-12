"""Convert a Telegram channel export (result.json) into assets/data/fatwas.json.

Usage:
    python3 tool/telegram_to_fatwas.py result.json [channel_username]

Each text post becomes one entry. It is sorted into a chapter by keywords
(anything unclear goes to «متفرقات» for manual review), and split into
question / answer when the post contains a question marker.
A review report is written to tool/review_report.txt.
"""
import json
import re
import sys
from pathlib import Path

TASHKEEL = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")


def norm(s: str) -> str:
    s = TASHKEEL.sub("", s)
    s = re.sub("[إأآٱ]", "ا", s)
    return s.replace("ى", "ي").replace("ة", "ه").replace("ؤ", "و").replace("ئ", "ي")


# Keywords per chapter (normalized form). Order matters: first strong match wins.
CHAPTER_KEYWORDS = {
    "aqeedah": ["عقيده", "توحيد", "شرك", "بدعه", "ايمان", "الاسماء والصفات", "قبور", "سحر",
                "تمائم", "كفر", "صوفي", "رافض", "حزبي", "اخوان", "منهج", "سلف", "قدر"],
    "taharah": ["وضوء", "غسل", "تيمم", "طهاره", "نجاسه", "حيض", "نفاس", "جنابه", "استنجاء",
                "مسح علي الخف", "مسح الخفين"],
    "salah": ["صلاه", "الصلوات", "اذان", "اقامه", "امام", "ماموم", "سجود", "ركوع", "جمعه",
              "قصر", "جمع الصلاه", "وتر", "سنن الرواتب", "مسجد", "قنوت", "سجود السهو"],
    "zakah": ["زكاه", "صدقه", "نصاب", "زكاه الفطر", "فطره"],
    "siyam": ["صيام", "صوم", "رمضان", "افطار", "سحور", "اعتكاف", "ليله القدر", "عاشوراء", "عرفه"],
    "hajj": ["حج", "عمره", "احرام", "طواف", "سعي", "مني", "اضحيه", "عيد الاضحي", "هدي"],
    "muamalat": ["ربا", "بيع", "شراء", "تجاره", "قرض", "دين", "بنك", "اجاره", "شركه", "مال",
                 "ميراث", "وصيه", "وقف", "قات", "تامين", "فوائد", "اسهم", "عمل"],
    "nikah": ["نكاح", "زواج", "طلاق", "خلع", "مهر", "خطبه", "ولي", "زوجه", "زوج", "رضاع",
              "عده", "نفقه", "حضانه", "ظهار", "تعدد"],
    "akhlaq": ["اخلاق", "اداب", "بر الوالدين", "والدين", "صله الرحم", "غيبه", "نميمه", "كذب",
               "لباس", "حجاب", "نقاب", "نمص", "لحيه", "اسبال", "تصوير", "اغاني", "معازف",
               "دخان", "شيشه", "سلام", "جار", "تهنئه", "عيد الميلاد", "حلق"],
}

QUESTION_MARKERS = ["السؤال:", "السؤال :", "سؤال:", "س:", "س/", "يقول السائل", "سائل يسأل"]
ANSWER_MARKERS = ["الجواب:", "الجواب :", "جواب:", "ج:", "ج/", "الإجابة:"]


def post_text(msg) -> str:
    t = msg.get("text", "")
    if isinstance(t, list):
        t = "".join(p if isinstance(p, str) else p.get("text", "") for p in t)
    return t.strip()


def classify(text: str) -> tuple[str, int]:
    n = norm(text)
    scores = {ch: sum(n.count(k) for k in kws) for ch, kws in CHAPTER_KEYWORDS.items()}
    best = max(scores, key=scores.get)
    return (best, scores[best]) if scores[best] > 0 else ("mutafarriq", 0)


def split_qa(text: str):
    q_pos = next((text.find(m) for m in QUESTION_MARKERS if m in text), -1)
    a_mark = next((m for m in ANSWER_MARKERS if m in text), None)
    if a_mark:
        a_pos = text.find(a_mark)
        q_part = text[:a_pos]
        if q_pos >= 0:
            q_part = text[q_pos:a_pos]
        for m in QUESTION_MARKERS:
            q_part = q_part.replace(m, "", 1) if q_part.lstrip().startswith(m) else q_part
        return q_part.strip(), text[a_pos + len(a_mark):].strip(), "fatwa"
    if q_pos >= 0 or "؟" in text[:300]:
        return "", text, "fatwa"
    return "", text, "article"


def make_title(question: str, answer: str) -> str:
    base = question or answer
    first = base.strip().split("\n")[0].strip(" :*_🔖📜▪️-")
    words = first.split()
    return " ".join(words[:12]) + ("…" if len(words) > 12 else "")


def main():
    src = Path(sys.argv[1])
    channel = sys.argv[2] if len(sys.argv) > 2 else ""
    data = json.loads(src.read_text(encoding="utf-8"))
    messages = data.get("messages", [])

    out, report = [], []
    for msg in messages:
        if msg.get("type") != "message":
            continue
        text = post_text(msg)
        if len(text) < 60:  # too short to be a fatwa/article (greetings, links…)
            continue
        question, answer, kind = split_qa(text)
        chapter, score = classify(text)
        entry = {
            "id": f"tg-{msg['id']}",
            "chapter": chapter,
            "type": kind,
            "title": make_title(question, answer),
            "question": question,
            "answer": answer,
            "tags": [],
            "date": (msg.get("date") or "")[:10],
            "source": f"https://t.me/{channel}/{msg['id']}" if channel else "",
        }
        out.append(entry)
        if score <= 1:
            report.append(f"{entry['id']}\t{chapter}\t(score {score})\t{entry['title']}")

    dest = Path("assets/data/fatwas.json")
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    Path("tool/review_report.txt").write_text(
        "Posts with weak classification — review manually:\n" + "\n".join(report),
        encoding="utf-8",
    )
    counts = {}
    for e in out:
        counts[e["chapter"]] = counts.get(e["chapter"], 0) + 1
    print(f"Wrote {len(out)} entries to {dest}")
    for ch, c in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {ch}: {c}")
    print(f"{len(report)} entries need review (tool/review_report.txt)")


if __name__ == "__main__":
    main()
