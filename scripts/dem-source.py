#!/usr/bin/env python3
"""Decides whether the dem and contours layers of a region must be built again, from mapping/dem-manifest.json.
The manifest records, per region (mapsforge key), the release whose dem and contours files layers.json points to and the
fingerprint of their sources at that time:
  copernicus  sha256 of the Copernicus tiles around the region (mapping/copernicus-tilelist.txt; the data set dates from 2022)
  cuzk        sha256 of the ČÚZK DMR 4G sheets around the region in the ATOM feed (only europe/czech-republic)
  poly        sha256 of the region outline mapping/poly/<key>.poly (it decides the bbox)
A region whose fingerprint is unchanged keeps its dem and contours: publish.sh merges the new layers into the previous layers.json,
so the old entries, which point to the older release, stay as they are.

Usage:
  dem-source.py reuse KEY               exit 0 when the dem and contours of KEY can be kept (prints why), 1 when they must be built
  dem-source.py fingerprint KEY         prints the current fingerprint of KEY as JSON
  dem-source.py update layers.json [KEY ...]
                                        records the releases of the dem and contours layers in layers.json with the current
                                        fingerprints (all regions of layers.json, or the given keys); run by the workflow
                                        DEM manifest (.github/workflows/dem-manifest.yml) after a release
  dem-source.py check layers.json [tag] fails when a region of the manifest has no dem or contours layer pointing to its release
                                        (or to the release being checked, for a region built again)
Env: CUZK_ATOM (file with the ATOM feed instead of downloading it)."""
import hashlib, json, math, os, re, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, 'mapping', 'dem-manifest.json')
TILES = os.path.join(ROOT, 'mapping', 'copernicus-tilelist.txt')
POLY = os.path.join(ROOT, 'mapping', 'poly')
CUZK_REGIONS = {'europe/czech-republic'}  # as DEM_CUZK in build-region.sh
ATOM = 'https://atom.cuzk.gov.cz/DMR4G-SJTSK/DMR4G-SJTSK.xml'
HEADERS = {'User-Agent': 'GeoKuk-vrstvy/1.0 (+https://github.com/geokuk-community/geokuk-maps)'}
TYPES = ('dem', 'contours')


def check_key(key):
    if not re.fullmatch(r'[a-z0-9-]+(/[a-z0-9-]+)*', key):
        sys.exit('Invalid key: ' + key)
    return key


def bbox(key):
    lons, lats = [], []
    with open(os.path.join(POLY, key + '.poly'), encoding='utf-8') as f:
        for line in f:
            m = re.match(r'\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s*$', line)
            if m:
                lons.append(float(m.group(1)))
                lats.append(float(m.group(2)))
    return min(lats), min(lons), max(lats), max(lons)


def sha(lines):
    return hashlib.sha256(('\n'.join(lines) + '\n').encode('utf-8')).hexdigest()


def copernicus(south, west, north, east):
    """The tiles that cop2hgt.py reads for the bbox (one tile around it as well)."""
    lat0, lat1 = math.floor(south) - 1, math.ceil(north)
    lon0, lon1 = math.floor(west) - 1, math.ceil(east)
    found = []
    with open(TILES, encoding='utf-8') as f:
        for line in f:
            m = re.fullmatch(r'Copernicus_DSM_COG_10_([NS])(\d+)_00_([EW])(\d+)_00_DEM', line.strip())
            if m:
                lat = int(m.group(2)) * (1 if m.group(1) == 'N' else -1)
                lon = int(m.group(4)) * (1 if m.group(3) == 'E' else -1)
                if lat0 <= lat <= lat1 and lon0 <= lon <= lon1:
                    found.append(line.strip())
    return sha(sorted(found))


def atom():
    path = os.environ.get('CUZK_ATOM')
    if path:
        with open(path, encoding='utf-8-sig') as f:
            return f.read()
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(ATOM, headers=HEADERS), timeout=120) as r:
                return r.read().decode('utf-8-sig')
        except OSError:
            time.sleep(5 * (attempt + 1))
    raise RuntimeError('ČÚZK ATOM feed not available')


