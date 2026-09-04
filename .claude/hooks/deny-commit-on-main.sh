#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and denies a git
# commit while the checkout is on main (CLAUDE.md: every change lands through
# a PR from a working branch).
#
# The branch of the checkout is one of the two things that decide it: a
# compound command may switch to main before it commits, so a checkout main /
# switch main that precedes the first commit is denied as well, even from a
# working branch. What the hook does not do is credit a branch the same command
# creates: "git switch -c feat && git commit" is refused on main, and the two
# halves are run as two commands instead. Crediting it took replaying every
# branch event in the command by offset, and what that bought was a flow any
# two commands already express. "checkout main -- <path>" restores files rather
# than switching, and is left alone. A word right after a hyphen or a slash is
# part of a name rather than a subcommand, so reading this file by path is not
# a commit. Matching is textual, not a shell parse
# (docs/ci-jobs.md#hooks), and the starting branch is the one of this checkout,
# so a command that commits in another repository (cd elsewhere, git -C) is
# judged against this checkout all the same.
#
# The hook fails closed: on main, a tool call it cannot read (not JSON, or no
# command string) is denied rather than waved through — a verdict must never
# rest on a guess, and here the guess would open the gate. Off main an
# unreadable call is let through: a plain commit there is allowed, and the
# switch to main that would make it one is exactly what cannot be seen —
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

# What the patterns below read: the command normalized as
# docs/ci-jobs.md#hooks describes. The class is the two quote characters, the
# single one written \x27 so the filter itself stays a single-quoted word. Both
# offsets are taken from this one normalized string.
normalized='.tool_input.command | gsub("[ \t]*\\\\\n[ \t]*"; " ") | gsub("[\"\\x27]"; "")'

if jq -e --argjson on_main "${on_main}" "${normalized}"'
    as $c
    | ([$c | match("\\bgit\\b[^|;&\\n]*(?<![-/])\\bcommit\\b").offset] + [null])[0] as $commit
    | ($commit != null)
      and ($on_main
           or ([$c | match("\\bgit\\b[^|;&\\n]*\\b(checkout|switch)\\b[^|;&\\n]*\\smain(?![^\\s;|&])(?![^|;&\\n]*\\s--(\\s|$))"; "g").offset]
               | any(. < $commit)))
  ' <<<"${input}" >/dev/null; then
  deny "CLAUDE.md: never commit on main — switch to a working branch created from the latest remote main, as a command of its own, and commit after that."
fi
