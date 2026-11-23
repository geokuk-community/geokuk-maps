#!/usr/bin/env bash
# Pull request checks of the themes and the catalogue with fixtures (no download): scripts/theme-check.py, scripts/theme-catalog.py,
# scripts/merge-catalog.py and the catalogue rules of GeoKuk 6.5.0 (scripts/finalize-check.py compat).
# Fixtures: geokuk/ and paws/ (render themes shaped like GeoKuk-tema.zip and GeoKuk-tema-PAWS.zip), tags.txt (tags of the headers of the
# Czech tourist and contours maps of layers-2026-10f/10e), layers.json (layers of that release for the Czech Republic and Monaco).
set -euo pipefail
T=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$T/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
# expect_fail "text that the error must contain" command...
expect_fail() {
  local want=$1; shift
  if "$@" > "$work/out.txt" 2>&1; then cat "$work/out.txt"; fail "expected an error: $*"; fi
  grep -qF "$want" "$work/out.txt" || { cat "$work/out.txt"; fail "the error does not say '$want': $*"; }
  echo "ok (fails as expected): $want"
}
zipdir() { (cd "$1" && rm -f "$2" && zip -qr -X "$2" .); }
mkdir -p "$work/themes"
zipdir "$T/geokuk" "$work/themes/GeoKuk-tema.zip"
zipdir "$T/paws" "$work/themes/GeoKuk-tema-PAWS.zip"
check() { python3 "$R/scripts/theme-check.py" "$@"; }

# The theme matches the tag mapping and the headers; rules on the base map (highway, natural=peak) are left out.
check geokuk "$work/themes/GeoKuk-tema.zip"
check geokuk "$work/themes/GeoKuk-tema.zip" --tags "$T/tags.txt" --notice | tee "$work/out.txt"
grep -q 'not used by the theme' "$work/out.txt" || fail "no notice about unused tags"
check paws "$work/themes/GeoKuk-tema-PAWS.zip"

# A tag of the layers that the tag mapping does not have.
cp -r "$T/geokuk" "$work/bad1"
sed -i 's/v="major|local|learning"/v="major|local|learning|purple"/' "$work/bad1/GeoKuk.xml"
zipdir "$work/bad1" "$work/bad1.zip"
expect_fail 'fmrelhikingred=purple (way): not in mapping' check geokuk "$work/bad1.zip"
# A key that only the layers would have.
sed -i 's/k="fmrelhikingblue|fmrelhikinggreen"/k="fmrelhikingblue|fmrelhikingpurple"/' "$work/bad1/GeoKuk.xml"
zipdir "$work/bad1" "$work/bad1.zip"
expect_fail 'fmrelhikingpurple=major (way): not in mapping' check geokuk "$work/bad1.zip"
# In the tag mapping, but in no header (the data of the release do not have it).
grep -v 'contour_ext=elevation_medium' "$T/tags.txt" > "$work/tags.txt"
expect_fail 'contour_ext=elevation_medium (way): in the tag mapping, but in no header' check geokuk "$work/themes/GeoKuk-tema.zip" --tags "$work/tags.txt"
# A symbol that is not in the ZIP, and a ZIP without a render theme.
cp -r "$T/paws" "$work/bad2"
rm "$work/bad2/icons/guidepost.svg"
zipdir "$work/bad2" "$work/bad2.zip"
expect_fail 'refers to file:icons/guidepost.svg, which is not in the ZIP' check paws "$work/bad2.zip"
rm "$work/bad2/GeoKuk-PAWS.xml"
zipdir "$work/bad2" "$work/bad2.zip"
expect_fail 'no render theme' check paws "$work/bad2.zip"

# Catalogue: the themes are added next to the layers, version stays 1, the layers keep the rules of GeoKuk 6.5.0.
cp "$T/layers.json" "$work/layers.json"
expect_fail 'theme/geokuk: theme with the file GeoKuk-tema.zip missing' python3 "$R/scripts/finalize-check.py" compat "$work/layers.json"
printf '{"geokuk": "v6.5.0", "geokukVersion": "6.5.0", "date": "2026-12-01", "source": "https://github.com/geokuk-community/geokuk/releases/tag/v6.5.0"}\n' \
  > "$work/themes/themes.meta.json"
