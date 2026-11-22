#!/usr/bin/env python3
"""Checks the GeoKuk themes (render themes in a ZIP) against the layers.
  geokuk theme.zip [--tags tags.txt] [--notice]
      The rules of the theme whose tags belong to the layers must find those tags in the layers: a key=value of mapping/tourist.xml or
      mapping/contours.xml, or a key that only the layers have (fmrel*, contour_ext). With --tags (lines "poi key=value" / "way key=value"
      from scripts/map-tags.py over the headers of every tourist and contours .map of a release) the tag must also be in those headers:
      the map writer lists only the tags that occur in the data, so the headers of all regions are joined. --notice lists the tags of the
      layers that the theme does not use. Every src="file:..." must be a file in the ZIP.
  paws theme.zip
      Only that the ZIP holds a render theme that parses and that every src="file:..." is a file in the ZIP.
Exit code 1 with the list of problems."""
import argparse, os, posixpath, re, sys, zipfile
import xml.etree.ElementTree as ET

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPPINGS = ('tourist.xml', 'contours.xml')
# Keys that only the layers write; the other keys of the mappings (natural, highway...) are also in the mapsforge base maps,
# so a value of theirs that the layers do not have is left to the base map.
LAYER_ONLY = re.compile(r'fmrel.*|contour_ext')
KINDS = {'node': ('poi',), 'way': ('way',), 'any': ('poi', 'way')}


def local(tag):
    return tag.rsplit('}', 1)[-1]


def mapping_tags():
    tags = set()
    for name in MAPPINGS:
        root = ET.parse(os.path.join(R, 'mapping', name)).getroot()
        for section, kind in (('pois', 'poi'), ('ways', 'way')):
            for group in root:
                if local(group.tag) != section:
                    continue
                for t in group.iter():
                    if local(t.tag) == 'osm-tag':
                        tags.add((kind, t.get('key'), t.get('value')))
    return tags


def read_themes(path):
    """[(name in the ZIP, root element)] of the render themes, and the problems."""
    problems, themes = [], []
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        for name in sorted(names):
            if not name.lower().endswith('.xml') or name.startswith('__MACOSX/'):
                continue
            try:
                root = ET.fromstring(z.read(name))
            except ET.ParseError as e:
                problems.append('%s: %s does not parse: %s' % (path, name, e))
                continue
            if local(root.tag) == 'rendertheme':
                themes.append((name, root))
        if not themes and not problems:
            problems.append('%s: no render theme (XML with <rendertheme>) in the ZIP' % path)
        for name, root in themes:
            base = posixpath.dirname(name)
            for e in root.iter():
                for attr, value in e.attrib.items():
                    if local(attr).endswith('src') and value.startswith('file:'):
                        target = posixpath.normpath(posixpath.join(base, value[5:].lstrip('/')))
                        if target not in names:
                            problems.append('%s: %s refers to %s, which is not in the ZIP' % (path, name, value))
    return themes, problems


def theme_tags(themes):
    """{(kind, key, value or '*')} used by the rules; '~' (tag absent) is left out."""
    used = set()
    for _, root in themes:
        for e in root.iter():
            if local(e.tag) != 'rule':
                continue
            kinds = KINDS.get(e.get('e', 'any'), ('poi', 'way'))
            for k in (e.get('k') or '').split('|'):
                for v in (e.get('v') or '').split('|'):
                    if k and v and k != '*' and v != '~':
                        for kind in kinds:
                            used.add((kind, k, v))
    return used


def check_geokuk(path, tags_file, notice):
    themes, problems = read_themes(path)
    mapping = mapping_tags()
    layer_keys = {(kind, k) for kind, k, _ in mapping}
    present = None
    if tags_file:
        present = set()
        with open(tags_file, encoding='utf-8') as f:
            for line in f:
                kind, _, kv = line.strip().partition(' ')
                k, sep, v = kv.partition('=')
                if sep:
                    present.add((kind, k, v))
    used = theme_tags(themes)
    # A rule with e="any" is fine when the tag is in the layers as a poi or as a way.
    wanted = {}
    for kind, k, v in used:
        layer_only = bool(LAYER_ONLY.fullmatch(k))
        if v == '*':
            if layer_only:
                wanted.setdefault((k, None), set()).add(kind)
        elif layer_only or (kind, k, v) in mapping:
            wanted.setdefault((k, v), set()).add(kind)
    missing, checked = [], 0
    for (k, v), kinds in sorted(wanted.items(), key=lambda x: (x[0][0], x[0][1] or '')):
        checked += 1
        if v is None:
            ok_mapping = any((kind, k) in layer_keys for kind in kinds)
            ok_maps = present is None or any(p[0] in kinds and p[1] == k for p in present)
            label = '%s=*' % k
        else:
            ok_mapping = any((kind, k, v) in mapping for kind in kinds)
            ok_maps = present is None or any((kind, k, v) in present for kind in kinds)
            label = '%s=%s' % (k, v)
        if not ok_mapping:
            missing.append('%s (%s): not in mapping/tourist.xml or mapping/contours.xml' % (label, '/'.join(sorted(kinds))))
        elif not ok_maps:
            missing.append('%s (%s): in the tag mapping, but in no header of the tourist and contours maps' % (label, '/'.join(sorted(kinds))))
    print('%s: %d render theme(s), %d tags in rules, %d of them belong to the layers' % (path, len(themes), len(used), checked))
    if notice and present is not None:
        unused = sorted('%s %s=%s' % p for p in present if not any((p[0], p[1], v) in used for v in (p[2], '*')))
        print('::notice::%d tags of the layers are not used by the theme: %s' % (len(unused), ', '.join(unused[:200])))
    problems += ['%s: tag missing in the layers: %s' % (path, m) for m in missing]
    return problems


def main():
    p = argparse.ArgumentParser()
    p.add_argument('kind', choices=['geokuk', 'paws'])
    p.add_argument('zip')
    p.add_argument('--tags')
    p.add_argument('--notice', action='store_true')
    a = p.parse_args()
    if a.kind == 'geokuk':
        problems = check_geokuk(a.zip, a.tags, a.notice)
    else:
        themes, problems = read_themes(a.zip)
        print('%s: %d render theme(s)' % (a.zip, len(themes)))
    if problems:
        sys.exit('\n'.join(problems[:200]) + '\n%d problem(s)' % len(problems))
    print('%s: OK' % a.zip)


if __name__ == '__main__':
    main()
