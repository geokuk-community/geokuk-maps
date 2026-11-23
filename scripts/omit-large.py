#!/usr/bin/env python3
"""Removes layers that have a file of at least LIMIT bytes (GitHub release assets must be smaller than 2 GiB) and layers that are
still missing parts from layers.json, and warns about files of at least 1.6 GiB, which may reach the limit in a later generation
(build such a region in parts, mapping/region-parts.json). check-draft fails when a layer of the previous release is missing.
Usage: omit-large.py layers.json [limit_bytes]; prints the omitted layers and the large files, one per line, as GitHub warnings."""
import json, sys

LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 2 * 1024 ** 3
WARN = int(1.6 * 1024 ** 3)
with open(sys.argv[1], encoding='utf-8') as f:
    catalog = json.load(f)
kept, omitted = [], []
for layer in catalog['layers']:
    big = [x for x in layer['files'] if x['size'] >= LIMIT]
    if '_parts' in layer:
        omitted.append('%s (parts %s of %d only)' % (layer['id'], layer['_parts']['have'], layer['_parts']['total']))
    elif big:
        omitted.append('%s (%s, %.2f GiB)' % (layer['id'], big[0]['name'], big[0]['size'] / 1024 ** 3))
    else:
        kept.append(layer)
        for x in layer['files']:
            if x['size'] >= WARN:
                print('::warning::%s: %s has %.2f GiB, close to the 2 GiB limit of release assets; consider building it in parts '
                      '(mapping/region-parts.json)' % (layer['id'], x['name'], x['size'] / 1024 ** 3))
if omitted:
    catalog['layers'] = kept
    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write('\n')
    for o in omitted:
        print('::warning::omitted: ' + o)
