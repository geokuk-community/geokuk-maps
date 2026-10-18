#!/usr/bin/env python3
"""Copernicus GLO-30 (AWS Open Data) -> HGT 1" (3601x3601, big-endian int16) for an area.
Usage: cop2hgt.py south,west,north,east output_dir work_dir
Above 50 degrees GLO-30 has a coarser spacing along the longitude (1.5" to 10"); the tiles are resampled with a cubic spline
and smoothed along the longitude so that no vertical stripes remain in the shading and the contours.
Requires numpy, scipy and GDAL (gdalbuildvrt, gdalwarp)."""
import email.utils, math, os, subprocess, sys, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from scipy.ndimage import gaussian_filter1d

URL = 'https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_{n}_00_{e}_00_DEM/Copernicus_DSM_COG_10_{n}_00_{e}_00_DEM.tif'


def tile_name(lat, lon):
    return '%s%02d' % ('N' if lat >= 0 else 'S', abs(lat)), '%s%03d' % ('E' if lon >= 0 else 'W', abs(lon))


LIST = 'https://copernicus-dem-30m.s3.amazonaws.com/tileList.txt'
AVAILABLE = set()


def load_tile_list():
    for attempt in range(5):
        try:
            with urllib.request.urlopen(LIST, timeout=120) as r:
                return {line.strip() for line in r.read().decode().splitlines() if line.strip()}
        except OSError:
            time.sleep(2 * (attempt + 1))
    raise RuntimeError('tile list not available')


SIGMA = 0.7  # smoothing along the longitude in output (1") columns per unit of the coarser source spacing
PAD = 8  # columns warped beyond each side of a tile so that the smoothing is the same on both sides of a tile edge


def spacing(lat):
    """GLO-30 spacing along the longitude in arc seconds for the tile with the south edge at lat."""
    a = abs(lat) if lat >= 0 else abs(lat) - 1  # the southern hemisphere tiles lie between -lat-1 and -lat
    for limit, seconds in ((85, 10), (80, 5), (70, 3), (60, 2), (50, 1.5)):
        if a >= limit:
            return seconds
    return 1


def download(args):
    lat, lon, folder = args
    n, e = tile_name(lat, lon)
    if 'Copernicus_DSM_COG_10_%s_00_%s_00_DEM' % (n, e) not in AVAILABLE:
        return None
    target = os.path.join(folder, n + e + '.tif')
    if os.path.exists(target):
        return target
    for attempt in range(5):
        try:
            with urllib.request.urlopen(URL.format(n=n, e=e), timeout=120) as r, open(target + '.part', 'wb') as f:
                while True:
                    block = r.read(1 << 20)
                    if not block:
                        break
                    f.write(block)
            os.replace(target + '.part', target)
            modified = r.headers.get('Last-Modified')
            if modified:
                with open(target + '.date', 'w') as f:
                    f.write(email.utils.parsedate_to_datetime(modified).strftime('%Y-%m-%d'))
            return target
        except urllib.error.HTTPError as ex:
            time.sleep(2 * (attempt + 1))
        except OSError:
            time.sleep(2 * (attempt + 1))
    raise RuntimeError('download of %s%s failed' % (n, e))


def main():
    south, west, north, east = (float(x) for x in sys.argv[1].split(','))
    output, work = sys.argv[2], sys.argv[3]
    AVAILABLE.update(load_tile_list())
    os.makedirs(output, exist_ok=True)
    source = os.path.join(work, 'cop')
    os.makedirs(source, exist_ok=True)
    lat0, lat1 = math.floor(south), math.ceil(north) - 1
    lon0, lon1 = math.floor(west), math.ceil(east) - 1
    targets = [(a, o) for a in range(lat0, lat1 + 1) for o in range(lon0, lon1 + 1)]
    candidates = [(a, o, source) for a in range(lat0 - 1, lat1 + 2) for o in range(lon0 - 1, lon1 + 2)]
    with ThreadPoolExecutor(8) as ex:
        tiffs = [t for t in ex.map(download, candidates) if t]
    print('Copernicus tiles', len(tiffs), 'of', len(candidates), flush=True)
    dates = []
    for t in tiffs:
        if os.path.exists(t + '.date'):
            with open(t + '.date') as f:
                dates.append(f.read().strip())
    if dates:
        with open(os.path.join(work, 'dem-date.txt'), 'w') as f:
            f.write(max(dates))
    vrt = os.path.join(work, 'cop.vrt')
    listing = os.path.join(work, 'cop.txt')
    with open(listing, 'w') as f:
        f.write('\n'.join(tiffs))
    subprocess.run(['gdalbuildvrt', '-q', '-input_file_list', listing, vrt], check=True)
    half = 0.5 / 3600
    written = 0
    for a, o in targets:
        n, e = tile_name(a, o)
        raw = os.path.join(work, 'tile.raw')
        subprocess.run(['gdalwarp', '-q', '-overwrite', '-te', str(o - half - PAD / 3600), str(a - half), str(o + 1 + half + PAD / 3600), str(a + 1 + half),
                        '-ts', str(3601 + 2 * PAD), '3601', '-r', 'cubicspline', '-ot', 'Float32', '-of', 'ENVI', vrt, raw], check=True)
        v = np.fromfile(raw, dtype='<f4').reshape(3601, 3601 + 2 * PAD)
        v = np.nan_to_num(v, nan=0.0)  # missing tiles are sea (height 0, as in SRTM)
        ratio = spacing(a)
        if ratio > 1:
            v = gaussian_filter1d(v, SIGMA * ratio, axis=1, mode='nearest')
        v = v[:, PAD:-PAD]
        if not (v > 0).any():
            continue
        np.rint(v).astype('>i2').tofile(os.path.join(output, n + e + '.hgt'))
        written += 1
        for p in (raw, raw + '.hdr', raw + '.aux.xml'):
            if os.path.exists(p):
                os.remove(p)
    print('HGT tiles', written, flush=True)


if __name__ == '__main__':
    main()
