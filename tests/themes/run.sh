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

# Rules for tags of the layer family that the layers never write (as GeoKuk-tema.zip of v6.5.0-beta.36: fmrelbicyclebrown/orange/purple,
# fmrelmtb...; addfmreltags.pl writes other colours as ...default): warnings, the check passes, also against the headers.
cp -r "$T/geokuk" "$work/dead"
sed -i 's|</rendertheme>|	<rule e="way" k="fmrelbicyclebrown\|fmrelbicycleorange\|fmrelmtbpurple" v="*">\n		<line stroke="#a05000" stroke-width="1" />\n	</rule>\n</rendertheme>|' "$work/dead/GeoKuk.xml"
sed -i 's/v="major|local|learning"/v="major|local|learning|purple"/' "$work/dead/GeoKuk.xml"
zipdir "$work/dead" "$work/dead.zip"
check geokuk "$work/dead.zip" --tags "$T/tags.txt" | tee "$work/out.txt"
for w in 'fmrelbicyclebrown=* (way)' 'fmrelbicycleorange=* (way)' 'fmrelmtbpurple=* (way)' 'fmrelhikingred=purple (way)'; do
  grep -qF "::warning::pravidlo tématu, které vrstva nevytváří (nekreslí se): $w" "$work/out.txt" || fail "no warning for $w"
done
# Only tags of the layer family get this warning; rules for the base map (highway, natural=peak in the fixture) are left out.
if grep 'pravidlo tématu' "$work/out.txt" | grep -vqE ': (fmrel|contour_ext)'; then
  fail "a theme rule outside fmrel*/contour_ext is reported as a rule that the layers never write"
fi
echo "ok: rules that the layers never draw are warnings"
# A tag of the mapping that the theme draws but no header has (the release lacks it) stays an error, next to the warnings.
grep -v 'contour_ext=elevation_medium' "$T/tags.txt" > "$work/tags.txt"
expect_fail 'contour_ext=elevation_medium (way): in the tag mapping, but in no header' check geokuk "$work/themes/GeoKuk-tema.zip" --tags "$work/tags.txt"
expect_fail 'contour_ext=elevation_medium (way): in the tag mapping, but in no header' check geokuk "$work/dead.zip" --tags "$work/tags.txt"
grep -q 'pravidlo tématu.*fmrelbicyclebrown' "$work/out.txt" || fail "no warning for fmrelbicyclebrown next to the error"
if grep -q 'tag missing in the layers: fmrelbicyclebrown' "$work/out.txt"; then fail "a rule that draws nothing is reported as an error"; fi
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
# publish.sh with the themes only, on a draft release made before the themes (layers.json without "themes"), as themes.yml does
# for layers-2026-11: both ZIPs and their .sha256 are uploaded, layers.json gets theme/geokuk only and keeps its layers.
mkdir -p "$work/stub/assets" "$work/upload/themes"
cp "$T/layers.json" "$work/stub/assets/layers.json"
echo licence > "$work/stub/assets/LICENSES.txt"
cp "$work/themes/GeoKuk-tema.zip" "$work/themes/GeoKuk-tema-PAWS.zip" "$work/upload/themes/"
(cd "$work/upload/themes" && for z in GeoKuk-tema.zip GeoKuk-tema-PAWS.zip; do sha256sum "$z" > "$z.sha256"; done)
printf '{"geokuk": "v6.5.0-beta.36", "geokukVersion": "6.5.0-beta.36", "date": "2026-11-23", "source": "https://github.com/geokuk-community/geokuk/releases/tag/v6.5.0-beta.36"}\n' \
  > "$work/upload/themes/themes.meta.json"
PATH="$T/stub:$PATH" STATE="$work/stub" GH_TOKEN=x GITHUB_REPOSITORY=o/r MODE=draft TAG=layers-2026-11 DIR="$work/upload" \
  bash "$R/scripts/publish.sh"
for name in GeoKuk-tema.zip GeoKuk-tema.zip.sha256 GeoKuk-tema-PAWS.zip GeoKuk-tema-PAWS.zip.sha256 layers.json; do
  [ -s "$work/stub/assets/$name" ] || fail "publish.sh did not upload $name"
done
python3 "$R/scripts/finalize-check.py" compat "$work/stub/assets/layers.json"
python3 -I - "$T/layers.json" "$work/stub/assets/layers.json" <<'PY'
import json, sys
old, new = (json.load(open(p, encoding='utf-8')) for p in sys.argv[1:3])
assert new['layers'] == old['layers'] and new['sources'] == old['sources'] and new['version'] == 1, 'the draft layers changed'
assert [(t['id'], t['files'][0]['url']) for t in new['themes']] == [('theme/geokuk', 'layers-2026-11/GeoKuk-tema.zip')], new['themes']
print('ok: themes added to the draft, its layers unchanged')
PY
# A layer of the previous release that is missing in the new layers.json fails, unless mapping/removed-layers.txt lists it.
python3 "$R/scripts/finalize-check.py" compare "$T/layers.json" "$T/layers.json"
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); c["layers"]=[x for x in c["layers"] if x["id"] != "tourist/europe/monaco"]; json.dump(c, open(sys.argv[2], "w"))' \
  "$T/layers.json" "$work/fewer.json"
