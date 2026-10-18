#!/usr/bin/env python3
"""ČÚZK DMR 4G (LAZ, S-JTSK, bare ground, open data CC BY 4.0) -> HGT 1" (3601x3601, big-endian int16) for an area.
Usage: cuzk2hgt.py south,west,north,east hgt_dir work_dir
The HGT tiles already in hgt_dir (Copernicus, see cop2hgt.py) are completed: wherever DMR 4G has data it replaces the value,
the rest (outside the Czech Republic, gaps) stays as it was.
Stage A: the sheets (SM5, about 2.7 x 2.3 km) are downloaded from the ČÚZK ATOM service one at a time per worker, averaged into
a 20 m grid in S-JTSK (a memory-mapped file) and dropped at once, so the disk holds only the grid.
Stage B: gdalwarp resamples the grid to the 1" tiles.
Requires numpy, laspy[lazrs] and GDAL (gdalwarp)."""
import io, math, os, re, subprocess, sys, time, urllib.request, zipfile
from multiprocessing import Pool
import numpy as np
import laspy

INDEX = 'https://atom.cuzk.gov.cz/DMR4G-SJTSK/DMR4G-SJTSK.xml'
SHEET = 'https://openzu.cuzk.gov.cz/opendata/DMR4G/epsg-5514/%s.zip'
HEADERS = {'User-Agent': 'GeoKuk-vrstvy/1.0 (+https://github.com/geokuk-community/geokuk-maps)'}
WORKERS = 4   # concurrent downloads (the terms of the service forbid overloading it)
PAUSE = 0.1   # seconds between two downloads of one worker
X0, Y0, CELL = -960000.0, -920000.0, 20.0  # upper left corner and cell size of the grid in S-JTSK
W, H = 27000, 16000
NODATA = -32768


def fetch(url):
    for attempt in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as r:
                return r.read()
        except OSError:
            time.sleep(2 * (attempt + 1))
    raise RuntimeError('download of %s failed' % url)


def sheets(south, west, north, east):
    text = fetch(INDEX).decode('utf-8-sig')
    found = []
    for entry in text.split('<entry>')[1:]:
        code = re.search(r'CUZK_DMR4G-SJTSK_([A-Z0-9]+)\.xml', entry)
        polygon = re.search(r'<georss:polygon>([^<]+)</georss:polygon>', entry)
        if not code or not polygon:
            continue
        v = [float(x) for x in polygon.group(1).split()]
        lats, lons = v[0::2], v[1::2]
        if max(lats) >= south and min(lats) <= north and max(lons) >= west and min(lons) <= east:
            found.append(code.group(1))
    return sorted(found)


def read_sheet(code):
    """Mean height of the points in 20 m cells: (first row, first column, array in metres with NaN for empty cells)."""
    data = fetch(SHEET % code)
    time.sleep(PAUSE)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        las = laspy.read(io.BytesIO(z.read(z.namelist()[0])))
    x, y, h = np.asarray(las.x), np.asarray(las.y), np.asarray(las.z)
    c = np.floor((x - X0) / CELL).astype(np.int64)
    r = np.floor((Y0 - y) / CELL).astype(np.int64)
    c0, r0 = c.min(), r.min()
    w, hh = c.max() - c0 + 1, r.max() - r0 + 1
    i = (r - r0) * w + (c - c0)
    total = np.bincount(i, weights=h, minlength=w * hh)
    count = np.bincount(i, minlength=w * hh)
    mean = np.where(count > 0, total / np.maximum(count, 1), np.nan).reshape(hh, w)
    return int(r0), int(c0), mean.astype(np.float32), len(data)


def safe_read(code):
    try:
        return code, read_sheet(code)
    except Exception as ex:
        return code, str(ex)


