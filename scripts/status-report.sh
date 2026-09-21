#!/usr/bin/env bash
# Writes docs/STATUS.md: the plain-language answer to "what is going on with Roost".
#
# GitHub and health are read live. Product questions remain in OPEN-ITEMS.md.
# This file is public: never include credentials or hardware identifiers.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
OUT="$PWD/docs/STATUS.md"

# Fetch before writing so an unavailable GitHub API cannot publish "nothing open"
# or destroy the last successful snapshot.
main_rev=$(gh api repos/amnanninga4/roost/commits/main --jq .sha) || exit 1
prs=$(gh pr list --state open --limit 1000 --json number,title,labels) || exit 1
anne_issues=$(gh issue list --state open --label needs-anne --limit 1000 --json number,title) || exit 1
ci=$(gh run list --branch main --workflow ci.yml --limit 1 --json status,conclusion,url,headSha \
  --jq '.[] | "\(.status) / \(.conclusion) — [\(.headSha[0:7])](\(.url))"') || exit 1
pr_lines() {
  printf '%s' "$prs" | python3 -c '
import json,sys
wanted = sys.argv[1] == "needs-wes"
for p in json.load(sys.stdin):
    if any(l["name"] == "needs-wes" for l in p["labels"]) == wanted:
        print("- {} [#{}](https://github.com/amnanninga4/roost/pull/{})".format(p["title"], p["number"], p["number"]))
' "$1"
}

waiting=$(pr_lines needs-wes) || exit 1
working=$(pr_lines other) || exit 1
anne_lines=$(printf '%s' "$anne_issues" | python3 -c '
import json,sys
issues=json.load(sys.stdin)
for i in issues:
    print("- {} [#{}](https://github.com/amnanninga4/roost/issues/{})".format(i["title"], i["number"], i["number"]))
if not issues: print("- No open issues labeled needs-anne.")
') || exit 1

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
  echo "| Latest code on main | \`${main_rev:0:7}\` |"
  echo "| Latest main CI | ${ci:-No runs found} |"
  echo "| Chores loaded | $(field choresSeeded), list version $(field choresVersion) |"
  echo "| Registered devices | $(field devices) |"
  echo "| Push notifications | $(field push) |"
  echo "| Last morning digest | $(field digestLastSent) |"
  backup_ok=$(printf '%s' "$health" | python3 -c "import json,sys;b=json.load(sys.stdin).get('backup') or {};print(('ok' if b.get('ok') else ('FAILING' if b else '?'))+' — '+str(b.get('at','?'))[:16].replace('T',' ')+' UTC')" 2>/dev/null || echo '?')
  echo "| Last backup | $backup_ok |"
  echo
  echo "## Waiting on you"
  echo
  echo "Only things Fable cannot decide: taste calls, and anything irreversible, outward-facing,"
  echo "or costing money. Code review is not on this list — Fable merges its own work on green CI."
  echo
  printf '%s\n' "${waiting:-- No open pull requests labeled needs-wes.}"
  echo
  echo "Non-code items only you can do are in the *Blocked on Wes* table of \`OPEN-ITEMS.md\`."
  echo
  echo "## In flight"
  echo
  echo "Open pull requests on GitHub. Local work is tracked in \`OPEN-ITEMS.md\`."
  echo
  printf '%s\n' "${working:-- No other open pull requests.}"
  echo
  echo "## Waiting on Anne"
  echo
  printf '%s\n' "$anne_lines"
  echo
  echo "Product questions and their verification limits are in \`OPEN-ITEMS.md\`."
  echo
  echo "## The phones"
  echo
  echo "Installed builds and TestFlight distribution have not been verified by this report."
  echo "Registered devices above are server records, not proof of active phones or push delivery."
  echo
  echo "## Open items, counted"
  echo
  if [ -f OPEN-ITEMS.md ]; then
    # Count data rows in one section: every table line that is not the header and not the
    # |---|---| separator. The range ends at the NEXT `## ` heading, whatever it is called —
    # naming the following section by hand broke the moment a section was inserted between them.
    count_rows() {
      awk -v want="$1" '
        /^## / { inside = ($0 == "## " want) ; next }
        inside && /^\|/ && !/^\|[[:space:]]*-/ && !/^\| Item \|/ && !/^\| \| \|/ { n++ }
        END { print n + 0 }' OPEN-ITEMS.md
    }
    echo "- blocked on Wes: $(count_rows "Blocked on Wes")"
    echo "- waiting on Anne: $(count_rows "Waiting on Anne")"
    echo "- owned by Fable: $(count_rows "Owned by Fable")"
    echo
    echo "Full text and the reasons: \`OPEN-ITEMS.md\` in the repo."
  fi
} > "$OUT"

echo "wrote $OUT"