def cuzk(south, west, north, east):
    """The sheets that cuzk2hgt.py reads for the bbox, each with its <updated> date (or the whole entry when it has none)."""
    found = []
    for entry in atom().split('<entry>')[1:]:
        entry = entry.split('</entry>')[0]
        code = re.search(r'CUZK_DMR4G-SJTSK_([A-Z0-9]+)\.xml', entry)
        polygon = re.search(r'<georss:polygon>([^<]+)</georss:polygon>', entry)
        if not code or not polygon:
            continue
        v = [float(x) for x in polygon.group(1).split()]
        lats, lons = v[0::2], v[1::2]
        if max(lats) >= south and min(lats) <= north and max(lons) >= west and min(lons) <= east:
            updated = re.search(r'<updated>([^<]+)</updated>', entry)
            found.append('%s %s' % (code.group(1), updated.group(1).strip() if updated else hashlib.sha256(entry.encode()).hexdigest()))
    if not found:
        raise RuntimeError('No DMR 4G sheet in the ATOM feed for the region')
    return sha(sorted(found))


def fingerprint(key, cuzk_part=True):
    box = bbox(key)
    with open(os.path.join(POLY, key + '.poly'), 'rb') as f:
        result = {'copernicus': copernicus(*box), 'poly': hashlib.sha256(f.read()).hexdigest()}
    if key in CUZK_REGIONS and cuzk_part:
        result['cuzk'] = cuzk(*box)
    return result


def load_manifest():
    with open(MANIFEST, encoding='utf-8') as f:
        return json.load(f)


def save_manifest(manifest):
    manifest['regions'] = dict(sorted(manifest['regions'].items()))
    with open(MANIFEST, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
        f.write('\n')


def releases(catalog):
    """{region: {type: release}} of the dem and contours layers (complete ones only) of a layers.json."""
    result = {}
    for layer in catalog.get('layers', []):
        if layer['type'] in TYPES and '_parts' not in layer and layer.get('files'):
            tags = {f['url'].split('/')[0] for f in layer['files']}
            if len(tags) == 1:
                result.setdefault(layer['region'], {})[layer['type']] = tags.pop()
    return result


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    command, args = sys.argv[1], sys.argv[2:]
    if command == 'reuse':
        key = check_key(args[0])
        entry = load_manifest()['regions'].get(key)
        if not entry or not all(entry.get(t) for t in TYPES):
            print('%s: not in mapping/dem-manifest.json, dem and contours are built' % key)
            sys.exit(1)
        expected = {'copernicus', 'poly'} | ({'cuzk'} if key in CUZK_REGIONS else set())
        missing = sorted(expected - set(entry.get('fingerprint', {})))
        if missing:
            print('%s: no recorded fingerprint of %s, dem and contours are built' % (key, ', '.join(missing)))
            sys.exit(1)
        try:
            current = fingerprint(key)
        except (OSError, RuntimeError) as ex:
            print('%s: fingerprint not available (%s), dem and contours are built' % (key, ex))
            sys.exit(1)
        changed = [k for k, v in current.items() if entry.get('fingerprint', {}).get(k) != v]
        if changed:
            print('%s: %s changed since %s, dem and contours are built' % (key, ', '.join(changed), entry['dem']))
            sys.exit(1)
        print('%s: sources unchanged, keeping dem from %s and contours from %s' % (key, entry['dem'], entry['contours']))
    elif command == 'fingerprint':
        print(json.dumps(fingerprint(check_key(args[0])), indent=1))
    elif command == 'update':
        with open(args[0], encoding='utf-8') as f:
            found = releases(json.load(f))
        manifest = load_manifest()
        keys = [check_key(k) for k in args[1:]] or sorted(found)
        for key in keys:
            if not all(t in found.get(key, {}) for t in TYPES):
                print('%s: no complete dem and contours in %s, left out' % (key, args[0]))
                manifest['regions'].pop(key, None)
                continue
            entry = dict(found[key])
            try:
                entry['fingerprint'] = fingerprint(key)
            except (OSError, RuntimeError) as ex:
                print('::warning::%s: ČÚZK fingerprint not available (%s); recorded without it, so it is built next time' % (key, ex))
                entry['fingerprint'] = fingerprint(key, cuzk_part=False)
            manifest['regions'][key] = entry
        save_manifest(manifest)
        print('%d regions in the manifest' % len(manifest['regions']))
    elif command == 'check':
        with open(args[0], encoding='utf-8') as f:
            found = releases(json.load(f))
        tag = args[1] if len(args) > 1 else None
        problems = ['%s: %s from %s is not in layers.json' % (key, t, entry[t])
                    for key, entry in sorted(load_manifest()['regions'].items()) for t in TYPES
                    if found.get(key, {}).get(t) not in (entry.get(t), tag)]
        if problems:
            sys.exit('\n'.join(problems) + '\nlayers.json does not match mapping/dem-manifest.json (%d problem(s))' % len(problems))
        print('dem and contours of all %d regions of the manifest are in layers.json' % len(load_manifest()['regions']))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
