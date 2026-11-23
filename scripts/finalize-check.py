#!/usr/bin/env python3
"""Checks used by finalize.sh.
  release releases.json [tag]      prints "<id> <tag>" of the draft release layers-* (the only one, or the given tag); fails when a published release is not older
  asset-id assets.json name        prints the id of the uploaded asset with that name
  verify layers.json assets.json tag   fails when size or sha256 of a file (layers and themes) differ from the uploaded assets or the
                                   catalogue does not keep the rules of the GeoKuk catalogue reader (see compat); warns about unreferenced assets
  compat layers.json               only the catalogue rules: what GeoKuk 6.5.0 (KatalogVrstev) needs and the theme theme/geokuk
  map-assets layers.json tag dir   prints "<release> <asset id> <name>" of every tourist and contours .map in layers.json, with
                                   dir/<tag>.assets.json for this release and dir/<release>.assets.json for older ones
  previous releases.json tag       prints "<id> <tag>" of the newest published release layers-* older than tag (nothing for the first one)
  compare layers.json previous.json   fails when a layer id of the previous release is missing, unless mapping/removed-layers.txt
                                   (or the file in REMOVED_LAYERS) lists it
  other-tags layers.json tag       prints the other releases that layers.json points to (dem and contours kept from an older release)
  verify-other layers.json tag dir     the same checks for the files in those releases, with dir/<release>.assets.json and
                                   dir/releases.json (the release must be published, not a draft)"""
import json, os, re, sys


def load(path):
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    return data


# The theme in layers.json (scripts/theme-catalog.py), and the theme assets that every release carries, so that
# .../releases/latest/download/<file> always works: GeoKuk-tema-PAWS.zip (maps of osm.paws.cz) is an asset only, not in the catalogue.
THEMES = {'theme/geokuk': 'GeoKuk-tema.zip'}
THEME_ASSETS = ('GeoKuk-tema.zip', 'GeoKuk-tema.zip.sha256', 'GeoKuk-tema-PAWS.zip', 'GeoKuk-tema-PAWS.zip.sha256')
KNOWN = {'tourist': 'map', 'contours': 'map', 'dem': 'hgt-zip'}
SHA256 = re.compile(r'[0-9a-f]{64}')


def compat(catalog):
    """Problems of layers.json under the rules of the catalogue reader of GeoKuk 6.5.0 (KatalogVrstev.nacti): version is the integer 1;
    a layer of an unknown type or format is skipped, any other defect of a layer fails the whole catalogue; ids and file paths are unique
    among the layers. The reader ignores other top-level keys such as "themes", which must hold the theme theme/geokuk only."""
    problems = []
    if type(catalog.get('version')) is not int or catalog['version'] != 1:
        problems.append('layers.json: version must be the integer 1 (GeoKuk 6.5.0 reads a higher one as a newer format)')
    if not isinstance(catalog.get('sources'), list) or not isinstance(catalog.get('layers'), list):
        problems.append('layers.json: sources and layers must be lists')
        return problems
    ids, paths = set(), set()
    for layer in catalog['layers']:
        if not isinstance(layer, dict):
            problems.append('layers.json: a layer is not an object')
            continue
        if KNOWN.get(layer.get('type')) != layer.get('format'):
            continue
        ident = layer.get('id')
        for k in ('id', 'region', 'name'):
            if not isinstance(layer.get(k), str) or not layer.get(k):
                problems.append('%s: %s missing' % (ident, k))
        if ident in ids:
            problems.append('%s: id is not unique' % ident)
        ids.add(ident)
        files = layer.get('files')
        if not isinstance(files, list) or not files:
            problems.append('%s: files missing' % ident)
            files = []
        for f in files:
            if not isinstance(f, dict) or not all(isinstance(f.get(k), str) and f.get(k) for k in ('name', 'path', 'url')) \
                    or type(f.get('size')) is not int or not SHA256.fullmatch(str(f.get('sha256'))):
                problems.append('%s: a file lacks name, path, url, size or sha256' % ident)
                continue
            if f['path'] in paths:
                problems.append('%s: file path %s is not unique' % (ident, f['path']))
            paths.add(f['path'])
        zoom = layer.get('zoom')
        if zoom is not None and not (isinstance(zoom, dict) and type(zoom.get('min')) is int and type(zoom.get('max')) is int):
            problems.append('%s: zoom must have integer min and max' % ident)
        if 'theme' in layer and not isinstance(layer['theme'], str):
            problems.append('%s: theme must be a text' % ident)
    themes = catalog.get('themes')
    if not isinstance(themes, list):
        problems.append('layers.json: themes missing')
        themes = []
    found = {}
    for t in themes:
        ident = t.get('id') if isinstance(t, dict) else None
        if ident in found:
            problems.append('%s: theme id is not unique' % ident)
        files = t.get('files') if isinstance(t, dict) else None
        if not isinstance(files, list) or len(files) != 1 or not isinstance(files[0], dict) \
                or type(files[0].get('size')) is not int or not SHA256.fullmatch(str(files[0].get('sha256'))) \
                or not all(isinstance(files[0].get(k), str) for k in ('name', 'url', 'date')) \
                or not all(isinstance(t.get(k), str) and t.get(k) for k in ('name', 'for', 'geokukVersion', 'source')):
            problems.append('%s: a theme needs name, for, geokukVersion, source and one file with name, url, size, sha256, date' % ident)
            continue
        found[ident] = files[0]['name']
    for ident, name in THEMES.items():
        if found.get(ident) != name:
            problems.append('%s: theme with the file %s missing' % (ident, name))
    for ident in sorted(set(found) - set(THEMES)):
        problems.append('%s: theme not expected in layers.json' % ident)
    return problems


