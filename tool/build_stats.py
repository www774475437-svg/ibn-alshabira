"""Four times a day: copy the quiz and the counts out of Firestore into small
JSON files on the `media` branch, so the app reads them from the site and
not from Firestore (which counts every document read).

Readers' phones send one small document a day each (`searches/d-<day>-<device>`):
the answers they viewed, their quiz answers, their votes, the hours they were
on, and their minutes. This script adds them up.

Run inside the media branch folder:  python3 -I ../code/tool/build_stats.py
Writes: quiz.json, stats.json, views.json, usage.json, and keeps stats-state.json.
"""
import datetime as dt
import json
import os
import urllib.request

PROJECT = 'ibn-alshabira'
KEY = 'AIzaSyCOpkQxy5gP2-PuFAphg_tlJBv2gI8RkVI'
BASE = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
HEAD = {'Content-Type': 'application/json', 'Referer': 'https://ibnalshabira.com/'}
READS = 0


def _call(url, body=None):
    global READS
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), headers=HEAD)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def val(v):
    """A Firestore REST value as plain Python."""
    if 'stringValue' in v:
        return v['stringValue']
    if 'integerValue' in v:
        return int(v['integerValue'])
    if 'doubleValue' in v:
        return v['doubleValue']
    if 'booleanValue' in v:
        return v['booleanValue']
    if 'timestampValue' in v:
        return v['timestampValue']
    if 'nullValue' in v:
        return None
    if 'mapValue' in v:
        return {k: val(x) for k, x in v['mapValue'].get('fields', {}).items()}
    if 'arrayValue' in v:
        return [val(x) for x in v['arrayValue'].get('values', [])]
    return None


def doc(d):
    return d['name'].rsplit('/', 1)[1], {k: val(x) for k, x in d.get('fields', {}).items()}


def collection(name):
    global READS
    out, token = [], ''
    while True:
        r = _call(f'{BASE}/{name}?key={KEY}&pageSize=300' + (f'&pageToken={token}' if token else ''))
        docs = r.get('documents', [])
        READS += max(1, len(docs))
        out += [doc(d) for d in docs]
        token = r.get('nextPageToken')
        if not token:
            return out


def day_docs(day):
    """Every device's document for one day."""
    global READS
    r = _call(f'{BASE}:runQuery?key={KEY}', {'structuredQuery': {
        'from': [{'collectionId': 'searches'}],
        'where': {'fieldFilter': {'field': {'fieldPath': 'day'}, 'op': 'EQUAL', 'value': {'stringValue': day}}},
    }})
    out = [doc(x['document']) for x in r if 'document' in x]
    READS += max(1, len(out))
    return out


def load(path, default):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return default


def save(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))


def add_day(base, docs):
    """Adds one day's device documents into the running totals."""
    q, v = base['quiz'], base['views']
    for _, m in docs:
        for qid, a in (m.get('a') or {}).items():
            if not isinstance(a, list) or len(a) < 2:
                continue
            s = q.setdefault(qid, [0] * 10)
            s[0] += 1
            if a[1]:
                s[1] += 1
            c = a[0] if isinstance(a[0], int) else -1
            if 0 <= c < 8:
                s[2 + c] += 1
        for aid in (m.get('v') or {}):
            v.setdefault(aid, [0, 0, 0])[0] += 1
        for aid, good in (m.get('hv') or {}).items():
            v.setdefault(aid, [0, 0, 0])[1 if good else 2] += 1
        base['shares'] = base.get('shares', 0) + int(m.get('sh') or 0)


def usage_of(day, docs):
    hours = [0] * 24
    minutes, web = {}, 0
    for _, m in docs:
        for h in (m.get('hr') or {}):
            if str(h).isdigit() and int(h) < 24:
                hours[int(h)] += 1
        if m.get('web'):
            web += 1
        if m.get('u') is not None:
            minutes[str(m['u'])] = max(minutes.get(str(m['u']), 0), int(m.get('min') or 0))
    return {'people': len(docs), 'web': web, 'hours': hours, 'minutes': minutes}


def first_base():
    """The counts as they were before the phones started sending one document
    a day (read once, the very first time)."""
    base = {'quiz': {}, 'views': {}, 'shares': 0, 'readers': {}}
    for qid, m in collection('quizStats'):
        s = [int(m.get('n', 0)), int(m.get('ok', 0))] + [int(m.get(f'c{i}', 0)) for i in range(8)]
        base['quiz'][qid] = s
    for vid, m in collection('views'):
        if vid == '_appShare':
            base['shares'] = int(m.get('count', 0))
        elif vid.startswith('_day_'):
            base['readers'][vid[5:]] = int(m.get('count', 0))
        elif not vid.startswith('_'):
            base['views'][vid] = [int(m.get('count', 0)), int(m.get('helpful', 0)), int(m.get('notHelpful', 0))]
    return base


def main():
    now = dt.datetime.now(dt.timezone.utc)
    today = now.strftime('%Y-%m-%d')
    yesterday = (now - dt.timedelta(days=1)).strftime('%Y-%m-%d')

    state = load('stats-state.json', None)
    if not state:
        state = {'baseDay': yesterday, 'base': first_base(), 'usage': {}}
    base = state['base']

    # Fold every finished day into the totals, once.
    d = dt.date.fromisoformat(state['baseDay']) + dt.timedelta(days=1)
    while d.isoformat() < today:
        docs = day_docs(d.isoformat())
        add_day(base, docs)
        state['usage'][d.isoformat()] = usage_of(d.isoformat(), docs)
        base['readers'][d.isoformat()] = len(docs)
        state['baseDay'] = d.isoformat()
        d += dt.timedelta(days=1)

    # Today so far, on top of the totals (not kept in the base).
    docs = day_docs(today)
    now_totals = json.loads(json.dumps(base))
    add_day(now_totals, docs)
    state['usage'][today] = usage_of(today, docs)
    readers = dict(base['readers'])
    readers[today] = len(docs)
    keep = sorted(state['usage'])[-8:]
    state['usage'] = {k: state['usage'][k] for k in keep}
    for k in sorted(base['readers'])[:-60]:
        base['readers'].pop(k, None)

    # The quiz itself: live questions only (drafts and hidden stay in Firestore).
    cats = [dict(m, id=i) for i, m in collection('quizCats')]
    qs = []
    for i, m in collection('quizQs'):
        if m.get('draft') or m.get('hidden'):
            continue
        qs.append(dict(m, id=i))
    cfg = dict(collection('config')).get('quiz', {})

    save('quiz.json', {'at': now.isoformat(), 'cats': cats, 'qs': qs,
                       'thanks': cfg.get('thanks', ''), 'chPerDay': cfg.get('chPerDay', 2),
                       'readPoints': cfg.get('readPoints', False)})
    save('stats.json', {'at': now.isoformat(), 'q': now_totals['quiz']})
    save('views.json', {'at': now.isoformat(), 'v': now_totals['views'],
                        'shares': now_totals.get('shares', 0), 'readers': readers})
    save('usage.json', {'at': now.isoformat(), 'days': state['usage']})
    save('stats-state.json', state)
    print(f'{len(qs)} questions, {len(docs)} devices today, about {READS} reads')


if __name__ == '__main__':
    main()
