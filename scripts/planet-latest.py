#!/usr/bin/env python3
"""Prints the name of the newest weekly OSM planet with an .md5 in the AWS Open Data bucket osm-planet-eu-central-1
(planet/pbf/YYYY/planet-YYMMDD.osm.pbf), or checks a given name. Usage: planet-latest.py [planet-YYMMDD]"""
import re, sys, urllib.request
from datetime import datetime, timezone

BUCKET = 'https://osm-planet-eu-central-1.s3.amazonaws.com/'


def keys(prefix):
    result, token = [], None
    while True:
        url = BUCKET + '?list-type=2&prefix=' + prefix + ('&continuation-token=' + urllib.request.quote(token) if token else '')
        with urllib.request.urlopen(url, timeout=60) as r:
            xml = r.read().decode('utf-8')
        result += re.findall(r'<Key>([^<]+)</Key>', xml)
        m = re.search(r'<NextContinuationToken>([^<]+)</NextContinuationToken>', xml)
        if not m:
            return result
        token = m.group(1)


def main():
    wanted = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
    if wanted and not re.fullmatch(r'planet-[0-9]{6}', wanted):
        sys.exit('Invalid planet name: ' + wanted)
    year = datetime.now(timezone.utc).year
    years = [2000 + int(wanted[7:9])] if wanted else [year, year - 1]
    for y in years:
        found = set(keys('planet/pbf/%d/' % y))
        names = sorted({k.split('/')[-1][:-8] for k in found if re.fullmatch(r'planet/pbf/%d/planet-[0-9]{6}\.osm\.pbf' % y, k)
                        and k + '.md5' in found}, reverse=True)
        if wanted:
            if wanted in names:
                print(wanted)
                return
            sys.exit('%s.osm.pbf with .md5 is not in the bucket' % wanted)
        if names:
            print(names[0])
            return
    sys.exit('No planet in the bucket')


if __name__ == '__main__':
    main()