def references(catalog):
    """(layer or theme id, release, asset name, size or None, sha256 or None) of every file and outline in layers.json."""
    for theme in catalog.get('themes', []):
        for f in theme.get('files', []):
            prefix, _, name = f['url'].partition('/')
            yield theme['id'], prefix, name, f['size'], f['sha256']
    for layer in catalog.get('layers', []):
        for f in layer.get('files', []):
            prefix, _, name = f['url'].partition('/')
            yield layer['id'], prefix, name, f['size'], f['sha256']
        poly = layer.get('coverage', {}).get('poly')
        if poly:
            prefix, _, name = poly.partition('/')
            yield layer['id'], prefix, name, None, None


def check_asset(problems, ident, name, a, size, sha256, no_digest):
    if a is None or a.get('state') != 'uploaded':
        problems.append('%s: asset %s missing' % (ident, name))
    elif size is not None and a['size'] != size:
        problems.append('%s: asset %s has %d bytes, catalog says %d' % (ident, name, a['size'], size))
    elif size is not None:
        digest = a.get('digest')
        if digest is None:
            if not no_digest:
                problems.append('%s: asset %s has no digest, sha256 cannot be verified' % (ident, name))
        elif digest != 'sha256:' + sha256:
            problems.append('%s: asset %s has %s, catalog says sha256:%s' % (ident, name, digest, sha256))


