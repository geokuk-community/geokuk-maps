#!/usr/bin/env python3
"""Removes layers that have a file of at least LIMIT bytes (GitHub release assets must be smaller than 2 GiB) and layers that are
still missing parts from layers.json.
Usage: omit-large.py layers.json [limit_bytes]; prints the omitted layers, one per line, as GitHub warnings."""
import json, sys

LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 2 * 1024 ** 3
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
if omitted:
    catalog['layers'] = kept
    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write('\n')
    for o in omitted:
        print('::warning::omitted: ' + o)
