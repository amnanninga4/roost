#!/usr/bin/env bash
# Writes docs/STATUS.md: the plain-language answer to "what is going on with Roost".
#
# This exists because a PR number is not information. Wes has no way to look up "#61", so a status
# update that says "#61 is green" tells him nothing. Everything here is pulled live — open PRs from
# GitHub, the running build from the server's own /health, the phones from devicectl — so it cannot
# drift the way a hand-written list does. Regenerate it, do not edit it.
#
# It lives in docs/ with RELEASE.md and FIRST-USE-TEST.md — the folder you go to when you want to
# know something, rather than loose at the repo root or off in ~/claude-reports with the dated
# one-off deliverables. Stable filename, and committed, so it
# is also readable on GitHub from a phone. The generated-at stamp at the top is how you know it is
# fresh; regenerate before trusting it.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
OUT="$PWD/docs/STATUS.md"

health=$(curl -fsS --max-time 10 https://roost.hinescreative.xyz/health 2>/dev/null || echo '{}')
field() { printf '%s' "$health" | python3 -c "import json,sys;print(json.load(sys.stdin).get('$1','?'))" 2>/dev/null || echo '?'; }

{
  echo "# Roost — what's going on"
  echo
  echo "_Generated $(date '+%A %B %-d, %Y at %-I:%M %p %Z'). Regenerate with \`scripts/status-report.sh\`._"
  echo
  echo "## Running right now"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Server build | \`$(field rev | cut -c1-7)\` |"
  echo "| Latest code on main | \`$(git rev-parse --short origin/main 2>/dev/null)\` |"
  echo "| Chores loaded | $(field choresSeeded), list version $(field choresVersion) |"
  echo "| Phones paired | $(field devices) |"
  echo "| Push notifications | $(field push) |"
  echo "| Last morning digest | $(field digestLastSent) |"
  backup_ok=$(printf '%s' "$health" | python3 -c "import json,sys;b=json.load(sys.stdin).get('backup') or {};print(('ok' if b.get('ok') else 'FAILING')+' — '+str(b.get('at','?'))[:16].replace('T',' ')+' UTC')" 2>/dev/null || echo '?')
  echo "| Last backup | $backup_ok |"
  echo
  echo "## Waiting on you"
  echo
  echo "Only things Fable cannot decide or do. Carrying the \`needs-wes\` label is what puts"
  echo "something here — if it is not labelled, it is not yours, and it should not be on your plate."
  echo
  if ! gh pr list --state open --label needs-wes --json number,title \
      --jq '.[] | "- **\(.title)**  [#\(.number)](https://github.com/amnanninga4/roost/pull/\(.number))"' 2>/dev/null | grep .; then
    echo "- Nothing in the code needs you."
  fi
  echo
  echo "Things only you can do, that are not code, live in the *Blocked on Wes* table of"
  echo "\`OPEN-ITEMS.md\`. Today that is the APNs key, Anne's phone, and a Tailscale key."
  echo
  echo "## Fable is handling these"
  echo
  echo "Here so you can see them, not so you can do them. No action needed."
  echo
  if ! gh pr list --state open --json number,title,labels \
      --jq '.[] | select([.labels[].name] | index("needs-wes") | not) | "- \(.title)  [#\(.number)](https://github.com/amnanninga4/roost/pull/\(.number))"' 2>/dev/null | grep .; then
    echo "- Nothing open."
  fi
  echo
  echo "## Waiting on Anne"
  echo
  echo "Three questions have been open on the kickoff thread since 09-13, re-asked twice."
  echo "The chore list is not final until they land:"
  echo
  echo "1. Garbage split, third location — basement/bathroom/kitchen, or basement/bedroom/bathroom?"
  echo "2. Which months does mowing run? April through October was proposed."
  echo "3. \"Trim Wes's hair\" is written as every two months, pinned to Anne. Right person, right rhythm?"
  echo
  gh issue list --state open --label needs-anne --json number,title \
    --jq '.[] | "Thread: **\(.title)**  [#\(.number)](https://github.com/amnanninga4/roost/issues/\(.number))"' 2>/dev/null \
    || echo "(could not read issues)"
  echo
  echo "## The phones"
  echo
  xcrun devicectl list devices 2>/dev/null | awk 'NR>2 && $0 ~ /physical/ {print "- " $0}' || echo "- none attached"
  echo
  echo "## Open items, counted"
  echo
  if [ -f OPEN-ITEMS.md ]; then
    echo "- blocked on Wes: $(awk '/^## Blocked on Wes/,/^## Owned by Fable/' OPEN-ITEMS.md | grep -c '^| .* |' | awk '{print $1-2}')"
    echo "- owned by Fable: $(awk '/^## Owned by Fable/,/^## In flight/' OPEN-ITEMS.md | grep -c '^| .* |' | awk '{print $1-2}')"
    echo
    echo "Full text and the reasons: \`OPEN-ITEMS.md\` in the repo."
  fi
} > "$OUT"

echo "wrote $OUT"
