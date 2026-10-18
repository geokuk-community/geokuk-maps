#!/usr/bin/env python3
"""Writes the region outline from OSM administrative boundaries (no buffer) as an osmosis .poly file.
Usage: region-polygon.py region.osm.pbf geofabrik.poly output.poly [work_dir]
The Geofabrik .poly (buffered) only tells which administrative units belong to the region: the units of one admin_level (2..6)
that lie mostly inside it are united. When no level covers the Geofabrik polygon, the Geofabrik .poly is written instead.
Requires osmium and shapely."""
import json, os, re, subprocess, sys, tempfile
import shapely
from shapely.geometry import shape
from shapely.ops import unary_union

LEVELS = (2, 3, 4, 5, 6)
INSIDE = 0.5      # share of a unit that must lie inside the Geofabrik polygon
PRECISION = 0.95  # share of the united units inside the Geofabrik polygon
RECALL = 0.8      # share of the Geofabrik polygon covered by the united units
HOLE = 0.9        # share of a hole inside the Geofabrik polygon for it to be filled (enclaves such as Berlin)
SIMPLIFY = 0.0002  # degrees, about 20 m, below the 1" DEM pixel


def read_poly(path):
    rings, current, name = [], None, None
    with open(path, encoding='utf-8') as f:
        lines = [l.strip() for l in f if l.strip()]
    positive, negative = [], []
    for line in lines[1:]:
        if line.upper() == 'END':
            if current is not None:
                if len(current) >= 4:
                    (negative if name.startswith('!') else positive).append(shapely.Polygon(current).buffer(0))
                current = None
            continue
        parts = line.split()
        if current is None:
            name, current = line, []
        elif len(parts) == 2:
            current.append((float(parts[0]), float(parts[1])))
    if not positive:
        sys.exit('No polygon in ' + path)
    geometry = unary_union(positive)
    return geometry.difference(unary_union(negative)) if negative else geometry


def write_poly(path, geometry):
    polygons = [geometry] if geometry.geom_type == 'Polygon' else list(geometry.geoms)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('region\n')
        for i, p in enumerate(polygons, 1):
            f.write('%d\n' % i)
            for lon, lat in p.exterior.coords:
                f.write('   %.7f   %.7f\n' % (lon, lat))
            f.write('END\n')
        f.write('END\n')


def boundaries(pbf, work):
    """Administrative areas of levels LEVELS in the pbf as {level: [geometry]}."""
    a, b, out = (os.path.join(work, n) for n in ('boundary.osm.pbf', 'levels.osm.pbf', 'areas.geojsonseq'))
    subprocess.run(['osmium', 'tags-filter', '--overwrite', '-o', a, pbf, 'r/boundary=administrative'], check=True)
    subprocess.run(['osmium', 'tags-filter', '--overwrite', '-o', b, a] + ['r/admin_level=%d' % l for l in LEVELS], check=True)
    subprocess.run(['osmium', 'export', '--overwrite', '-f', 'geojsonseq', '--geometry-types=polygon', '--add-unique-id=type_id',
                    '-o', out, b], check=True)
    result = {l: [] for l in LEVELS}
    with open(out, encoding='utf-8') as f:
        for line in f:
            line = line.strip().lstrip('\x1e')
            if not line:
                continue
            feature = json.loads(line)
            ident = str(feature.get('id', ''))
            if not (ident.startswith('a') and ident[1:].isdigit() and int(ident[1:]) % 2 == 1):  # odd area ids come from relations
                continue
            level = (feature.get('properties') or {}).get('admin_level')
            if level and level.isdigit() and int(level) in result:
                geometry = shape(feature['geometry'])
                if geometry.is_valid and not geometry.is_empty:
                    result[int(level)].append(geometry)
    return result


def choose(areas, region):
    best = None
    for level in LEVELS:
        units = [g for g in areas[level] if g.intersects(region) and g.intersection(region).area >= INSIDE * g.area]
        if not units:
            continue
        united = fill_enclaves(unary_union(units), region)
        inside = united.intersection(region).area
        precision, recall = inside / united.area, inside / region.area
        print('admin_level %d: %d units, precision %.3f, recall %.3f' % (level, len(units), precision, recall), flush=True)
        if precision >= PRECISION and recall >= RECALL and (best is None or recall > best[0] + 0.005):
            best = (recall, level, united)
    return best


def fill_enclaves(united, region):
    """Fills holes that lie inside the Geofabrik polygon; the other holes are joined to the outside by a slit (.poly rings have no holes)."""
    result = []
    for p in ([united] if united.geom_type == 'Polygon' else list(united.geoms)):
        polygon = shapely.Polygon(p.exterior)
        for ring in p.interiors:
            hole = shapely.Polygon(ring)
            if hole.intersection(region).area >= HOLE * hole.area:
                continue
            point = hole.representative_point()
            slit = shapely.LineString([(polygon.bounds[0] - 1, point.y), (point.x, point.y)]).buffer(1e-6)
            polygon = polygon.difference(hole.union(slit))
        result.extend([polygon] if polygon.geom_type == 'Polygon' else list(polygon.geoms))
    return unary_union(result) if len(result) == 1 else shapely.MultiPolygon(result)


def main():
    pbf, geofabrik, output = sys.argv[1:4]
    work = sys.argv[4] if len(sys.argv) > 4 else tempfile.mkdtemp()
    os.makedirs(work, exist_ok=True)
    region = read_poly(geofabrik)
    best = choose(boundaries(pbf, work), region)
    if best is None:
        print('No administrative level fits the region, using the Geofabrik polygon', flush=True)
        geometry = region
    else:
        print('Using admin_level %d (recall %.3f)' % (best[1], best[0]), flush=True)
        geometry = best[2]
    geometry = geometry.simplify(SIMPLIFY, preserve_topology=True)
    write_poly(output, geometry)


if __name__ == '__main__':
    main()
