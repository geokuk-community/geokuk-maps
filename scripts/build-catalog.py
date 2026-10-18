#!/usr/bin/env python3
"""Builds layers.json and SHA256SUMS from *.meta.json (written by write-meta.py).
Usage: build-catalog.py meta_dir region name south,west,north,east [url_prefix]
Environment: EXISTING_CATALOG = path of an existing layers.json to merge the new layers into.
File name = <region with / replaced by _>.<type>.<extension>; files[].path = <region>.<type>.<extension>."""
import glob, json, os, re, sys
from datetime import datetime, timezone

SOURCE = 'https://github.com/geokuk-community/geokuk-maps/releases/download/'

COPERNICUS = ('produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 '
              'provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the '
              'Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.')

TYPES = {
    'tourist': dict(name='Routes and outdoor features – %s', format='map', license='ODbL 1.0',
                    attribution='© OpenStreetMap contributors', theme='tourist'),
    'contours': dict(name='Contour lines – %s (10 m)', format='map', license='Copernicus COP-DEM-GLO-30-F',
                     attribution='Contours: Copernicus DEM GLO-30 © DLR/Airbus, ESA', attributionFull=COPERNICUS,
                     note='Copernicus DEM is a surface model (includes buildings and forest canopy).'),
    'dem': dict(name='Hillshade elevation data – %s (HGT 1")', format='hgt-zip', license='Copernicus COP-DEM-GLO-30-F',
                attribution='Elevation: Copernicus DEM GLO-30 © DLR/Airbus, ESA', attributionFull=COPERNICUS),
}


def build(folder, region, name, bbox, prefix):
    south, west, north, east = (float(x) for x in bbox.split(','))
    layers = []
    for path in sorted(glob.glob(os.path.join(folder, '*.meta.json'))):
        with open(path, encoding='utf-8') as f:
            m = json.load(f)
        t = TYPES[m['type']]
        match = re.fullmatch(r'(.+)\.%s(?:\.([0-9]+))?\.meta\.json' % m['type'], os.path.basename(path))
        base, part = match.group(1), match.group(2)
        suffix = '.' + part if part else ''
        extension = m['name'].rsplit('.', 1)[1]
        coverage = {'bbox': [south, west, north, east]}
        if os.path.exists(os.path.join(folder, base + '.poly')):
            coverage['poly'] = prefix + base + '.poly'
        layer = {'id': '%s/%s' % (m['type'], region), 'type': m['type'], 'region': region, 'format': t['format'],
                 'name': t['name'] % name,
                 'files': [{'name': m['name'], 'path': '%s.%s%s.%s' % (region, m['type'], suffix, extension),
                            'url': prefix + m['name'], 'size': m['size'], 'sha256': m['sha256'], 'date': m['produced']}],
                 'size': m['size'], 'dataDate': m['dataDate'], 'produced': m['produced'], 'dataSource': m['dataSource']}
        if 'zoom' in m:
            layer['zoom'] = m['zoom']
        if 'contourInterval' in m:
            layer['contourInterval'] = m['contourInterval']
        layer['coverage'] = coverage
        if part:
            layer['_parts'] = {'total': int(os.environ['PART_TOTAL']), 'have': [int(part)]}
        for k in ('license', 'attribution', 'attributionFull', 'theme', 'note'):
            if k in m:
                layer[k] = m[k]
            elif k in t:
                layer[k] = t[k]
        layer['licenseText'] = m['licenseText']
        layers.append(layer)
    return layers


def main():
    folder, region, name, bbox = sys.argv[1:5]
    prefix = sys.argv[5] if len(sys.argv) > 5 else ''
    layers = build(folder, region, name, bbox, prefix)
    sources = [SOURCE]
    merged = layers
    existing = os.environ.get('EXISTING_CATALOG')
    if existing and os.path.exists(existing):
        with open(existing, encoding='utf-8') as f:
            old = json.load(f)
        new_ids = {x['id'] for x in layers}
        merged = [x for x in old.get('layers', []) if x['id'] not in new_ids] + layers
        sources = list(dict.fromkeys(old.get('sources', []) + sources))
    out = {'version': 1, 'generated': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), 'sources': sources,
           'layers': sorted(merged, key=lambda x: x['id'])}
    with open(os.path.join(folder, 'layers.json'), 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write('\n')
    with open(os.path.join(folder, 'SHA256SUMS'), 'w', encoding='utf-8') as f:
        for layer in layers:
            for s in layer['files']:
                f.write('%s  %s\n' % (s['sha256'], s['name']))


if __name__ == '__main__':
    main()
