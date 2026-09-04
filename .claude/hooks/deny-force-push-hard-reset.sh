#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: reads the tool-call JSON on stdin and denies a force
# push, a hard reset, or a git clean. The hard deny belongs to the deny rules in
# settings.json, which is where Claude Code's own guidance puts it and which
# read the command as a shell rather than as text; this hook covers what a rule
# there still cannot name: the flag bundled with other short flags, options to
# git itself before the subcommand (git -C dir push -f), and the flagless +
# refspec (docs/ci-jobs.md#hooks).
#
# --force\b covers --force-with-lease and --force-if-includes too (the hyphen
# is a word boundary): with main unpushable and every change squash-merged,
# the safer variants have no job here either. git bundles short flags, so -fu
# and -uf are force pushes as much as -f is: any single-dash cluster that holds
# an f counts, which -[a-zA-Z]*f[a-zA-Z]* expresses (a long option starts with
# a second hyphen, so --follow-tags is left alone). A refspec that starts with
# + is a force push carrying no flag at all, so \s\+\S counts as one. Matching
# is textual, not a shell parse (docs/ci-jobs.md#hooks).
#
# git clean is denied in every form, the dry run included, to match the deny
# rule in settings.json: untracked files are uncommitted work too, and a clean
# that deletes nothing tells nothing that git status does not.
#
# The hook fails closed: a tool call it cannot read (not JSON, or no command
# string) is denied rather than waved through — the guarded operations destroy
# pushed history or uncommitted work, so a verdict must never rest on a guess
# that would open the gate. A command it can read but not resolve gets the
# weaker form of the same rule: a push or reset whose segment carries a $ or a
# backtick is asked about rather than let through, because what the flag turns
# out to be is up to the shell, and a textual match never learns it.

deny() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$1"
}

ask() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "%s"}}\n' "$1"
}

input="$(cat)"

if ! jq -e '.tool_input.command | type == "string"' <<<"${input}" >/dev/null 2>&1; then
  deny "The hook could not read the tool call, and an unreadable command is denied rather than guessed at: a force push, hard reset, or git clean must not slip through."
  exit 0
fi

# What the three patterns below read: the command normalized as
# docs/ci-jobs.md#hooks describes. The class is the two quote characters, the
# single one written \x27 so the filter itself stays a single-quoted word.
normalized='.tool_input.command | gsub("[ \t]*\\\\\n[ \t]*"; " ") | gsub("[\"\\x27]"; "")'

if jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*\\bpush\\b[^|;&\\n]*(\\s(--force\\b|-[a-zA-Z]*f[a-zA-Z]*(\\s|$))|\\s\\+\\S)")
  ' <<<"${input}" >/dev/null; then
  deny "Force pushes are denied — they rewrite pushed history, and main only moves through squash-merged PRs."
elif jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*\\breset\\b[^|;&\\n]*\\s--hard\\b")
  ' <<<"${input}" >/dev/null; then
  deny "git reset --hard is denied — it throws away uncommitted work; prefer git stash or a soft reset."
elif jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*\\bclean\\b")
  ' <<<"${input}" >/dev/null; then
  deny "git clean is denied — it deletes untracked files, which are uncommitted work too; prefer git stash -u."
elif jq -e "${normalized}"'
    | test("\\bgit\\b[^|;&\\n]*(\\bpush\\b[^|;&\\n]*[$`]|\\breset\\b(?![^|;&\\n]*\\s--(soft|mixed|keep|merge)\\b)[^|;&\\n]*[$`]|[$`][^|;&\\n]*\\b(push|reset)\\b)")
  ' <<<"${input}" >/dev/null; then
  ask "This push or reset is spelled with an expansion, so the hook cannot tell whether it forces or resets hard — confirm it does neither."
fi
