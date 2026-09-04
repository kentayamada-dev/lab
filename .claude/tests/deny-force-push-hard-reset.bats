#!/usr/bin/env bats

setup() {
  load helper
}

# assert_decision <expected permissionDecision, empty for silence> <command>
assert_decision() {
  assert_answer deny-force-push-hard-reset.sh "$(tool_call command "$2")" \
    .hookSpecificOutput.permissionDecision "$1"
}

@test "answers with a PreToolUse deny and a reason" {
  output="$(answer deny-force-push-hard-reset.sh "$(tool_call command 'git push --force')")"
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"${output}")" = PreToolUse ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"${output}")" = deny ]
  [ -n "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"${output}")" ]
}

@test "denies a force push wherever the flag sits" {
  assert_decision deny 'git push --force'
  assert_decision deny 'git push origin main --force'
  assert_decision deny 'git push -f origin HEAD'
  assert_decision deny 'git push origin HEAD -f'
}

@test "denies the flag bundled with other short flags" {
  assert_decision deny 'git push -fu origin HEAD'
  assert_decision deny 'git push origin HEAD -uf'
  assert_decision deny 'git push -quf origin HEAD'
}

@test "denies the with-lease and if-includes variants" {
  assert_decision deny 'git push --force-with-lease origin main'
  assert_decision deny 'git push origin main --force-if-includes'
}

@test "denies a + refspec, the force push that carries no flag" {
  assert_decision deny 'git push origin +main'
}

@test "denies a hard reset wherever the flag sits" {
  assert_decision deny 'git reset --hard'
  assert_decision deny 'git reset --hard HEAD~1'
  assert_decision deny 'git reset -q --hard HEAD'
}

@test "denies a git clean, the dry run included" {
  assert_decision deny 'git clean -fdx'
  assert_decision deny 'git clean -n'
  assert_decision deny 'git -C docs clean -f'
}

@test "denies when the command hides in a compound command" {
  assert_decision deny 'git fetch && git push -f'
  assert_decision deny 'cd docs; git reset --hard'
  assert_decision deny 'cd docs && git clean -fdx'
}

@test "denies a merely quoted mention" {
  assert_decision deny 'echo "git push --force"'
}

@test "denies a command continued onto the next line" {
  assert_decision deny $'git push origin HEAD \\\n  --force'
  assert_decision deny $'git reset \\\n  --hard HEAD~1'
  assert_decision deny $'git \\\n  clean -fdx'
}

@test "denies a quoted flag, refspec, or alias definition" {
  assert_decision deny 'git push origin HEAD "-f"'
  assert_decision deny "git push origin '+HEAD:main'"
  assert_decision deny "git reset '--hard'"
  assert_decision deny "git config alias.pf 'push -f'"
}

@test "asks about a push or reset whose flag only an expansion spells out" {
  assert_decision ask 'f=--force; git push origin HEAD "$f"'
  assert_decision ask 'h=--hard; git reset $h'
  assert_decision ask 'git push origin HEAD $FLAGS'
  assert_decision ask 'git reset $(git merge-base main HEAD)'
  assert_decision ask 'git push `cat flag` origin main'
}

@test "denies rather than asks when the expansion sits next to a named flag" {
  assert_decision deny 'git push --force origin $BRANCH'
  assert_decision deny 'git reset --hard $BASE'
  assert_decision deny 'git clean -fdx $DIR'
}

@test "stays silent for a reset that names a mode the expansion cannot be" {
  assert_decision '' 'git reset --soft $BASE'
  assert_decision '' 'git reset --mixed $BASE'
  assert_decision '' 'git reset --keep $BASE'
  assert_decision '' 'git reset $h --soft'
}

@test "stays silent for an expansion outside a push or reset" {
  assert_decision '' 'git log --oneline $BASE'
  assert_decision '' 'git status | grep $x'
}

@test "stays silent for an ordinary push or reset" {
  assert_decision '' 'git push origin HEAD'
  assert_decision '' 'git push --follow-tags origin main'
  assert_decision '' 'git push -u origin HEAD'
  assert_decision '' 'git push -qu origin feature/force-field'
  assert_decision '' 'git reset --soft HEAD~1'
  assert_decision '' 'git reset HEAD~1'
}

@test "stays silent when the words fall in different pipeline segments" {
  assert_decision '' 'git log --oneline | grep -- --force'
  assert_decision '' 'git push origin HEAD | grep -- -f'
  assert_decision '' 'git status --porcelain | grep clean'
}

@test "stays silent when the words fall on different lines" {
  assert_decision '' $'git push origin HEAD\necho --force'
}

@test "stays silent for an unrelated command" {
  assert_decision '' 'ls -la'
}

@test "denies when the tool call carries no command" {
  assert_answer deny-force-push-hard-reset.sh '{}' .hookSpecificOutput.permissionDecision deny
}

@test "denies when the command is not text" {
  assert_answer deny-force-push-hard-reset.sh '{"tool_input": {"command": 123}}' \
    .hookSpecificOutput.permissionDecision deny
}

@test "denies when the tool call is not JSON" {
  assert_answer deny-force-push-hard-reset.sh 'not json' .hookSpecificOutput.permissionDecision deny
}
