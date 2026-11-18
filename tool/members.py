"""Four times a day, after build_stats.py (inside the media branch folder):

1. profiles.json (public, on the media branch): each reader's public page,
   made only of what the reader shows to everyone (his name only when he
   turned on «أضف اسمي»), keyed by his 6-digit number, with how many follow
   him. Only the documents changed since the last run are read; once a day
   everything is read again so nothing is missed.

2. adminData/members_* (private, in Firestore, only the staff can open it):
   everyone who registered, numbered from the first, with his summary. The
   staff page opens it with one or two reads instead of one per person.
   The script signs in as the «stats bot» account, whose password is made
   from the Telegram bot secret, so no new secret is needed.

Env: TELEGRAM_BOT_TOKEN.  Run:  python3 -I ../code/tool/members.py
"""
import datetime as dt
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

PROJECT = 'ibn-alshabira'
KEY = 'AIzaSyCOpkQxy5gP2-PuFAphg_tlJBv2gI8RkVI'
BASE = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
REFERER = 'https://ibnalshabira.com/'
BOT_EMAIL = 'stats-bot@ibnalshabira.com'
CHUNK = 1200
READS = 0
TOKEN = None


def call(url, body=None, method=None, auth=True):
    h = {'Content-Type': 'application/json', 'Referer': REFERER}
    if auth and TOKEN:
        h['Authorization'] = 'Bearer ' + TOKEN
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), headers=h, method=method)
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read() or b'{}')


def val(v):
    if 'stringValue' in v: return v['stringValue']
    if 'integerValue' in v: return int(v['integerValue'])
    if 'doubleValue' in v: return v['doubleValue']
    if 'booleanValue' in v: return v['booleanValue']
    if 'timestampValue' in v: return v['timestampValue']
    if 'nullValue' in v: return None
    if 'mapValue' in v: return {k: val(x) for k, x in v['mapValue'].get('fields', {}).items()}
    if 'arrayValue' in v: return [val(x) for x in v['arrayValue'].get('values', [])]
    return None


def ms(iso):
    try:
        return int(dt.datetime.fromisoformat(iso.replace('Z', '+00:00')).timestamp() * 1000)
    except Exception:
        return None


def sign_in():
    """The stats bot: signs in, or makes the account the first time."""
    global TOKEN
    secret = os.environ.get('TELEGRAM_BOT_TOKEN', '')
    if not secret:
        print('no secret: skipping the private list')
        return None
    pw = hashlib.sha256(('ibn-alshabira-stats:' + secret).encode()).hexdigest()[:40]
    body = {'email': BOT_EMAIL, 'password': pw, 'returnSecureToken': True}
    idt = 'https://identitytoolkit.googleapis.com/v1/accounts:'
    try:
        r = call(f'{idt}signInWithPassword?key={KEY}', body, auth=False)
    except urllib.error.HTTPError as e:
        msg = e.read().decode()
        if 'EMAIL_NOT_FOUND' in msg or 'INVALID_LOGIN_CREDENTIALS' in msg:
            try:
                r = call(f'{idt}signUp?key={KEY}', body, auth=False)
            except urllib.error.HTTPError as e2:
                print('cannot make the bot account:', e2.read().decode()[:300])
                return None
        else:
            print('cannot sign in:', msg[:300])
            return None
    TOKEN = r['idToken']
    print('BOT UID:', r['localId'])
    return r['localId']


def list_all(coll, fields):
    """Every document of a collection (only the given fields), with its time."""
    global READS
    out, page = [], ''
    mask = ''.join(f'&mask.fieldPaths={f}' for f in fields)
    while True:
        r = call(f'{BASE}/{coll}?key={KEY}&pageSize=300{mask}' + (f'&pageToken={page}' if page else ''))
        for d in r.get('documents', []):
            out.append((d['name'].rsplit('/', 1)[1], d.get('createTime'), {k: val(x) for k, x in d.get('fields', {}).items()}))
        READS += max(1, len(r.get('documents', [])))
        page = r.get('nextPageToken', '')
        if not page:
            return out


def changed_since(coll, field, value, fields):
    """Documents whose [field] is greater than [value] (a Firestore value)."""
    global READS
    q = {'structuredQuery': {
        'from': [{'collectionId': coll}],
        'select': {'fields': [{'fieldPath': f} for f in fields]},
        'where': {'fieldFilter': {'field': {'fieldPath': field}, 'op': 'GREATER_THAN', 'value': value}},
    }}
    r = call(f'{BASE}:runQuery?key={KEY}', q)
    out = []
    for x in r:
        d = x.get('document')
        if d:
            out.append((d['name'].rsplit('/', 1)[1], d.get('createTime'), {k: val(v) for k, v in d.get('fields', {}).items()}))
    READS += max(1, len(out))
    return out


