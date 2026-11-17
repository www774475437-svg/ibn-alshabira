"""Posts what the sheikh published from the app to his Telegram channels.

The app never holds the bot's key: it leaves requests in Firestore
(tgQueue, staff only); this job — which has the key as a hidden GitHub
secret — posts them. Text → main channel, voice → recordings channel.
The bot only posts and edits its own posts; it never deletes anything.

Run inside the media branch folder. Keeps posted.json:
  answers: answer id -> message id (to edit later)
  ids: every main-channel message the app made (not pulled back in twice)
  voices: answer id -> recordings-channel message id
  done: queue ids already handled
"""
import base64
import datetime as dt
import json
import os
import urllib.request
import uuid

PROJECT = 'ibn-alshabira'
KEY = 'AIzaSyCOpkQxy5gP2-PuFAphg_tlJBv2gI8RkVI'
BASE = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
HEAD = {'Content-Type': 'application/json', 'Referer': 'https://ibnalshabira.com/'}
TOKEN = os.environ.get('BOT_TOKEN', '').strip()
MAIN = '@qaidghsh'
AUDIO = '@QaidSandVe'


def call(url, body=None):
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), headers=HEAD)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def val(v):
    for k in ('stringValue', 'booleanValue', 'doubleValue', 'timestampValue'):
        if k in v:
            return v[k]
    if 'integerValue' in v:
        return int(v['integerValue'])
    if 'mapValue' in v:
        return {k: val(x) for k, x in v['mapValue'].get('fields', {}).items()}
    if 'arrayValue' in v:
        return [val(x) for x in v['arrayValue'].get('values', [])]
    return None


def query(coll, field, op, value):
    r = call(f'{BASE}:runQuery?key={KEY}', {'structuredQuery': {
        'from': [{'collectionId': coll}],
        'where': {'fieldFilter': {'field': {'fieldPath': field}, 'op': op, 'value': value}},
    }})
    out = []
    for x in r:
        if 'document' in x:
            d = x['document']
            out.append((d['name'].rsplit('/', 1)[1], {k: val(v) for k, v in d.get('fields', {}).items()}))
    return out


def tg(method, **params):
    req = urllib.request.Request(f'https://api.telegram.org/bot{TOKEN}/{method}',
                                 data=json.dumps(params).encode(), headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def tg_file(method, field, name, data, **params):
    """multipart/form-data upload (voice or audio)."""
    b = uuid.uuid4().hex
    parts = []
    for k, v in params.items():
        parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{field}"; filename="{name}"\r\n'
                 f'Content-Type: application/octet-stream\r\n\r\n'.encode() + data + b'\r\n')
    parts.append(f'--{b}--\r\n'.encode())
    req = urllib.request.Request(f'https://api.telegram.org/bot{TOKEN}/{method}', data=b''.join(parts),
                                 headers={'Content-Type': f'multipart/form-data; boundary={b}'})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read())


def main():
    if not TOKEN:
        print('no bot key (TELEGRAM_BOT_TOKEN secret) — nothing posted')
        return
    try:
        state = json.load(open('posted.json', encoding='utf-8'))
    except Exception:
        state = {'answers': {}, 'ids': [], 'voices': {}, 'done': []}
    done = set(state.get('done', []))
    now = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    since = now - 7 * 86400000
    items = sorted(query('tgQueue', 'at', 'GREATER_THAN_OR_EQUAL', {'integerValue': str(since)}), key=lambda x: x[1].get('at', 0))
    changed = False
    for qid, m in items:
        if qid in done or int(m.get('at', 0)) > now:
            continue
        kind, text, aid = m.get('kind'), (m.get('text') or '').strip(), m.get('answerId') or ''
        try:
            if kind == 'text' and text:
                r = tg('sendMessage', chat_id=MAIN, text=text)
                mid = r['result']['message_id']
                state['ids'].append(mid)
                if aid:
                    state['answers'][aid] = mid
            elif kind == 'edit' and text and aid in state['answers']:
                tg('editMessageText', chat_id=MAIN, message_id=state['answers'][aid], text=text)
            elif kind == 'voice':
                parts = sorted(query('tgVoice', 'q', 'EQUAL', {'stringValue': qid}), key=lambda x: x[1].get('n', 0))
                data = base64.b64decode(''.join(p[1].get('data', '') for p in parts))
                ext = m.get('ext') or 'ogg'
                if ext == 'ogg':
                    r = tg_file('sendVoice', 'voice', 'voice.ogg', data, chat_id=AUDIO, caption=text)
                else:
                    r = tg_file('sendAudio', 'audio', f'voice.{ext}', data, chat_id=AUDIO, caption=text, title=text or 'تسجيل')
                if aid:
                    state['voices'][aid] = r['result']['message_id']
            done.add(qid)
            changed = True
            print('posted', kind, qid)
        except Exception as e:
            print('could not post', qid, e)
    state['done'] = sorted(done)[-2000:]
    state['ids'] = state['ids'][-5000:]
    if changed:
        json.dump(state, open('posted.json', 'w', encoding='utf-8'), ensure_ascii=False)


if __name__ == '__main__':
    main()
