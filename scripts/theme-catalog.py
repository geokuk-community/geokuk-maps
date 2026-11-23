#!/usr/bin/env python3
"""Writes the GeoKuk theme GeoKuk-tema.zip (for the maps and layers of GeoKuk) into layers.json, as the top-level list "themes" next to
"layers" (replaced by id). GeoKuk-tema-PAWS.zip (maps of osm.paws.cz) is a release asset only and is not in the catalogue.
GeoKuk 6.5.0 (KatalogVrstev) reads only version, sources and layers and ignores other top-level keys, so the list does not change how
it reads the catalogue; "version" stays 1 and nothing is added to "layers".
The version of the theme comes from tema.json in the ZIP ({"version": N, "for": ...}; N is 1, 2, 3... or a date YYYY.MM.DD): "version"
of the entry. A ZIP without tema.json (GeoKuk 6.5.0-beta.36 and older) gets no "version" and a warning; an invalid tema.json is an error.
"source" links to the GeoKuk release the ZIP comes from.
Usage: theme-catalog.py layers.json themes_dir tag   (themes_dir holds the ZIPs and themes.meta.json of scripts/theme-fetch.sh)"""
import hashlib, json, os, re, sys, zipfile

THEMES = [
    dict(id='theme/geokuk', file='GeoKuk-tema.zip', name='GeoKuk', maps='geokuk-maps', layers=['tourist', 'contours']),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def valid_version(v):
    """A theme version: an integer from 1, or a date YYYY.MM.DD."""
    return (type(v) is int and v >= 1) or (isinstance(v, str) and re.fullmatch(r'[0-9]{4}\.[0-9]{2}\.[0-9]{2}', v) is not None)


def theme_version(path):
    """version from tema.json in the root of the ZIP, None when the ZIP has none; exits on an invalid tema.json."""
    with zipfile.ZipFile(path) as z:
        if 'tema.json' not in z.namelist():
            print('::warning::%s has no tema.json (GeoKuk 6.5.0-beta.36 and older): the catalogue entry gets no version'
                  % os.path.basename(path))
            return None
        try:
            info = json.loads(z.read('tema.json').decode('utf-8'))
        except ValueError as e:
            sys.exit('%s: tema.json is not valid JSON: %s' % (path, e))
    if not isinstance(info, dict) or not valid_version(info.get('version')):
        sys.exit('%s: tema.json needs "version", an integer from 1 or a date YYYY.MM.DD, not %r'
                 % (path, info.get('version') if isinstance(info, dict) else info))
    print('%s: tema.json version %s, for %s' % (os.path.basename(path), info['version'], info.get('for')))
    return info['version']


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
        version = theme_version(path)
        if version is not None:
            theme['version'] = version
        theme['source'] = meta['source']
        out.append(theme)
    return out


def merge(old, new):
    """Themes of old with those of new replaced by id, in the order of THEMES; only the themes of THEMES are kept."""
    order = [t['id'] for t in THEMES]
    by_id = {t['id']: t for t in old or [] if t.get('id') in order}
    by_id.update({t['id']: t for t in new or []})
    return sorted(by_id.values(), key=lambda t: order.index(t['id']))


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
        print('theme %s: %s (%d bytes), version %s, from %s' % (t['id'], t['files'][0]['url'], t['files'][0]['size'],
                                                              t.get('version', '(none)'), t['source']))


if __name__ == '__main__':
    main()