def main():
    cmd = sys.argv[1]
    if cmd == 'release':
        drafts = [r for r in load(sys.argv[2]) if r.get('draft') and re.fullmatch(r'layers-[0-9]{4}-[0-9]{2}[a-z0-9-]*', r.get('tag_name', ''))]
        wanted = sys.argv[3] if len(sys.argv) > 3 else ''
        if wanted:
            drafts = [r for r in drafts if r['tag_name'] == wanted]
        if len(drafts) != 1:
            sys.exit('Expected exactly one draft release layers-*, found %d (set TAG)' % len(drafts))
        tag = drafts[0]['tag_name']
        newer = sorted(r['tag_name'] for r in load(sys.argv[2]) if not r.get('draft') and re.fullmatch(r'layers-[0-9]{4}-[0-9]{2}[a-z0-9-]*', r.get('tag_name', '')) and r['tag_name'] >= tag)
        if newer:
            sys.exit('Published release %s is not older than the draft %s; the latest release would go back' % (newer[-1], tag))
        print(drafts[0]['id'], tag)
    elif cmd == 'asset-id':
        for a in load(sys.argv[2]):
            if a['name'] == sys.argv[3] and a.get('state') == 'uploaded':
                print(a['id'])
                return
        sys.exit('Asset %s not found' % sys.argv[3])
    elif cmd == 'verify':
        catalog, assets, tag = load(sys.argv[2]), {a['name']: a for a in load(sys.argv[3])}, sys.argv[4]
        problems = []
        if catalog.get('version') != 1 or not catalog.get('sources') or not catalog.get('layers'):
            problems.append('layers.json: version/sources/layers missing')
        problems += compat(catalog)
        if len(assets) > 1000:
            problems.append('more than 1000 assets')
        if 'LICENSES.txt' not in assets:
            problems.append('LICENSES.txt missing')
        files = 0
        referenced = {'layers.json', 'LICENSES.txt'} | set(THEME_ASSETS)
        for name in THEME_ASSETS:
            if assets.get(name, {}).get('state') != 'uploaded':
                problems.append('theme asset %s missing' % name)
        no_digest = os.environ.get('ALLOW_NO_DIGEST') == '1'
        for layer in catalog.get('layers', []) + catalog.get('themes', []):
            refs = [(f['url'], f['size']) for f in layer.get('files', [])]
            poly = layer.get('coverage', {}).get('poly')
            if poly:
                refs.append((poly, None))
            for url, size in refs:
                prefix, _, name = url.partition('/')
                if prefix != tag:
                    continue
                files += 1
                referenced.add(name)
                a = assets.get(name)
                if a is None or a.get('state') != 'uploaded':
                    problems.append('%s: asset %s missing' % (layer['id'], name))
                elif size is not None and a['size'] != size:
                    problems.append('%s: asset %s has %d bytes, catalog says %d' % (layer['id'], name, a['size'], size))
                elif size is not None:
                    digest = a.get('digest')
                    expected = {f['url']: f['sha256'] for f in layer['files']}[url]
                    if digest is None:
                        if not no_digest:
                            problems.append('%s: asset %s has no digest, sha256 cannot be verified' % (layer['id'], name))
                    elif digest != 'sha256:' + expected:
                        problems.append('%s: asset %s has %s, catalog says sha256:%s' % (layer['id'], name, digest, expected))
        for name in sorted(set(assets) - referenced):
            print('::warning::asset %s is not referenced by layers.json' % name)
        by_type = {}
        for layer in catalog.get('layers', []):
            by_type[layer['type']] = by_type.get(layer['type'], 0) + 1
        print('layers by type: ' + ', '.join('%s %d' % kv for kv in sorted(by_type.items())))
        print('layers: %d, files in this release: %d, assets: %d' % (len(catalog.get('layers', [])), files, len(assets)))
        if problems:
            sys.exit('\n'.join(problems[:50]) + '\n%d problem(s); the release was not published' % len(problems))
    elif cmd == 'compat':
        problems = compat(load(sys.argv[2]))
        if problems:
            sys.exit('\n'.join(problems[:50]) + '\n%d problem(s)' % len(problems))
        print('layers.json keeps the catalogue rules of GeoKuk 6.5.0 and has the theme theme/geokuk')
    elif cmd == 'map-assets':
        catalog, tag, folder = load(sys.argv[2]), sys.argv[3], sys.argv[4]
        assets = {}
        for layer in catalog.get('layers', []):
            if layer.get('type') not in ('tourist', 'contours'):
                continue
            for f in layer['files']:
                prefix, _, name = f['url'].partition('/')
                if not re.fullmatch(r'layers-[0-9]{4}-[0-9]{2}[a-z0-9-]*', prefix) or not re.fullmatch(r'[A-Za-z0-9._-]+\.map', name):
                    sys.exit('%s: unexpected file url %s' % (layer['id'], f['url']))
                if prefix not in assets:
                    assets[prefix] = {a['name']: a for a in load(os.path.join(folder, prefix + '.assets.json'))}
                a = assets[prefix].get(name)
                if a is None:
                    sys.exit('%s: asset %s missing' % (layer['id'], f['url']))
                print(prefix, a['id'], name)
    elif cmd == 'previous':
        tag = sys.argv[3]
        older = sorted((r['tag_name'], r['id']) for r in load(sys.argv[2]) if not r.get('draft')
                       and re.fullmatch(r'layers-[0-9]{4}-[0-9]{2}[a-z0-9-]*', r.get('tag_name', '')) and r['tag_name'] < tag)
        if older:
            print(older[-1][1], older[-1][0])
    elif cmd == 'compare':
        new, old = load(sys.argv[2]), load(sys.argv[3])
        removed = set()
        path = os.environ.get('REMOVED_LAYERS') or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'mapping', 'removed-layers.txt')
        if os.path.exists(path):
            with open(path, encoding='utf-8') as f:
                removed = {line.strip() for line in f if line.strip() and not line.startswith('#')}
        have = {x['id'] for x in new.get('layers', [])}
        missing = sorted({x['id'] for x in old.get('layers', [])} - have - removed)
        print('layers: %d in the previous release, %d in this one, %d removed on purpose' % (len(old.get('layers', [])), len(have), len(removed)))
        if missing:
            sys.exit('%d layer(s) of the previous release are missing (omitted at 2 GiB, a failed build, or removed: then list them in '
                     'mapping/removed-layers.txt): %s' % (len(missing), ', '.join(missing[:50])))
    elif cmd == 'other-tags':
        tag = sys.argv[3]
        for t in sorted({r[1] for r in references(load(sys.argv[2])) if r[1] != tag}):
            if not re.fullmatch(r'layers-[0-9]{4}-[0-9]{2}[a-z0-9-]*', t):
                sys.exit('layers.json points to %s, which is not a layers-* release' % t)
            print(t)
    elif cmd == 'verify-other':
        catalog, tag, folder = load(sys.argv[2]), sys.argv[3], sys.argv[4]
        published = {r['tag_name'] for r in load(os.path.join(folder, 'releases.json')) if not r.get('draft')}
        no_digest = os.environ.get('ALLOW_NO_DIGEST') == '1'
        problems, assets, count = [], {}, {}
        for ident, prefix, name, size, sha256 in references(catalog):
            if prefix == tag:
                continue
            if prefix not in assets:
                if prefix not in published:
                    problems.append('%s: release %s is not published' % (ident, prefix))
                path = os.path.join(folder, prefix + '.assets.json')
                assets[prefix] = {a['name']: a for a in load(path)} if os.path.exists(path) else {}
            count[prefix] = count.get(prefix, 0) + 1
            check_asset(problems, ident, prefix + '/' + name, assets[prefix].get(name), size, sha256, no_digest)
        print('files in older releases: ' + (', '.join('%s %d' % kv for kv in sorted(count.items())) or 'none'))
        if problems:
            sys.exit('\n'.join(problems[:50]) + '\n%d problem(s) in older releases; the release was not published' % len(problems))
    else:
        sys.exit('Unknown command ' + cmd)


if __name__ == '__main__':
    main()
