"""Turn the sheikh's channel posts into the app's answers and articles,
word for word, sorted into chapters by keywords.

- A post with a question and «الجواب» becomes an answer (question + answer).
- A longer post without one becomes an article.
- Short posts (notices, links) stay only in «من قناة الشيخ».
Writes assets/data/fatwas.json and assets/data/channel.json.
Staff can move any answer to another chapter from inside the app."""
import json
import os
import re

from telegram_to_fatwas import norm

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'data')

# The word «الجواب» (with و/ف, optional colon) standing at the start of a line.
ANSWER_LINE = re.compile(r'(?m)^[^\w\n]*(?:(?:[وف]?\s*الجواب|الإجابة)[^\w\n]*(?:[:：/][^\w\n]*|$)|ج[ \t]*[:：/]|فأجبت(?:ه|ها|هم)?[ \t]*[:：])[ \t]*\n?', re.U)
QUESTION_START = re.compile(r'^[^\w\n]*(?:السؤال|سؤال|س)\s*[:：/]\s*|^[^\w\n]*(?:يقول\s*(?:السائل)?\s*[:：]?)\s*', re.U)
HASHTAG_LINE = re.compile(r'(?m)^\s*(?:#\S+\s*)+$')
LINK_ONLY = re.compile(r'^\s*(?:https?://\S+\s*)+$')

MIN_ARTICLE = 220


# Keyword stems per chapter (normalized). A word matches when, after
# dropping و/ف/ب/ل/ك and ال, it starts with the stem.
KEYWORDS = {
    "aqeedah": ["توحيد", "شرك", "مشرك", "عقيده", "ايمان", "كفر", "كافر", "قبور", "سحر", "ساحر", "تمائم",
                "تميمه", "الحاد", "ملحد", "صفات", "قدر", "جن", "رقيه", "تبرك", "استغاثه", "اولياء"],
    "manhaj": ["منهج", "سلفي", "سلفيه", "بدعه", "مبتدع", "حزبي", "حزبيه", "اخوان", "اخواني", "صوفي",
               "صوفيه", "رافضه", "رافضي", "حوثي", "خوارج", "خارجي", "تبليغ", "اشاعره", "معتزله",
               "حجوري", "الحجوري", "دماج", "جرح", "تحذير", "ردود", "فرقه", "فرق", "الشيعه", "داعش"],
    "taharah": ["وضوء", "توضا", "غسل", "اغتسال", "تيمم", "طهاره", "نجاسه", "نجس", "حيض", "حائض", "نفاس",
                "جنابه", "جنب", "استنجاء", "خفين"],
    "salah": ["صلاه", "الصلاه", "صلوات", "يصلي", "اذان", "مؤذن", "اقامه", "سجود", "ركوع", "جمعه", "تراويح",
              "وتر", "قنوت", "مسجد", "مساجد", "امامه", "ماموم", "قيام", "تهجد", "ركعه", "ركعتين"],
    "zakah": ["زكاه", "صدقه", "صدقات", "نصاب", "فطره"],
    "siyam": ["صيام", "صوم", "صائم", "رمضان", "افطار", "سحور", "اعتكاف", "عاشوراء", "عرفه"],
    "hajj": ["حج", "حاج", "حجاج", "عمره", "احرام", "طواف", "مكه", "اضحيه", "اضاحي", "هدي", "منى"],
    "muamalat": ["ربا", "ربوي", "بيع", "بيوع", "شراء", "تجاره", "قرض", "ديون", "بنك", "بنوك", "اجاره",
                 "ميراث", "مواريث", "تركه", "وصيه", "وقف", "قات", "تامين", "اسهم", "رشوه", "غش", "ضريبه"],
    "nikah": ["نكاح", "زواج", "تزوج", "طلاق", "طلق", "خلع", "مهر", "زوجه", "زوجته", "زوجها", "زوجتي",
              "رضاع", "عده", "حضانه", "ظهار", "تعدد", "خطيب", "مخطوبه", "عرس"],
    "akhlaq": ["اخلاق", "خلق", "ادب", "اداب", "بر", "والدين", "عقوق", "رحم", "غيبه", "نميمه", "كذب",
               "حجاب", "نقاب", "تبرج", "نمص", "لحيه", "اسبال", "تصوير", "صور", "اغاني", "اغنيه", "معازف",
               "موسيقى", "دخان", "تدخين", "شيشه", "سلام", "جار", "جيران", "اختلاط", "حياء", "لباس"],
    "mawaiz": ["موعظه", "نصيحه", "نصائح", "رقائق", "توبه", "استغفار", "ذكر", "اذكار", "دعاء", "قلب",
               "قلوب", "موت", "قبر", "اخره", "جنه", "نار", "صبر", "شكر", "زهد", "دنيا", "تقوى", "اخلاص",
               "ذنوب", "معاصي", "معصيه"],
}

