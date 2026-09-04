#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and asks for
# confirmation when the command looks like a git commit/push or gh pr create
# (CLAUDE.md: those need an explicit user request).
#
# A push right after stash is git stash push, the local operation CLAUDE.md
# prefers over a hard reset, so it is left alone. A word right after a hyphen
# or a slash is part of a name rather than a subcommand, which is what keeps
# "git show HEAD:.claude/hooks/deny-commit-on-main.sh" out of this: the files
# this hook guards are named after what they guard, and reading them is not
# doing it. Matching is textual, not a shell parse (docs/ci-jobs.md#hooks).
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

# What the pattern below reads: the command normalized as
# docs/ci-jobs.md#hooks describes. The class is the two quote characters, the
# single one written \x27 so the filter itself stays a single-quoted word.
normalized='.tool_input.command | gsub("[ \t]*\\\\\n[ \t]*"; " ") | gsub("[\"\\x27]"; "")'

if jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*(?<![-/])\\b(commit|(?<!stash\\s)push)\\b|\\bgh\\b[^|;&\\n]*\\bpr\\b[^|;&\\n]*\\bcreate\\b")
  ' <<<"${input}" >/dev/null; then
  ask "CLAUDE.md: commit/push/PR creation requires an explicit user request — confirm before running."
fi
