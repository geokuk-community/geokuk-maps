#!/usr/bin/env python3
"""Merges a new layers.json into an existing one (layers are replaced by id).
A layer built in parts carries "_parts": {"total", "have"}; parts of the same layer are combined into one layer with several files
until all parts are present. Usage: merge-catalog.py existing.json new.json output.json"""
import json, sys


def union(a, b):
    return [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


def combine(old, new):
    paths = {f['path'] for f in new['files']}
    merged = dict(new)
    merged['files'] = sorted([f for f in old['files'] if f['path'] not in paths] + new['files'], key=lambda f: f['path'])
    merged['size'] = sum(f['size'] for f in merged['files'])
    merged['coverage'] = dict(new['coverage'], bbox=union(old['coverage']['bbox'], new['coverage']['bbox']))
    have = sorted(set(old['_parts']['have']) | set(new['_parts']['have']))
    merged['_parts'] = {'total': new['_parts']['total'], 'have': have}
    if len(have) == merged['_parts']['total']:
        del merged['_parts']
    return merged


def main():
    with open(sys.argv[1], encoding='utf-8') as f:
        old = json.load(f)
    with open(sys.argv[2], encoding='utf-8') as f:
        new = json.load(f)
    current = {x['id']: x for x in old.get('layers', [])}
    for layer in new['layers']:
        previous = current.get(layer['id'])
        if '_parts' in layer and previous and '_parts' in previous and previous['_parts']['total'] == layer['_parts']['total']:
            layer = combine(previous, layer)
        current[layer['id']] = layer
    new['layers'] = sorted(current.values(), key=lambda x: x['id'])
    new['sources'] = list(dict.fromkeys(old.get('sources', []) + new.get('sources', [])))
    with open(sys.argv[3], 'w', encoding='utf-8') as f:
        json.dump(new, f, ensure_ascii=False, indent=2)
        f.write('\n')


if __name__ == '__main__':
    main()
