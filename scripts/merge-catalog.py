#!/usr/bin/env python3
"""Merges a new layers.json into an existing one (layers are replaced by id).
Usage: merge-catalog.py existing.json new.json output.json"""
import json, sys

with open(sys.argv[1], encoding='utf-8') as f:
    old = json.load(f)
with open(sys.argv[2], encoding='utf-8') as f:
    new = json.load(f)
ids = {x['id'] for x in new['layers']}
new['layers'] = sorted([x for x in old.get('layers', []) if x['id'] not in ids] + new['layers'], key=lambda x: x['id'])
new['sources'] = list(dict.fromkeys(old.get('sources', []) + new.get('sources', [])))
with open(sys.argv[3], 'w', encoding='utf-8') as f:
    json.dump(new, f, ensure_ascii=False, indent=2)
    f.write('\n')
