#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and denies a git
# commit while the checkout is on main (CLAUDE.md: every change lands through
# a PR from a working branch).
#
# A compound command may create the branch and commit in one Bash call, so the
# first branch creation (checkout -b / switch -c / switch --create) is compared
# by offset against the first commit: branching first is allowed. The flag has
# to stand on its own (-c feat, not -cfeat) to count as one. [^|;&\n] keeps
# each match inside one pipeline segment (a newline separates commands just as
# ; does). Matching is textual, not a shell parse, so a command that merely
# quotes the words (echo "git commit") is still denied on main — a cheap false
# positive; likewise the branch is the one of the checkout the hook runs in,
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

[ "$(git branch --show-current 2>/dev/null)" = "main" ] || exit 0

input="$(cat)"

if ! jq -e '.tool_input.command | type == "string"' <<<"${input}" >/dev/null 2>&1; then
  deny "The hook could not read the tool call, and on main an unreadable command is denied rather than guessed at. CLAUDE.md: never commit on main."
  exit 0
fi

if jq -e '
    .tool_input.command as $c
    | ([$c | match("\\bgit\\b[^|;&\\n]*\\bcommit\\b").offset] + [null])[0] as $commit
    | ([$c | match("\\bgit\\b[^|;&\\n]*\\b(checkout|switch)\\b[^|;&\\n]*\\s(-b|-c|--create)\\b").offset] + [null])[0] as $branch
    | ($commit != null) and ($branch == null or $branch > $commit)
  ' <<<"${input}" >/dev/null; then
  deny "CLAUDE.md: never commit on main — create a working branch from the latest remote main first."
fi
