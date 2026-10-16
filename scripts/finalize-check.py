#!/usr/bin/env python3
"""Checks used by finalize.sh.
  release releases.json [tag]      prints "<id> <tag>" of the draft release layers-* (the only one, or the given tag)
  asset-id assets.json name        prints the id of the uploaded asset with that name
  verify layers.json assets.json tag   fails when the catalog does not match the uploaded assets"""
import json, re, sys


def load(path):
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    return data


def main():
    cmd = sys.argv[1]
    if cmd == 'release':
        drafts = [r for r in load(sys.argv[2]) if r.get('draft') and re.fullmatch(r'layers-[0-9]{4}-[0-9]{2}[a-z0-9-]*', r.get('tag_name', ''))]
        wanted = sys.argv[3] if len(sys.argv) > 3 else ''
        if wanted:
            drafts = [r for r in drafts if r['tag_name'] == wanted]
        if len(drafts) != 1:
            sys.exit('Expected exactly one draft release layers-*, found %d (set TAG)' % len(drafts))
        print(drafts[0]['id'], drafts[0]['tag_name'])
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
        if len(assets) > 1000:
            problems.append('more than 1000 assets')
        if 'LICENSES.txt' not in assets:
            problems.append('LICENSES.txt missing')
        files = 0
        for layer in catalog.get('layers', []):
            refs = [(f['url'], f['size']) for f in layer.get('files', [])]
            poly = layer.get('coverage', {}).get('poly')
            if poly:
                refs.append((poly, None))
            for url, size in refs:
                prefix, _, name = url.partition('/')
                if prefix != tag:
                    continue
                files += 1
                a = assets.get(name)
                if a is None or a.get('state') != 'uploaded':
                    problems.append('%s: asset %s missing' % (layer['id'], name))
                elif size is not None and a['size'] != size:
                    problems.append('%s: asset %s has %d bytes, catalog says %d' % (layer['id'], name, a['size'], size))
        print('layers: %d, files in this release: %d, assets: %d' % (len(catalog.get('layers', [])), files, len(assets)))
        if problems:
            sys.exit('\n'.join(problems[:50]) + '\n%d problem(s); the release was not published' % len(problems))
    else:
        sys.exit('Unknown command ' + cmd)


if __name__ == '__main__':
    main()
