#!/usr/bin/env bash
#
# PostToolUse(Write|Edit) hook: reads the tool-call JSON on stdin and, when the
# edited file is the README or a page under docs/, reminds that its
# English/Japanese counterpart must change in the same PR (CONTRIBUTING.md).
#
# The path is judged relative to the project directory, so that the README of
# the repository is told apart from one belonging to a subdirectory, which has
# no counterpart. Without CLAUDE_PROJECT_DIR there is nothing to be relative
# to, and the hook stays quiet rather than guessing.

jq -c --arg root "${CLAUDE_PROJECT_DIR:-}" 'if $root != "" and ((.tool_input.file_path // "" | strings)
    | ltrimstr($root + "/")
    | test("^README(\\.ja)?\\.md$|^docs/.+\\.md$"))
  then {hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "Bilingual-pair rule (CONTRIBUTING.md): this file has an English/Japanese counterpart (X.md / X.ja.md). Update the counterpart in the same PR (English first)."}}
  else empty end'
