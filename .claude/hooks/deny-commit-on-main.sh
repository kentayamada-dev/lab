#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and denies a git
# commit while the checkout is on main (CLAUDE.md: every change lands through
# a PR from a working branch).
#
# The branch of the checkout the hook runs in is only the starting point: a
# compound command may move between branches before it commits, so the branch
# creations (checkout -b/-B / switch -c/-C / switch --create) and the switches
# to main (checkout main / switch main) that precede the first commit are
# replayed by offset, and the commit is denied if that leaves the command on
# main. Branching off first is allowed; switching to main first is denied even
# from a working branch. A creation flag has to stand on its own (-c feat, not
# -cfeat) to count, and "checkout main -- <path>" restores files rather than
# switching. [^|;&\n] keeps each match inside one pipeline segment (a newline
# separates commands just as ; does). Matching is textual, not a shell parse
# (docs/ci-jobs.md#hooks), and the starting branch is the one of this checkout,
# so a command that commits in another repository (cd elsewhere, git -C) is
# judged against this checkout all the same.
#
# The hook fails closed: on main, a tool call it cannot read (not JSON, or no
# command string) is denied rather than waved through — a verdict must never
# rest on a guess, and here the guess would open the gate. Off main there is
# nothing for this hook to protect, so it stays silent whatever the input —
# silence that leans on ask-before-commit-push-pr.sh asking about the same
# unreadable input; without that hook it would pass unconfirmed.

deny() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$1"
}

on_main=false
[ "$(git branch --show-current 2>/dev/null)" != "main" ] || on_main=true

input="$(cat)"

if ! jq -e '.tool_input.command | type == "string"' <<<"${input}" >/dev/null 2>&1; then
  if [ "${on_main}" = true ]; then
    deny "The hook could not read the tool call, and on main an unreadable command is denied rather than guessed at. CLAUDE.md: never commit on main."
  fi
  exit 0
fi

# At an equal offset (checkout -B main is both) the switch to main wins: sort_by
# orders false before true, and the reduce keeps the last event.
if jq -e --argjson on_main "${on_main}" '
    .tool_input.command as $c
    | ([$c | match("\\bgit\\b[^|;&\\n]*\\bcommit\\b").offset] + [null])[0] as $commit
    | ($commit != null) and (
        [ ($c | match("\\bgit\\b[^|;&\\n]*\\b(checkout|switch)\\b[^|;&\\n]*\\s(-b|-B|-c|-C|--create)\\b"; "g") | {offset, main: false}),
          ($c | match("\\bgit\\b[^|;&\\n]*\\b(checkout|switch)\\b[^|;&\\n]*\\smain(?![^\\s;|&])(?![^|;&\\n]*\\s--(\\s|$))"; "g") | {offset, main: true}) ]
        | map(select(.offset < $commit))
        | sort_by(.offset, .main)
        | reduce .[].main as $m ($on_main; $m)
      )
  ' <<<"${input}" >/dev/null; then
  deny "CLAUDE.md: never commit on main — create a working branch from the latest remote main first."
fi
