#!/usr/bin/env python3
"""Prints the download URL of a Geofabrik extract from the Geofabrik index (index-v1-nogeom.json).
Usage: geofabrik-url.py index.json path [kind]; path = Geofabrik path such as europe/germany/bayern, kind = pbf (default), poly, ...
The URLs are taken from the index rather than composed, because Geofabrik moves files (europe/germany/bayern/bayern-latest.osm.pbf)
while the index keeps its structure. A path matches a feature whose chain of parents gives the path, or whose URL lies under it."""
import json, re, sys
from urllib.parse import urlparse


def feature_paths(features):
    """Path of each feature id from its chain of parents (the last part of an id such as us/georgia is its own name)."""
    by_id = {f['properties']['id']: f['properties'] for f in features}
    paths = {}

    def path(ident, depth=0):
        if ident in paths:
            return paths[ident]
        p = by_id.get(ident)
        if p is None or depth > 20:
            return None
        own = ident.rsplit('/', 1)[-1]
        parent = p.get('parent')
        if parent:
            above = path(parent, depth + 1)
            result = above + '/' + own if above else None
        else:
            result = own
        paths[ident] = result
        return result

    for ident in by_id:
        path(ident)
    return paths


def url_path(url):
    """Geofabrik path of a pbf URL: europe/germany/bayern/bayern-latest.osm.pbf and europe/germany/bayern-latest.osm.pbf
    both give europe/germany/bayern."""
    parts = urlparse(url).path.strip('/').split('/')
    m = re.fullmatch(r'(.+?)-latest\.osm\.pbf', parts[-1]) if parts else None
    if not m:
        return None
    if len(parts) >= 2 and parts[-2] == m.group(1):
        return '/'.join(parts[:-1])
    return '/'.join(parts[:-1] + [m.group(1)])


def find(index, key, kind='pbf'):
    features = index.get('features', [])
    paths = feature_paths(features)
    matches = []
    for f in features:
        p = f['properties']
        urls = p.get('urls') or {}
        if paths.get(p['id']) == key or (urls.get('pbf') and url_path(urls['pbf']) == key):
            matches.append(p)
    if len(matches) != 1:
        sys.exit('%s: %d matching extracts in the Geofabrik index' % (key, len(matches)))
    url = (matches[0].get('urls') or {}).get(kind)
    if not url or not url.startswith('https://'):
        sys.exit('%s: no %s URL in the Geofabrik index' % (key, kind))
    return url


def main():
    index_file, key = sys.argv[1:3]
    kind = sys.argv[3] if len(sys.argv) > 3 else 'pbf'
    if not re.fullmatch(r'[a-z0-9-]+(/[a-z0-9-]+)*', key):
        sys.exit('Invalid path: ' + key)
    with open(index_file, encoding='utf-8') as f:
        print(find(json.load(f), key, kind))


if __name__ == '__main__':
    main()
