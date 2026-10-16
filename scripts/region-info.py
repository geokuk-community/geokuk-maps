#!/usr/bin/env python3
"""Prints the bounding box (south,west,north,east) of a Geofabrik .poly file.
Usage: region-info.py file.poly"""
import re, sys

lats, lons = [], []
with open(sys.argv[1], encoding='utf-8') as f:
    for line in f:
        m = re.match(r'\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s*$', line)
        if m:
            lons.append(float(m.group(1)))
            lats.append(float(m.group(2)))
if not lats:
    sys.exit('No coordinates in ' + sys.argv[1])
print('%.4f,%.4f,%.4f,%.4f' % (min(lats), min(lons), max(lats), max(lons)))
