#!/usr/bin/env python3
"""Prints the bounding box of one part of a region whose layers are too large for one file.
Usage: region-parts.py south,west,north,east part total [lat|lon]
The region is cut along its longer side (or the given axis) at whole degrees so that every part has about the same number
of Copernicus tiles that exist (land); the parts do not overlap."""
import math, re, sys, urllib.request

LIST = 'https://copernicus-dem-30m.s3.amazonaws.com/tileList.txt'


def tiles(south, west, north, east):
    with urllib.request.urlopen(LIST, timeout=120) as r:
        names = r.read().decode().split()
    found = set()
    for n in names:
        m = re.search(r'_([NS])(\d+)_00_([EW])(\d+)_00_DEM$', n)
        if not m:
            continue
        lat = int(m.group(2)) * (1 if m.group(1) == 'N' else -1)
        lon = int(m.group(4)) * (1 if m.group(3) == 'E' else -1)
        if math.floor(south) <= lat <= math.ceil(north) - 1 and math.floor(west) <= lon <= math.ceil(east) - 1:
            found.add((lat, lon))
    return found


def main():
    south, west, north, east = (float(x) for x in sys.argv[1].split(','))
    part, total = int(sys.argv[2]), int(sys.argv[3])
    axis = sys.argv[4] if len(sys.argv) > 4 else ('lon' if east - west >= north - south else 'lat')
    if not 1 <= part <= total:
        sys.exit('Part %d of %d is not valid' % (part, total))
    land = tiles(south, west, north, east)
    index = 1 if axis == 'lon' else 0
    start = math.floor(west if axis == 'lon' else south)
    end = math.ceil(east if axis == 'lon' else north)
    counts = [0] * (end - start)
    for t in land:
        counts[t[index] - start] += 1
    whole = sum(counts)
    cuts, acc, k = [], 0, 1
    for i, c in enumerate(counts):
        acc += c
        while k < total and acc >= whole * k / total:
            cuts.append(start + i + 1)
            k += 1
    cuts = sorted(set(c for c in cuts if start < c < end))
    if len(cuts) != total - 1:
        sys.exit('The region cannot be cut into %d parts at whole degrees along %s' % (total, axis))
    edges = [None] + cuts + [None]
    low, high = edges[part - 1], edges[part]
    lo = (west if axis == 'lon' else south) if low is None else float(low)
    hi = (east if axis == 'lon' else north) if high is None else float(high)
    if axis == 'lon':
        box = (south, lo, north, hi)
    else:
        box = (lo, west, hi, east)
    print('%.4f,%.4f,%.4f,%.4f' % box)
    sys.stderr.write('part %d/%d along %s: cuts %s, %d land tiles of %d\n' % (part, total, axis, cuts, sum(1 for t in land if (box[1] <= t[1] < box[3]) if axis == 'lon') if axis == 'lon' else sum(1 for t in land if box[0] <= t[0] < box[2]), whole))


if __name__ == '__main__':
    main()
