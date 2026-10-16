#!/usr/bin/env bash
# Checks that FROM_RUN (a run id) is a trusted source of artifacts: a workflow_dispatch run of layers.yml in this repository.
# For MODE=release the run must also be on main.
# Env: GH_TOKEN, GITHUB_REPOSITORY, FROM_RUN, MODE.
set -euo pipefail
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${MODE:?}"
FROM_RUN=${FROM_RUN:-}
[ -z "$FROM_RUN" ] && exit 0
[[ "$FROM_RUN" =~ ^[0-9]+$ ]] || { echo "from_run must be a run id" >&2; exit 1; }
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$FROM_RUN" > run.json
python3 - "$MODE" "$GITHUB_REPOSITORY" <<'PY'
import json, sys
mode, repo = sys.argv[1:3]
r = json.load(open('run.json'))
problems = []
if r.get('path') != '.github/workflows/layers.yml':
    problems.append('run is not a Layers workflow run')
if r.get('event') != 'workflow_dispatch':
    problems.append('run was triggered by %s, not workflow_dispatch' % r.get('event'))
if (r.get('head_repository') or {}).get('full_name') != repo:
    problems.append('run comes from another repository')
if mode == 'release' and r.get('head_branch') != 'main':
    problems.append('a release can only be published from a run on main (run is on %s)' % r.get('head_branch'))
if problems:
    sys.exit('Run %s is not accepted: %s' % (r.get('id'), '; '.join(problems)))
print('Run %s accepted (branch %s, %s)' % (r['id'], r.get('head_branch'), r.get('head_sha', '')[:7]))
PY