_PREFIX = re.compile(r"^(?:و|ف)?(?:ب|ل|ك)?(?:ال)?")


def _tokens(text):
    out = []
    for w in re.findall(r"[\u0621-\u064A]+", norm(text)):
        w2 = _PREFIX.sub("", w, count=1)
        out.append(w2 if len(w2) >= 2 else w)
    return out


def _score(tokens):
    scores = dict.fromkeys(KEYWORDS, 0)
    for t in tokens:
        for ch, stems in KEYWORDS.items():
            for k in stems:
                kk = _PREFIX.sub("", k, count=1) or k
                if t == kk or (len(kk) >= 4 and t.startswith(kk)):
                    scores[ch] += 1
                    break
    return scores


def classify(text, title=""):
    """Chapter by keywords; the title counts three times. Unclear → متفرقات."""
    s = _score(_tokens(text))
    t = _score(_tokens(title))
    total = {ch: s[ch] + 3 * t[ch] for ch in KEYWORDS}
    ranked = sorted(total.items(), key=lambda kv: -kv[1])
    (best, top), (_, second) = ranked[0], ranked[1]
    if top < 2 or top <= second:
        return "mutafarriq"
    return best


def clean(text):
    t = HASHTAG_LINE.sub('', text)
    t = re.sub(r'\n{3,}', '\n\n', t)
    return t.strip()


def title_of(text, limit=90):
    for line in text.split('\n'):
        line = line.strip(' *_-–—▪•🔹🔸📌❓⁉️')
        if len(line) >= 8:
            if len(line) > limit:
                cut = line[:limit]
                sp = cut.rfind(' ')
                line = (cut[:sp] if sp > 40 else cut) + '…'
            return line
    return text[:limit]


def split(text):
    """Return (question, answer) or None when the post is not a Q&A."""
    m = ANSWER_LINE.search(text)
    if not m or m.start() < 10:
        return None
    q = QUESTION_START.sub('', text[:m.start()], count=1).strip()
    a = text[m.end():].strip()
    if len(q) < 8 or len(a) < 8:
        return None
    # Split only when it is clearly one question and its answer. Anything
    # doubtful stays whole as an article, so no word lands in the wrong box.
    if len(q) > 900 or len(a) < 60 or len(ANSWER_LINE.findall(text)) > 1:
        return None
    if len(a) < 300 and 'http' in a:
        return None
    return q, a


def convert(posts):
    answers, rest = [], []
    for p in posts:
        text = clean(p['text'])
        if not text or LINK_ONLY.match(text):
            continue
        qa = split(text)
        base = {
            'id': 'tg-%d' % p['id'],
            'tags': [],
            'date': p.get('date', ''),
            'source': 'https://t.me/qaidghsh/%d' % p['id'],
        }
        if qa:
            q, a = qa
            answers.append(dict(base, chapter=classify(q + '\n' + a, q), type='fatwa',
                                title=title_of(q), question=q, answer=a))
        elif len(text) >= MIN_ARTICLE:
            answers.append(dict(base, chapter=classify(text, title_of(text)), type='article',
                                title=title_of(text), question='', answer=text))
        else:
            rest.append({'id': p['id'], 'text': text, 'date': p.get('date', '')})
    answers.sort(key=lambda a: int(a['id'][3:]))
    with open(os.path.join(DATA, 'fatwas.json'), 'w', encoding='utf-8') as f:
        json.dump(answers, f, ensure_ascii=False)
    with open(os.path.join(DATA, 'channel.json'), 'w', encoding='utf-8') as f:
        json.dump(rest, f, ensure_ascii=False)
    # The newest answers, for apps installed before these were posted.
    with open(os.path.join(DATA, 'latest.json'), 'w', encoding='utf-8') as f:
        json.dump(answers[-80:], f, ensure_ascii=False)
    by = {}
    for a in answers:
        by[a['chapter']] = by.get(a['chapter'], 0) + 1
    print('answers:', sum(1 for a in answers if a['type'] == 'fatwa'),
          'articles:', sum(1 for a in answers if a['type'] == 'article'),
          'short posts:', len(rest), 'by chapter:', by)