def stage_a(codes, grid):
    mm = np.memmap(grid, dtype='<i2', mode='w+', shape=(H, W))
    mm[:] = NODATA
    errors, size, start = 0, 0, time.time()
    with Pool(WORKERS) as pool:
        for k, (code, res) in enumerate(pool.imap_unordered(safe_read, codes, chunksize=4), 1):
            if isinstance(res, str):
                errors += 1
                print('ERROR', code, res, flush=True)
                continue
            r0, c0, m, n = res
            size += n
            block = mm[r0:r0 + m.shape[0], c0:c0 + m.shape[1]]
            ok = ~np.isnan(m)
            block[ok] = np.rint(m[ok] * 10).astype('<i2')  # decimetres, to fit the whole country in 16 bits
            if k % 500 == 0:
                print('%d/%d sheets, %.0f MB, %.0f s' % (k, len(codes), size / 1e6, time.time() - start), flush=True)
    mm.flush()
    print('Stage A: %d sheets, %.0f MB downloaded, %d errors, %.0f s' % (len(codes), size / 1e6, errors, time.time() - start), flush=True)
    if errors > len(codes) * 0.001:
        sys.exit('Too many sheets failed')


def stage_b(south, west, north, east, hgt_dir, work, grid):
    vrt = os.path.join(work, 'sjtsk20m.vrt')
    with open(vrt, 'w') as f:
        f.write('''<VRTDataset rasterXSize="%d" rasterYSize="%d"><SRS>EPSG:5514</SRS><GeoTransform>%r, %r, 0, %r, 0, %r</GeoTransform>
<VRTRasterBand dataType="Int16" band="1" subClass="VRTRawRasterBand"><NoDataValue>%d</NoDataValue>
<SourceFilename relativeToVRT="0">%s</SourceFilename><ImageOffset>0</ImageOffset><PixelOffset>2</PixelOffset><LineOffset>%d</LineOffset>
<ByteOrder>LSB</ByteOrder></VRTRasterBand></VRTDataset>''' % (W, H, X0, CELL, Y0, -CELL, NODATA, grid, 2 * W))
    half = 0.5 / 3600
    replaced = 0
    for a in range(math.floor(south), math.ceil(north)):
        for o in range(math.floor(west), math.ceil(east)):
            name = '%s%02d%s%03d.hgt' % ('N' if a >= 0 else 'S', abs(a), 'E' if o >= 0 else 'W', abs(o))
            raw = os.path.join(work, 'tile.raw')
            subprocess.run(['gdalwarp', '-q', '-overwrite', '-s_srs', 'EPSG:5514', '-t_srs', 'EPSG:4326',
                            '-te', str(o - half), str(a - half), str(o + 1 + half), str(a + 1 + half), '-ts', '3601', '3601',
                            '-r', 'bilinear', '-srcnodata', str(NODATA), '-dstnodata', str(NODATA), '-ot', 'Int16', '-of', 'ENVI', vrt, raw],
                           check=True)
            dmr = np.fromfile(raw, dtype='<i2').reshape(3601, 3601)
            for p in (raw, raw + '.hdr', raw + '.aux.xml'):
                if os.path.exists(p):
                    os.remove(p)
            valid = dmr != NODATA
            if not valid.any():
                continue
            path = os.path.join(hgt_dir, name)
            tile = np.fromfile(path, dtype='>i2').reshape(3601, 3601).astype(np.float32) if os.path.exists(path) \
                else np.zeros((3601, 3601), np.float32)
            tile[valid] = dmr[valid] / 10.0
            np.rint(tile).astype('>i2').tofile(path)
            replaced += 1
            print('%s: %.1f %% from DMR 4G' % (name, 100.0 * valid.mean()), flush=True)
    print('Stage B: %d tiles completed' % replaced, flush=True)


def main():
    south, west, north, east = (float(x) for x in sys.argv[1].split(','))
    hgt_dir, work = sys.argv[2], sys.argv[3]
    os.makedirs(work, exist_ok=True)
    codes = sheets(south, west, north, east)
    print('DMR 4G sheets in the area:', len(codes), flush=True)
    grid = os.path.join(work, 'sjtsk20m.i16')
    stage_a(codes, grid)
    stage_b(south, west, north, east, hgt_dir, work, grid)
    os.remove(grid)


if __name__ == '__main__':
    main()
