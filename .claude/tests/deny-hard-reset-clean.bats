#!/usr/bin/env bats

setup() {
  load helper
}

# assert_decision <expected permissionDecision, empty for silence> <command>
assert_decision() {
  assert_answer deny-hard-reset-clean.sh "$(tool_call command "$2")" \
    .hookSpecificOutput.permissionDecision "$1"
}

@test "answers with a PreToolUse deny and a reason" {
  output="$(answer deny-hard-reset-clean.sh "$(tool_call command 'git reset --hard')")"
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"${output}")" = PreToolUse ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"${output}")" = deny ]
  [ -n "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"${output}")" ]
}

@test "denies a hard reset wherever the flag sits" {
  assert_decision deny 'git reset --hard'
  assert_decision deny 'git reset --hard HEAD~1'
  assert_decision deny 'git reset -q --hard HEAD'
  assert_decision deny 'git -C docs reset --hard'
}

@test "denies a git clean, the dry run included" {
  assert_decision deny 'git clean -fdx'
  assert_decision deny 'git clean -n'
  assert_decision deny 'git -C docs clean -f'
}

@test "denies when the command hides in a compound command" {
  assert_decision deny 'cd docs; git reset --hard'
  assert_decision deny 'cd docs && git clean -fdx'
}

@test "denies a merely quoted mention" {
  assert_decision deny 'echo "git clean -fdx"'
}

@test "denies a command continued onto the next line" {
  assert_decision deny $'git reset \\\n  --hard HEAD~1'
  assert_decision deny $'git \\\n  clean -fdx'
}

@test "denies a quoted flag or alias definition" {
  assert_decision deny "git reset '--hard'"
  assert_decision deny "git config alias.wipe 'clean -fdx'"
}

@test "asks about a reset whose flag only an expansion spells out" {
  assert_decision ask 'h=--hard; git reset $h'
  assert_decision ask 'git reset $(git merge-base main HEAD)'
  assert_decision ask 'git reset `cat flag`'
}

@test "denies rather than asks when the expansion sits next to a named flag" {
  assert_decision deny 'git reset --hard $BASE'
  assert_decision deny 'git clean -fdx $DIR'
}

@test "stays silent for a reset that names a mode the expansion cannot be" {
  assert_decision '' 'git reset --soft $BASE'
  assert_decision '' 'git reset --mixed $BASE'
  assert_decision '' 'git reset --keep $BASE'
  assert_decision '' 'git reset $h --soft'
}

@test "stays silent for an expansion outside a reset" {
  assert_decision '' 'git log --oneline $BASE'
  assert_decision '' 'git status | grep $x'
}

@test "stays silent for an ordinary reset" {
  assert_decision '' 'git reset --soft HEAD~1'
  assert_decision '' 'git reset HEAD~1'
  assert_decision '' 'git reset'
}

@test "stays silent for reading this hook by path" {
  assert_decision '' 'git show HEAD:.claude/hooks/deny-hard-reset-clean.sh'
  assert_decision '' 'git log --oneline -- .claude/hooks/deny-hard-reset-clean.sh'
}

@test "stays silent for what the ruleset now guards" {
  assert_decision '' 'git push --force origin main'
  assert_decision '' 'git commit -m x'
}

@test "stays silent when the words fall in different pipeline segments" {
  assert_decision '' 'git status --porcelain | grep clean'
  assert_decision '' 'git log --oneline | grep -- --hard'
}

@test "stays silent when the words fall on different lines" {
  assert_decision '' $'git reset HEAD~1\necho --hard'
}

@test "stays silent for an unrelated command" {
  assert_decision '' 'ls -la'
}

@test "denies when the tool call carries no command" {
  assert_answer deny-hard-reset-clean.sh '{}' .hookSpecificOutput.permissionDecision deny
}

@test "denies when the command is not text" {
  assert_answer deny-hard-reset-clean.sh '{"tool_input": {"command": 123}}' \
    .hookSpecificOutput.permissionDecision deny
}

@test "denies when the tool call is not JSON" {
  assert_answer deny-hard-reset-clean.sh 'not json' .hookSpecificOutput.permissionDecision deny
}
