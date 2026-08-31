#!/usr/bin/env bats

setup() {
  load helper
}

# assert_decision <expected permissionDecision, empty for silence> <command>
assert_decision() {
  assert_answer ask-before-commit-push-pr.sh "$(tool_call command "$2")" \
    .hookSpecificOutput.permissionDecision "$1"
}

@test "answers with a PreToolUse ask and a reason" {
  output="$(answer ask-before-commit-push-pr.sh "$(tool_call command 'git push')")"
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"${output}")" = PreToolUse ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"${output}")" = ask ]
  [ -n "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"${output}")" ]
}

@test "asks before a commit" {
  assert_decision ask 'git commit -m "message"'
}

@test "asks before a push" {
  assert_decision ask 'git push origin HEAD'
}

@test "asks before creating a PR" {
  assert_decision ask 'gh pr create --fill'
}

@test "asks when the commit sits in the middle of a compound command" {
  assert_decision ask 'cd docs && git commit -am fix'
}

@test "asks for a merely quoted mention" {
  assert_decision ask 'echo "git push"'
}

@test "stays silent when the words fall in different pipeline segments" {
  assert_decision '' 'git log --oneline | grep push'
  assert_decision '' 'gh pr view 1 | grep create'
}

@test "stays silent when the words fall on different lines" {
  assert_decision '' $'git log --oneline\ngrep push'
}

@test "stays silent for a read-only git or gh command" {
  assert_decision '' 'git status'
  assert_decision '' 'gh pr list'
}

@test "stays silent for an unrelated command" {
  assert_decision '' 'ls -la'
}

# The hook fails closed: a tool call it cannot read gets the same "ask",
# because a command the hook cannot see must not slip past unconfirmed.
@test "asks when the tool call carries no command" {
  assert_answer ask-before-commit-push-pr.sh '{}' .hookSpecificOutput.permissionDecision ask
}

@test "asks when the command is not text" {
  assert_answer ask-before-commit-push-pr.sh '{"tool_input": {"command": 123}}' \
    .hookSpecificOutput.permissionDecision ask
}

@test "asks when the tool call is not JSON" {
  assert_answer ask-before-commit-push-pr.sh 'not json' .hookSpecificOutput.permissionDecision ask
}
