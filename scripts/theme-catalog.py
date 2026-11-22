#!/usr/bin/env python3
"""Writes the GeoKuk themes into layers.json, as the top-level list "themes" next to "layers" (replaced by id).
GeoKuk 6.5.0 (KatalogVrstev) reads only version, sources and layers and ignores other top-level keys, so the list does not change how
it reads the catalogue; "version" stays 1 and nothing is added to "layers".
Usage: theme-catalog.py layers.json themes_dir tag   (themes_dir holds the ZIPs and themes.meta.json of scripts/theme-fetch.sh)"""
import hashlib, json, os, sys

THEMES = [
    dict(id='theme/geokuk', file='GeoKuk-tema.zip', name='GeoKuk', maps='geokuk-maps', layers=['tourist', 'contours']),
    dict(id='theme/geokuk-paws', file='GeoKuk-tema-PAWS.zip', name='GeoKuk (osm.paws.cz)', maps='osm.paws.cz'),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def entries(folder, tag):
    with open(os.path.join(folder, 'themes.meta.json'), encoding='utf-8') as f:
        meta = json.load(f)
    out = []
    for t in THEMES:
        path = os.path.join(folder, t['file'])
        theme = {'id': t['id'], 'name': t['name'], 'for': t['maps']}
        if 'layers' in t:
            theme['layers'] = t['layers']
        theme['files'] = [{'name': t['file'], 'url': '%s/%s' % (tag, t['file']), 'size': os.path.getsize(path),
                           'sha256': sha256(path), 'date': meta['date']}]
        theme.update(geokukVersion=meta['geokukVersion'], geokuk=meta['geokuk'], source=meta['source'])
        out.append(theme)
    return out


def merge(old, new):
    """Themes of old with those of new replaced by id, in the order of THEMES."""
    by_id = {t['id']: t for t in old or []}
    by_id.update({t['id']: t for t in new or []})
    order = [t['id'] for t in THEMES]
    return sorted(by_id.values(), key=lambda t: (order.index(t['id']) if t['id'] in order else len(order), t['id']))


def main():
    catalog_path, folder, tag = sys.argv[1:4]
    with open(catalog_path, encoding='utf-8') as f:
        catalog = json.load(f)
    themes = merge(catalog.get('themes'), entries(folder, tag))
    # Keep "themes" right after "layers" for readability; the other keys keep their order.
    out = {k: v for k, v in catalog.items() if k != 'themes'}
    out['themes'] = themes
    with open(catalog_path, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write('\n')
    for t in themes:
        print('theme %s: %s (%d bytes), GeoKuk %s' % (t['id'], t['files'][0]['url'], t['files'][0]['size'], t['geokukVersion']))


if __name__ == '__main__':
    main()
