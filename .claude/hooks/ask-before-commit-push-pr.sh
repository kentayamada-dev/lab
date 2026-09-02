#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and asks for
# confirmation when the command looks like a git commit/push or gh pr create
# (CLAUDE.md: those need an explicit user request).
#
# [^|;&\n] keeps each match inside one pipeline segment (a newline separates
# commands just as ; does), so "git log | grep push" does not trigger. Matching
# is textual, not a shell parse (docs/ci-jobs.md#hooks).
#
# The hook fails closed: a tool call it cannot read (not JSON, or no command
# string) gets the same "ask" — confirmation is the gate, and a command the
# hook cannot see must not slip past it unconfirmed.

ask() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "%s"}}\n' "$1"
}

input="$(cat)"

if ! jq -e '.tool_input.command | type == "string"' <<<"${input}" >/dev/null 2>&1; then
  ask "The hook could not read the tool call — confirm it is not a commit, push, or PR creation (CLAUDE.md: those need an explicit user request)."
  exit 0
fi

if jq -e '.tool_input.command
    | test("\\bgit\\b[^|;&\\n]*\\b(commit|push)\\b|\\bgh\\b[^|;&\\n]*\\bpr\\b[^|;&\\n]*\\bcreate\\b")
  ' <<<"${input}" >/dev/null; then
  ask "CLAUDE.md: commit/push/PR creation requires an explicit user request — confirm before running."
fi
