#!/usr/bin/env bash
#
# Closes every open issue whose title is exactly <title>, leaving <comment> on each to
# say why. This is how the scheduled workflows retract the issue they opened once the
# check behind it passes again; with no such issue open it does nothing.
#
# The title identifies the issue here, so it has to be the one the issue was opened with,
# character for character, and it has to be an issue github-actions[bot] opened (why the
# author is part of the identity: upsert-issue.sh). Only the first 100 open issues are
# looked at, the same window upsert-issue.sh searches before it opens one.
#
# Usage:
#   ./.github/scripts/close-issues-by-title.sh <title> <comment>
#
# Environment variables:
#   GH_TOKEN  a token with issues write access (gh reads it itself)
#   GH_REPO   target repository (default: derived from the checkout)
#
set -euo pipefail

case "${1:-}" in
  -h | --help)
    awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/, ""); print}' "$0"
    exit 0
    ;;
esac

if [[ $# -ne 2 ]]; then
  echo "usage: $(basename "$0") <title> <comment>" >&2
  exit 2
fi

title="$1"
comment="$2"

# Captured rather than piped straight into the loop so that a failing gh aborts the
# run: inside a process substitution its exit status would go unseen.
numbers="$(gh issue list --state open --limit 100 --author 'github-actions[bot]' --json number,title |
  jq -r --arg t "$title" '.[] | select(.title == $t) | .number')"

# With nothing to close the command substitution above is empty, which still reaches
# the loop as one empty line, hence the guard rather than a count.
while IFS= read -r number; do
  [[ -n "$number" ]] || continue
  gh issue close "$number" --comment "$comment"
done <<<"$numbers"
