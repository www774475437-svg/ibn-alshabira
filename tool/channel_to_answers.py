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

from telegram_to_fatwas import CHAPTER_KEYWORDS, norm

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'data')

# The word «الجواب» (with و/ف, optional colon) standing at the start of a line.
ANSWER_LINE = re.compile(r'(?m)^[ \t]*(?:(?:[وف]?\s*الجواب|الإجابة)[ \t]*(?:[:：/]|$)|ج[ \t]*[:：/])[ \t]*\n?', re.U)
QUESTION_START = re.compile(r'^\s*(?:السؤال|سؤال|س)\s*[:：/]\s*|^\s*(?:يقول\s*(?:السائل)?\s*[:：]?)\s*', re.U)
HASHTAG_LINE = re.compile(r'(?m)^\s*(?:#\S+\s*)+$')
LINK_ONLY = re.compile(r'^\s*(?:https?://\S+\s*)+$')

MIN_ARTICLE = 220


def classify(text):
    n = norm(text)
    scores = {ch: sum(n.count(k) for k in kws) for ch, kws in CHAPTER_KEYWORDS.items()}
    best = max(scores, key=scores.get)
    return best if scores[best] > 0 else 'mutafarriq'


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
            answers.append(dict(base, chapter=classify(q + '\n' + a), type='fatwa',
                                title=title_of(q), question=q, answer=a))
        elif len(text) >= MIN_ARTICLE:
            answers.append(dict(base, chapter=classify(text), type='article',
                                title=title_of(text), question='', answer=text))
        else:
            rest.append({'id': p['id'], 'text': text, 'date': p.get('date', '')})
    answers.sort(key=lambda a: int(a['id'][3:]))
    with open(os.path.join(DATA, 'fatwas.json'), 'w', encoding='utf-8') as f:
        json.dump(answers, f, ensure_ascii=False)
    with open(os.path.join(DATA, 'channel.json'), 'w', encoding='utf-8') as f:
        json.dump(rest, f, ensure_ascii=False)
    by = {}
    for a in answers:
        by[a['chapter']] = by.get(a['chapter'], 0) + 1
    print('answers:', sum(1 for a in answers if a['type'] == 'fatwa'),
          'articles:', sum(1 for a in answers if a['type'] == 'article'),
          'short posts:', len(rest), 'by chapter:', by)
