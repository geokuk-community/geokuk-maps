#!/usr/bin/env python3
"""Prints the osmium tags-filter expressions for the points (n/), lines and areas (wa/) of mapping/tourist-features.xml.
Tags with renderable="false" are left out; they are kept only on objects selected by another tag."""
import os, sys
import xml.etree.ElementTree as ET

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
root = ET.parse(sys.argv[1] if len(sys.argv) > 1 else os.path.join(R, 'mapping', 'tourist-features.xml')).getroot()
for section in root:
    kind = {'pois': 'n', 'ways': 'wa'}[section.tag.split('}')[1]]
    values = {}
    for tag in section:
        if tag.get('renderable') == 'false':
            continue
        v = values.setdefault(tag.get('key'), [])
        v.append(tag.get('value'))
        v += [x for x in (tag.get('equivalent-values') or '').split(',') if x]
    for key, v in values.items():
        print('%s/%s=%s' % (kind, key, ','.join(dict.fromkeys(v))))