python3 "$R/scripts/theme-catalog.py" "$work/layers.json" "$work/themes" layers-2026-12
python3 "$R/scripts/finalize-check.py" compat "$work/layers.json"
python3 -I - "$T/layers.json" "$work/layers.json" <<'PY'
import json, sys
old, new = (json.load(open(p, encoding='utf-8')) for p in sys.argv[1:3])
assert new['version'] == 1 and new['layers'] == old['layers'] and new['sources'] == old['sources'], 'layers changed'
assert list(new)[-1] == 'themes' and [t['id'] for t in new['themes']] == ['theme/geokuk'], new.get('themes')
g = new['themes'][0]
assert g['files'][0]['url'] == 'layers-2026-12/GeoKuk-tema.zip' and g['layers'] == ['tourist', 'contours'] and g['geokukVersion'] == '6.5.0'
print('ok: theme/geokuk added (GeoKuk-tema-PAWS.zip not in the catalogue), layers unchanged')
PY
# merge-catalog keeps the themes of the release when a region is merged in.
python3 -I - "$work/layers.json" "$work/frag.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1], encoding='utf-8'))
json.dump({'version': 1, 'generated': c['generated'], 'sources': c['sources'], 'layers': [c['layers'][0]]}, open(sys.argv[2], 'w'))
PY
python3 "$R/scripts/merge-catalog.py" "$work/layers.json" "$work/frag.json" "$work/merged.json"
python3 "$R/scripts/finalize-check.py" compat "$work/merged.json"
# What GeoKuk 6.5.0 refuses: another version, a duplicate file path, a layer without files.
for case in version dup files; do
  python3 -I - "$work/layers.json" "$work/bad.json" "$case" <<'PY'
import json, sys
c = json.load(open(sys.argv[1], encoding='utf-8'))
case = sys.argv[3]
known = [x for x in c['layers'] if x['type'] in ('tourist', 'contours')]
if case == 'version':
    c['version'] = 2
elif case == 'dup':
    known[1]['files'][0]['path'] = known[0]['files'][0]['path']
else:
    known[0]['files'] = []
json.dump(c, open(sys.argv[2], 'w'))
PY
  want=$(case $case in version) echo 'version must be the integer 1';; dup) echo 'is not unique';; files) echo 'files missing';; esac)
  expect_fail "$want" python3 "$R/scripts/finalize-check.py" compat "$work/bad.json"
done
# A theme of osm.paws.cz in the catalogue is refused (GeoKuk-tema-PAWS.zip is a release asset only).
python3 -I - "$work/layers.json" "$work/bad.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1], encoding='utf-8'))
paws = json.loads(json.dumps(c['themes'][0]))
paws.update(id='theme/geokuk-paws', name='GeoKuk (osm.paws.cz)', **{'for': 'osm.paws.cz'})
paws['files'][0].update(name='GeoKuk-tema-PAWS.zip', url='layers-2026-12/GeoKuk-tema-PAWS.zip')
c['themes'].append(paws)
json.dump(c, open(sys.argv[2], 'w'))
PY
expect_fail 'theme/geokuk-paws: theme not expected in layers.json' python3 "$R/scripts/finalize-check.py" compat "$work/bad.json"
# verify: both ZIPs with their .sha256 are required assets; the PAWS ZIP is not an unreferenced asset.
python3 -I - "$work/layers.json" "$work/assets.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1], encoding='utf-8'))
assets, i = [], 1
for x in c['layers'] + c['themes']:
    for f in x['files']:
        tag, name = f['url'].split('/')
        if tag == 'layers-2026-12':
            assets.append({'id': i, 'name': name, 'state': 'uploaded', 'size': f['size'], 'digest': 'sha256:' + f['sha256']})
            i += 1
for name in ('GeoKuk-tema.zip.sha256', 'GeoKuk-tema-PAWS.zip', 'GeoKuk-tema-PAWS.zip.sha256', 'layers.json', 'LICENSES.txt'):
    assets.append({'id': i, 'name': name, 'state': 'uploaded', 'size': 1})
    i += 1
json.dump(assets, open(sys.argv[2], 'w'))
PY
ALLOW_NO_DIGEST=1 python3 "$R/scripts/finalize-check.py" verify "$work/layers.json" "$work/assets.json" layers-2026-12 | tee "$work/out.txt"
! grep -q 'not referenced' "$work/out.txt" || fail "a theme asset is reported as unreferenced"
python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1])); json.dump([x for x in a if x["name"] != "GeoKuk-tema-PAWS.zip.sha256"], open(sys.argv[1], "w"))' "$work/assets.json"
expect_fail 'theme asset GeoKuk-tema-PAWS.zip.sha256 missing' python3 "$R/scripts/finalize-check.py" verify "$work/layers.json" "$work/assets.json" layers-2026-12
echo "All theme and catalogue checks passed"
