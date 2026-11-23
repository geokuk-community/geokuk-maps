#!/usr/bin/env python3
"""Writes the state of the stub of gh (tests/themes/stub-finalize) for the test of finalize.sh in tests/themes/run.sh.
Usage: finalize-state.py STATE draft.json themes_dir previous.json tags.txt
  draft.json     layers.json of the draft layers-2026-12 (with theme/geokuk; its layers point to layers-2026-10, -10e and -10f)
  themes_dir     GeoKuk-tema.zip, GeoKuk-tema-PAWS.zip and their .sha256
  previous.json  layers.json of the published layers-2026-11, the previous release
  tags.txt       tags ("poi k=v" / "way k=v") written into the synthetic map header STATE/header.map
Releases: 1 layers-2026-12 (draft), 2 layers-2026-11, 3 layers-2026-10f, 4 layers-2026-10e, 5 layers-2026-10, and 6 layers-2026-11-split
(published, a test tag that must never be taken as the previous release: its layers.json has a layer that no other release has)."""
import hashlib, json, os, struct, sys

state, draft_path, themes, previous_path, tags_path = sys.argv[1:6]
os.makedirs(state, exist_ok=True)
draft = json.load(open(draft_path, encoding='utf-8'))
previous = json.load(open(previous_path, encoding='utf-8'))
split = json.loads(json.dumps(previous))
split['layers'].append(dict(split['layers'][0], id='tourist/europe/only-in-split'))
releases = [(1, 'layers-2026-12', True), (2, 'layers-2026-11', False), (3, 'layers-2026-10f', False), (4, 'layers-2026-10e', False),
            (5, 'layers-2026-10', False), (6, 'layers-2026-11-split', False)]
ids = {tag: rid for rid, tag, _ in releases}
assets = {rid: [] for rid, _, _ in releases}
next_id = [100]


def add(tag, name, data=None, size=None, sha=None):
    aid = next_id[0]
    next_id[0] += 1
    if data is not None:
        open(os.path.join(state, 'blob-%d' % aid), 'wb').write(data)
        size, sha = len(data), hashlib.sha256(data).hexdigest()
    a = {'id': aid, 'name': name, 'state': 'uploaded', 'size': size if size is not None else 1}
    if sha:
        a['digest'] = 'sha256:' + sha
    assets[ids[tag]].append(a)


def blob(path):
    return open(path, 'rb').read()


add('layers-2026-12', 'layers.json', json.dumps(draft).encode())
add('layers-2026-12', 'LICENSES.txt', b'licence\n')
for name in ('GeoKuk-tema.zip', 'GeoKuk-tema.zip.sha256', 'GeoKuk-tema-PAWS.zip', 'GeoKuk-tema-PAWS.zip.sha256'):
    if name != 'GeoKuk-tema.zip':  # GeoKuk-tema.zip is a file of the catalogue, added below with its sha256
        add('layers-2026-12', name, blob(os.path.join(themes, name)))
add('layers-2026-11', 'layers.json', json.dumps(previous).encode())
add('layers-2026-11-split', 'layers.json', json.dumps(split).encode())
seen = set()
for entry in draft['layers'] + draft.get('themes', []):
    for f in entry['files']:
        tag, name = f['url'].split('/')
        if (tag, name) in seen:
            continue
        seen.add((tag, name))
        if name == 'GeoKuk-tema.zip':
            add(tag, name, blob(os.path.join(themes, name)))
        else:
            add(tag, name, size=f['size'], sha=f['sha256'])
    poly = entry.get('coverage', {}).get('poly')
    if poly and tuple(poly.split('/')) not in seen:
        seen.add(tuple(poly.split('/')))
        add(*poly.split('/'))
json.dump([{'id': rid, 'tag_name': tag, 'draft': d} for rid, tag, d in releases], open(os.path.join(state, 'releases.json'), 'w'))
for rid, items in assets.items():
    json.dump(items, open(os.path.join(state, 'assets-%d.json' % rid), 'w'))


def string(s):
    b = s.encode('utf-8')
    return bytes([len(b)]) + b


poi, way = [], []
for line in open(tags_path, encoding='utf-8'):
    kind, _, kv = line.strip().partition(' ')
    (poi if kind == 'poi' else way).append(kv)
header = b'mapsforge binary OSM' + struct.pack('>iiqqiiiih', 0, 3, 0, 0, 0, 0, 0, 0, 256) + string('Mercator') + b'\x00'
header += struct.pack('>H', len(poi)) + b''.join(string(t) for t in poi) + struct.pack('>H', len(way)) + b''.join(string(t) for t in way)
open(os.path.join(state, 'header.map'), 'wb').write(header)