def get_doc(path):
    global READS
    READS += 1
    try:
        d = call(f'{BASE}/{path}?key={KEY}')
        return {k: val(x) for k, x in d.get('fields', {}).items()}
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def put_doc(path, fields):
    body = {'fields': {k: ({'stringValue': v} if isinstance(v, str) else {'integerValue': str(v)}) for k, v in fields.items()}}
    call(f'{BASE}/{path}?key={KEY}', body, method='PATCH')


# ------------------------------------------------------------ the public pages
def public_pages(full):
    try:
        prev = json.load(open('profiles.json', encoding='utf-8'))
    except Exception:
        prev, full = {'at': 0, 'p': {}, 'u': {}}, True
    fields = ['nick', 'showName', 'no', 'score', 'pts', 'reads', 'listens', 'hifz', 'days', 'badges',
              'chPlayed', 'chWinsDuel', 'chWinsGroup', 'fw', 'qt', 'at']
    started = dt.datetime.now(dt.timezone.utc)
    if full:
        rows = list_all('quizUsers', fields)
        pages, uids = {}, {}
    else:
        since = dt.datetime.fromtimestamp(prev.get('at', 0) / 1000 - 60, dt.timezone.utc).isoformat().replace('+00:00', 'Z')
        rows = changed_since('quizUsers', 'at', {'timestampValue': since}, fields)
        pages, uids = prev.get('p', {}), prev.get('u', {})
    for uid, _, m in rows:
        no = m.get('no')
        if not isinstance(no, int) or no < 100000:
            continue  # an old 5-digit page: it is renewed when its owner opens the new app
        old = uids.get(uid)
        if old and old != str(no):
            pages.pop(old, None)
        uids[uid] = str(no)
        qt = [q for q in (m.get('qt') or []) if isinstance(q, dict)][:30]
        pages[str(no)] = {
            'n': (m.get('nick') or '').strip() if m.get('showName') else '',
            'p': m.get('pts') or 0, 'r': m.get('score') or 0, 'rd': m.get('reads') or 0,
            'ls': m.get('listens') or 0, 'hf': m.get('hifz') or 0, 'd': m.get('days') or 0,
            'b': [b for b in (m.get('badges') or []) if isinstance(b, str)][:40],
            'cp': m.get('chPlayed') or 0, 'cw': (m.get('chWinsDuel') or 0) + (m.get('chWinsGroup') or 0),
            'fw': [str(x) for x in (m.get('fw') or [])][:500],
            'q': [{'t': str(q.get('t', ''))[:600], 's': str(q.get('s', ''))[:120], 'at': q.get('at', 0)} for q in qt],
        }
    # Followers: everyone whose list holds the number.
    count = {}
    for no, p in pages.items():
        for f in set(p['fw']):
            if f != no:
                count[f] = count.get(f, 0) + 1
    for no, p in pages.items():
        p['fr'] = count.get(no, 0)
        p['fg'] = len(set(p['fw']) - {no})
    out = {'at': int(started.timestamp() * 1000), 'p': pages, 'u': uids}
    with open('profiles.json', 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print(f'public pages: {len(pages)} ({len(rows)} read, full={full})')


# ------------------------------------------------------------- the staff list
def members(full):
    meta = get_doc('adminData/members_meta')
    state = {}
    if meta:
        for i in range(int(meta.get('chunks', 0))):
            c = get_doc(f'adminData/members_{i}')
            if c and c.get('l'):
                state.update(json.loads(c['l']))
    else:
        full = True
    started = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    if full:
        rows = list_all('users', ['card'])
        seen_uids = {uid for uid, _, _ in rows}
        for uid in list(state):
            if uid not in seen_uids:
                state.pop(uid)  # the account was deleted; his number is not given again
    else:
        rows = changed_since('users', 'card.seen', {'integerValue': str(int(meta.get('last', 0)) - 60000)}, ['card'])
    top = max([m['s'] for m in state.values()] or [0])
    if meta and int(meta.get('top', 0)) > top:
        top = int(meta['top'])
    fresh = []
    for uid, created, m in rows:
        card = m.get('card') or {}
        joined = card.get('joined') if isinstance(card.get('joined'), int) else ms(created or '')
        rec = state.get(uid) or {'s': 0, 'j': joined}
        rec['c'] = card
        if not rec.get('j'):
            rec['j'] = joined
        if isinstance(card.get('seen'), int):
            rec['v'] = card['seen']
        if not rec['s']:
            fresh.append(uid)
        state[uid] = rec
    fresh.sort(key=lambda u: (state[u].get('j') or 1 << 62, u))
    for u in fresh:
        top += 1
        state[u]['s'] = top
    items = sorted(state.items(), key=lambda kv: kv[1]['s'])
    chunks = [dict(items[i:i + CHUNK]) for i in range(0, len(items), CHUNK)] or [{}]
    for i, c in enumerate(chunks):
        put_doc(f'adminData/members_{i}', {'l': json.dumps(c, ensure_ascii=False, separators=(',', ':'))})
    put_doc('adminData/members_meta', {'chunks': len(chunks), 'last': started, 'top': top, 'count': len(state),
                                       'at': dt.datetime.now(dt.timezone.utc).isoformat()})
    print(f'members: {len(state)} ({len(rows)} read, {len(fresh)} new, full={full})')



# --------------------------------------------------------- Friday tournament
RT = 'https://ibn-alshabira-default-rtdb.firebaseio.com'


def rt(path, method='GET'):
    req = urllib.request.Request(f'{RT}/{path}.json?auth={TOKEN}', method=method)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b'null')


