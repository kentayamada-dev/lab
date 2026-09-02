#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and denies a force
# push or a hard reset. The permissions.deny rules in settings.json match only
# commands that begin with the flagged form; this hook also catches a flag
# placed after other arguments and a command buried inside a compound one.
#
# --force\b covers --force-with-lease and --force-if-includes too (the hyphen
# is a word boundary): with main unpushable and every change squash-merged,
# the safer variants have no job here either. A refspec that starts with + is
# a force push carrying no flag at all, so \s\+\S counts as one. [^|;&\n]
# keeps each match inside one pipeline segment (a newline separates commands
# just as ; does). Matching is textual, not a shell parse (docs/ci-jobs.md#hooks).
#
# The hook fails closed: a tool call it cannot read (not JSON, or no command
# string) is denied rather than waved through — the guarded operations destroy
# pushed history or uncommitted work, so a verdict must never rest on a guess
# that would open the gate.

deny() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$1"
}

input="$(cat)"

if ! jq -e '.tool_input.command | type == "string"' <<<"${input}" >/dev/null 2>&1; then
  deny "The hook could not read the tool call, and an unreadable command is denied rather than guessed at: a force push or hard reset must not slip through."
  exit 0
fi

if jq -e '.tool_input.command
    | test("\\bgit\\b[^|;&\\n]*\\bpush\\b[^|;&\\n]*(\\s(--force|-f)\\b|\\s\\+\\S)")
  ' <<<"${input}" >/dev/null; then
  deny "Force pushes are denied — they rewrite pushed history, and main only moves through squash-merged PRs."
elif jq -e '.tool_input.command
    | test("\\bgit\\b[^|;&\\n]*\\breset\\b[^|;&\\n]*\\s--hard\\b")
  ' <<<"${input}" >/dev/null; then
  deny "git reset --hard is denied — it throws away uncommitted work; prefer git stash or a soft reset."
fi
