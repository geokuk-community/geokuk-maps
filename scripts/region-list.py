#!/usr/bin/env python3
"""Expands the regions input of Layers.
Usage: region-list.py [--types TYPES] REGIONS...
  "all" stands for every key in mapping/poly; a key listed in mapping/region-parts.json is followed by key:part/total[/axis]
  for each of its parts (dem and contours), other entries are kept as given. Prints one entry per line, sorted, without duplicates.
  With --types tourist (the types input of Layers), "all" gives no parts: a part builds only dem and contours, and build-region.sh
  fails on a part with the tourist layer (run 44886196372, 24 failed jobs). A part given explicitly is kept.
  region-list.py --parts KEY prints the part spec of KEY (total[/axis]) or nothing."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLY = os.path.join(ROOT, 'mapping', 'poly')
PARTS = os.path.join(ROOT, 'mapping', 'region-parts.json')


def parts():
    with open(PARTS, encoding='utf-8') as f:
        result = json.load(f)['parts']
    for key, spec in result.items():
        if not re.fullmatch(r'[1-9][0-9]*(/(lat|lon))?', spec) or not os.path.isfile(os.path.join(POLY, key + '.poly')):
            sys.exit('Invalid entry in mapping/region-parts.json: %s %s' % (key, spec))
    return result


def keys():
    return sorted(os.path.relpath(os.path.join(d, f), POLY)[:-5].replace(os.sep, '/')
                  for d, _, files in os.walk(POLY) for f in files if f.endswith('.poly'))


def expand(entries, types='all'):
    split = parts() if types in ('all', 'dem', 'contours') else {}
    out = []
    for entry in entries:
        if entry != 'all':
            out.append(entry)
            continue
        for key in keys():
            out.append(key)
            if key in split:
                total, _, axis = split[key].partition('/')
                out += ['%s:%d/%s%s' % (key, i, total, '/' + axis if axis else '') for i in range(1, int(total) + 1)]
    return sorted(set(out))


def main():
    if sys.argv[1:2] == ['--parts']:
        print(parts().get(sys.argv[2], ''))
        return
    args, types = sys.argv[1:], 'all'
    if args[:1] == ['--types']:
        types, args = args[1], args[2:]
        if types not in ('all', 'tourist', 'dem', 'contours'):
            sys.exit('Invalid types: ' + types)
    for entry in expand(args, types):
        print(entry)


if __name__ == '__main__':
    main()
