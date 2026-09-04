#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and denies a hard
# reset or a git clean — the two commands whose loss no server can undo
# (CLAUDE.md: uncommitted work must survive).
#
# Force pushes and commits on main used to be here and are not any more. The
# ruleset (.github/rulesets/main.json) refuses a non-fast-forward push to main
# and every push that does not arrive through a pull request, with no bypass
# actor, so both are already impossible where they would matter; the deny rules
# in settings.json still name the force-push spellings a permission rule can
# read. What no ruleset reaches is the working tree, which exists only on this
# machine, and that is what is left for a hook to guard.
#
# The deny rules in settings.json name these two as well, and read the command
# as a shell rather than as text; what they cannot name is an option to git
# itself before the subcommand (git -C dir clean -f), which is why the textual
# match stays (docs/ci-jobs.md#hooks). A word right after a hyphen or a slash
# is part of a name rather than a subcommand, which keeps reading this file by
# path from counting as running what it guards.
#
# git clean is denied in every form, the dry run included, to match the deny
# rule in settings.json: untracked files are uncommitted work too, and a clean
# that deletes nothing tells nothing that git status does not.
#
# The hook fails closed: a tool call it cannot read (not JSON, or no command
# string) is denied rather than waved through — the work these commands delete
# is gone for good, so a verdict must never rest on a guess. A command it can
# read but not resolve gets the weaker form of the same rule: a reset whose
# segment carries a $ or a backtick is asked about rather than let through,
# because what the flag turns out to be is up to the shell, and a textual match
# never learns it.

deny() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$1"
}

ask() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "%s"}}\n' "$1"
}

input="$(cat)"

if ! jq -e '.tool_input.command | type == "string"' <<<"${input}" >/dev/null 2>&1; then
  deny "The hook could not read the tool call, and an unreadable command is denied rather than guessed at: a hard reset or a git clean must not slip through."
  exit 0
fi

# What the three patterns below read: the command normalized as
# docs/ci-jobs.md#hooks describes. The class is the two quote characters, the
# single one written \x27 so the filter itself stays a single-quoted word.
normalized='.tool_input.command | gsub("[ \t]*\\\\\n[ \t]*"; " ") | gsub("[\"\\x27]"; "")'

if jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*\\breset\\b[^|;&\\n]*\\s--hard\\b")
  ' <<<"${input}" >/dev/null; then
  deny "git reset --hard is denied — it throws away uncommitted work; prefer git stash or a soft reset."
elif jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*(?<![-/])\\bclean\\b")
  ' <<<"${input}" >/dev/null; then
  deny "git clean is denied — it deletes untracked files, which are uncommitted work too; prefer git stash -u."
elif jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*\\breset\\b(?![^|;&\\n]*\\s--(soft|mixed|keep|merge)\\b)[^|;&\\n]*[$`]")
  ' <<<"${input}" >/dev/null; then
  ask "This reset is spelled with an expansion, so the hook cannot tell whether it resets hard — confirm it does not."
fi
