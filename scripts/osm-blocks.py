#!/usr/bin/env python3
"""Assigns regions to the planet blocks of mapping/osm-blocks.json.
Usage: osm-blocks.py block KEY             prints the block of a region (mapsforge key)
       osm-blocks.py streams KEY [KEY...]  prints the streams that are needed, as a JSON matrix {"include": [{"stream", "blocks"}]}
       osm-blocks.py config BLOCK [...]    prints the osmium extract config of the blocks (output BLOCK.osm.pbf)
       osm-blocks.py check                 checks that every outline in mapping/poly has a block and that the streams are consistent
A region goes to the smallest block (by area) that contains the bbox of mapping/poly/KEY.poly widened by the margin."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'mapping', 'osm-blocks.json')
POLY = os.path.join(ROOT, 'mapping', 'poly')
MAX_BLOCKS = 4  # peak RAM of osmium extract on the planet is about 2.4 GB per block (planet-261116), the runner has 16 GB


def load():
    with open(CONFIG, encoding='utf-8') as f:
        return json.load(f)


def bbox(key):
    """west, south, east, north of mapping/poly/KEY.poly."""
    if not re.fullmatch(r'[a-z0-9-]+(/[a-z0-9-]+)*', key):
        sys.exit('Invalid key: ' + key)
    lons, lats = [], []
    with open(os.path.join(POLY, key + '.poly'), encoding='utf-8') as f:
        for line in f:
            m = re.match(r'\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s*$', line)
            if m:
                lons.append(float(m.group(1)))
                lats.append(float(m.group(2)))
    if not lons:
        sys.exit('No coordinates in mapping/poly/%s.poly' % key)
    return min(lons), min(lats), max(lons), max(lats)


def block_of(config, key):
    m = config['margin']
    w, s, e, n = bbox(key)
    w, s, e, n = max(w - m, -180), max(s - m, -90), min(e + m, 180), min(n + m, 90)
    fits = [(abs((b[2] - b[0]) * (b[3] - b[1])), name) for name, b in config['blocks'].items()
            if b[0] <= w and b[1] <= s and b[2] >= e and b[3] >= n]
    if not fits:
        sys.exit('No block of mapping/osm-blocks.json contains %s (%.2f,%.2f,%.2f,%.2f)' % (key, w, s, e, n))
    return min(fits)[1]


def stream_of(config, block):
    return next(s for s, blocks in config['streams'].items() if block in blocks)


def main():
    config = load()
    command, args = sys.argv[1], sys.argv[2:]
    if command == 'block':
        print(block_of(config, args[0]))
    elif command == 'streams':
        needed = {block_of(config, k) for k in args}
        include = [{'stream': s, 'blocks': ' '.join(b for b in blocks if b in needed)}
                   for s, blocks in config['streams'].items() if needed & set(blocks)]
        print(json.dumps({'include': include}))
    elif command == 'config':
        extracts = []
        for name in args:
            if name not in config['blocks']:
                sys.exit('Unknown block: ' + name)
            extracts.append({'output': name + '.osm.pbf', 'bbox': config['blocks'][name]})
        print(json.dumps({'extracts': extracts}, indent=1))
    elif command == 'check':
        in_streams = [b for blocks in config['streams'].values() for b in blocks]
        if sorted(in_streams) != sorted(config['blocks']):
            sys.exit('Every block must be in exactly one stream')
        if max(len(b) for b in config['streams'].values()) > MAX_BLOCKS:
            sys.exit('A stream has more than %d blocks' % MAX_BLOCKS)
        for name, (w, s, e, n) in config['blocks'].items():
            if not (-180 <= w < e <= 180 and -90 <= s < n <= 90):
                sys.exit('Invalid bbox of block ' + name)
        keys = sorted(os.path.relpath(os.path.join(d, f), POLY)[:-5] for d, _, files in os.walk(POLY) for f in files if f.endswith('.poly'))
        count = {}
        for k in keys:
            b = block_of(config, k)
            count[b] = count.get(b, 0) + 1
        print('%d regions: %s' % (len(keys), ', '.join('%s %d' % (b, count.get(b, 0)) for b in config['blocks'])))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
