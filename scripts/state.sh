#!/bin/bash
#
# state.sh — what is true about Roost right now. Read it whole; the point is the fields
# you did not come looking for. `push: "no key"` sat in four health reads before anyone
# noticed that every notification in the product was a no-op.
#
#   scripts/state.sh            # everything
#   scripts/state.sh --no-net   # skip the server and GitHub
set -uo pipefail
cd "$(dirname "$0")/.."

net=1
[ "${1:-}" = "--no-net" ] && net=0

rule() { printf '\n== %s ==\n' "$1"; }

rule "repo"
echo "branch:    $(git branch --show-current) @ $(git rev-parse --short HEAD)"
echo "main:      $(git rev-parse --short origin/main 2>/dev/null || echo '?') $(git log -1 --format=%s origin/main 2>/dev/null)"
dirty=$(git status --porcelain | wc -l | tr -d ' ')
echo "dirty:     $dirty file(s)"
echo "branches:  $(git ls-remote --heads origin 2>/dev/null | wc -l | tr -d ' ') on the remote"
echo "worktrees: $(git worktree list | wc -l | tr -d ' ')"
git worktree list | sed 's/^/           /'

rule "toolchain"
echo "xcode:     $(xcodebuild -version 2>/dev/null | head -1)  (CI runs its own — CI is the authority)"
echo "swift:     $(swift --version 2>&1 | grep -o 'Swift version [0-9.]*' | head -1)"

rule "devices"
xcrun devicectl list devices 2>/dev/null | grep -vE '^(Name|---)' | grep -v '^$' | sed 's/^/           /' || echo "           none"

if [ "$net" = 1 ]; then
  rule "server /health (read every field)"
  fssh theoldone "curl -s --max-time 10 http://127.0.0.1:8790/health" 2>/dev/null \
    | python3 -m json.tool 2>/dev/null | sed 's/^/           /' \
    || echo "           unreachable"

  rule "open pull requests"
  gh pr list --state open --json number,title,createdAt,statusCheckRollup \
    --jq '.[] | "           #\(.number) \(.createdAt[0:10]) \(.title) — \([.statusCheckRollup[]?|.conclusion//.state]|join(","))"' 2>/dev/null \
    || echo "           (gh unavailable)"

  rule "open issues"
  gh issue list --state open --json number,title,updatedAt \
    --jq '.[] | "           #\(.number) updated \(.updatedAt[0:10]) \(.title)"' 2>/dev/null \
    || echo "           (gh unavailable)"
fi

rule "open items"
if [ -f OPEN-ITEMS.md ]; then
  grep -m1 'Last swept' OPEN-ITEMS.md | sed 's/^/           /'
  echo "           blocked on Wes: $(sed -n '/## Blocked on Wes/,/^## /p' OPEN-ITEMS.md | grep -c '^| \[*[A-Za-z`]')"
  echo "           owned by Fable: $(sed -n '/## Owned by Fable/,/^## /p' OPEN-ITEMS.md | grep -c '^| \[*[A-Za-z`]')"
  echo "           (read OPEN-ITEMS.md itself before starting a lane)"
else
  echo "           OPEN-ITEMS.md is missing"
fi
echo