def tours():
    """tours.json: which coming Fridays have questions (so the card shows),
    and the record of each finished tournament: its first ten, from the live
    room and from Firestore (players who found the live room full). The live
    room is deleted once it is in the record."""
    try:
        prev = json.load(open('tours.json', encoding='utf-8'))
    except Exception:
        prev = {'h': [], 'ready': {}}
    done = {h['d'] for h in prev.get('h', [])}
    now = dt.datetime.now(dt.timezone.utc)
    first = dt.datetime(now.year, now.month, now.day, 18, tzinfo=dt.timezone.utc)
    while first.weekday() != 4 or now > first + dt.timedelta(minutes=30):
        first += dt.timedelta(days=1)
    ready = {}
    for i in range(5):
        k = (first + dt.timedelta(days=7 * i)).strftime('%Y-%m-%d')
        d = get_doc(f'tours/{k}')
        if d and int(d.get('n') or 0) > 0:
            ready[k] = int(d['n'])
    hist = list(prev.get('h', []))
    for back in range(1, 4):
        start = first - dt.timedelta(days=7 * back) if first > now else first - dt.timedelta(days=7 * (back - 1))
        if start + dt.timedelta(minutes=25) > now:
            continue
        k = start.strftime('%Y-%m-%d')
        if k in done:
            continue
        d = get_doc(f'tours/{k}')
        if not d or not d.get('qs'):
            continue
        players = {}
        try:
            for uid, m in (rt(f'tour/{k}/p') or {}).items():
                if isinstance(m, dict):
                    players[uid] = m
        except Exception as e:
            print('live room:', e)
            continue  # try again next time, so nobody is missed
        for uid, _, m in list_all(f'tours/{k}/p', ['name', 'no', 'score', 'right', 'wrong', 'ms', 'finished']):
            players.setdefault(uid, m)
        ranked = sorted(players.values(), key=lambda m: (-int(m.get('score') or 0), int(m.get('ms') or 0) or 1 << 30))
        top = [{'n': str(m.get('name') or 'طالب علم')[:60], 'no': int(m.get('no') or 0), 's': int(m.get('score') or 0),
                'r': int(m.get('right') or 0), 'ms': int(m.get('ms') or 0)} for m in ranked[:10]]
        if len(players) < 2:
            top = []  # cancelled: fewer than two
        hist.append({'d': k, 'n': len(players), 'q': len(d['qs']), 'top': top})
        try:
            rt(f'tour/{k}', 'DELETE')
        except Exception as e:
            print('could not delete the live room:', e)
        print(f'tournament {k}: {len(players)} players')
    hist.sort(key=lambda h: h['d'], reverse=True)
    out = {'at': int(now.timestamp() * 1000), 'ready': ready, 'h': hist[:400]}
    with open('tours.json', 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print(f'tours: ready {ready}, record {len(hist)}')


def main():
    full = os.environ.get('FULL') == '1' or dt.datetime.now(dt.timezone.utc).hour < 6
    try:
        public_pages(full)
    except Exception as e:
        print('public pages failed:', e)
    if sign_in():
        try:
            tours()
        except urllib.error.HTTPError as e:
            print('tours failed:', e.code, e.read().decode()[:400])
        except Exception as e:
            print('tours failed:', e)
        if os.environ.get('TOURS_ONLY') == '1':
            print('reads:', READS)
            return
        try:
            members(full)
        except urllib.error.HTTPError as e:
            print('members failed:', e.code, e.read().decode()[:400])
        except Exception as e:
            print('members failed:', e)
    print('reads:', READS)


if __name__ == '__main__':
    main()
