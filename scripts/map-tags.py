#!/usr/bin/env python3
"""Prints the tags (key=value) listed in the header of a mapsforge .map file, as "poi key=value" and "way key=value" lines.
Usage: map-tags.py file.map  (the first megabyte is enough)"""
import struct, sys


def main():
    with open(sys.argv[1], 'rb') as f:
        data = f.read(1 << 20)
    if data[:20] != b'mapsforge binary OSM':
        sys.exit('Not a mapsforge map file')
    pos = 24 + 4 + 8 + 8 + 16 + 2

    def vbe():
        nonlocal pos
        value, shift = 0, 0
        while True:
            b = data[pos]
            pos += 1
            value |= (b & 0x7f) << shift
            shift += 7
            if not b & 0x80:
                return value

    def string():
        nonlocal pos
        n = vbe()
        pos += n
        return data[pos - n:pos].decode('utf-8')

    string()  # projection
    flags = data[pos]
    pos += 1
    if flags & 0x40:
        pos += 8
    if flags & 0x20:
        pos += 1
    for bit in (0x10, 0x08, 0x04):
        if flags & bit:
            string()
    for kind in ('poi', 'way'):
        count = struct.unpack('>H', data[pos:pos + 2])[0]
        pos += 2
        for _ in range(count):
            print(kind, string())


if __name__ == '__main__':
    main()