expect_fail '1 layer(s) of the previous release are missing (omitted at 2 GiB, a failed build, or removed: then list them in mapping/removed-layers.txt): tourist/europe/monaco' \
  python3 "$R/scripts/finalize-check.py" compare "$work/fewer.json" "$T/layers.json"
printf '# test\ntourist/europe/monaco\n' > "$work/removed.txt"
REMOVED_LAYERS="$work/removed.txt" python3 "$R/scripts/finalize-check.py" compare "$work/fewer.json" "$T/layers.json"
# The previous release is the newest published layers-* older than the draft; drafts and other tags do not count.
printf '[{"id": 1, "tag_name": "layers-2026-11", "draft": false}, {"id": 2, "tag_name": "layers-2026-10f", "draft": false}, {"id": 3, "tag_name": "layers-2026-11-split", "draft": true}, {"id": 4, "tag_name": "layers-2026-12", "draft": true}, {"id": 5, "tag_name": "v1", "draft": false}]\n' > "$work/releases.json"
[ "$(python3 "$R/scripts/finalize-check.py" previous "$work/releases.json" layers-2026-12)" = "1 layers-2026-11" ] || fail "wrong previous release"
[ -z "$(python3 "$R/scripts/finalize-check.py" previous "$work/releases.json" layers-2026-10)" ] || fail "a previous release before the first one"
# omit-large.py warns about a file of at least 1.6 GiB and keeps its layer; at 2 GiB the layer is omitted.
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); c["layers"][0]["files"][0]["size"]=int(1.7*1024**3); c["layers"][1]["files"][0]["size"]=2*1024**3; json.dump(c, open(sys.argv[2], "w"))' \
  "$T/layers.json" "$work/large.json"
python3 "$R/scripts/omit-large.py" "$work/large.json" > "$work/out.txt"
grep -q '::warning::.*1.70 GiB, close to the 2 GiB limit' "$work/out.txt" || { cat "$work/out.txt"; fail "no warning at 1.7 GiB"; }
grep -q '::warning::omitted: .*2.00 GiB' "$work/out.txt" || { cat "$work/out.txt"; fail "a 2 GiB layer is not omitted"; }
echo "ok: previous release, missing layers and large files"

# finalize.sh end to end (DRY_RUN=1) against stubs of gh and curl: draft layers-2026-12 with the layers of the fixture (in older
# releases) and theme/geokuk, previous release layers-2026-11. It must pass, and fail when a layer of layers-2026-11 is missing
# in the draft; that also shows that finalize.sh runs the comparison. layers-2026-11-split (a test tag) is never the previous release.
mkdir -p "$work/fin/themes"
cp "$work/themes/GeoKuk-tema.zip" "$work/themes/GeoKuk-tema-PAWS.zip" "$work/fin/themes/"
(cd "$work/fin/themes" && for z in GeoKuk-tema.zip GeoKuk-tema-PAWS.zip; do sha256sum "$z" > "$z.sha256"; done)
cp "$work/themes/themes.meta.json" "$work/fin/themes/"
cp "$T/layers.json" "$work/fin/draft.json"
python3 "$R/scripts/theme-catalog.py" "$work/fin/draft.json" "$work/fin/themes" layers-2026-12 > /dev/null
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); json.dump({"regions": {l["region"]: {"dem": "layers-2026-10e", "contours": "layers-2026-10e"} for l in c["layers"] if l["type"] == "dem"}}, open(sys.argv[2], "w"))' \
  "$T/layers.json" "$work/fin/manifest.json"
finalize() { # $1 = previous layers.json
  rm -rf "$work/fin/state"
  python3 "$T/finalize-state.py" "$work/fin/state" "$work/fin/draft.json" "$work/fin/themes" "$1" "$T/tags.txt"
  PATH="$T/stub-finalize:$PATH" STATE="$work/fin/state" DEM_MANIFEST="$work/fin/manifest.json" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
    TAG=layers-2026-12 DRY_RUN=1 bash "$R/scripts/finalize.sh"
}
finalize "$T/layers.json" > "$work/out.txt" 2>&1 || { cat "$work/out.txt"; fail "finalize.sh failed on a complete draft"; }
grep -q 'Previous release layers-2026-11$' "$work/out.txt" || { cat "$work/out.txt"; fail "finalize.sh did not compare with layers-2026-11"; }
grep -q 'Dry run: all checks passed' "$work/out.txt" || { cat "$work/out.txt"; fail "finalize.sh did not finish its checks"; }
[ ! -e "$work/fin/state/patched" ] || fail "finalize.sh published in a dry run"
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); c["layers"].append(dict(c["layers"][0], id="tourist/europe/andorra")); json.dump(c, open(sys.argv[2], "w"))' \
  "$T/layers.json" "$work/fin/previous-more.json"
expect_fail '1 layer(s) of the previous release are missing (omitted at 2 GiB, a failed build, or removed: then list them in mapping/removed-layers.txt): tourist/europe/andorra' \
  finalize "$work/fin/previous-more.json"
echo "ok: finalize.sh compares the draft with the previous release"
echo "All theme and catalogue checks passed"
