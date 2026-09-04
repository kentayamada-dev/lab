#!/usr/bin/env bats

# An unborn HEAD still reports its branch name, so the throwaway repository
# needs no commit.
setup() {
  load helper
  git init -q -b main "${BATS_TEST_TMPDIR}/repo"
  cd "${BATS_TEST_TMPDIR}/repo" || return 1
}

# assert_decision <expected permissionDecision, empty for silence> <command>
assert_decision() {
  assert_answer deny-commit-on-main.sh "$(tool_call command "$2")" \
    .hookSpecificOutput.permissionDecision "$1"
}

@test "answers with a PreToolUse deny and a reason" {
  output="$(answer deny-commit-on-main.sh "$(tool_call command 'git commit -m x')")"
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"${output}")" = PreToolUse ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"${output}")" = deny ]
  [ -n "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"${output}")" ]
}

@test "denies a commit on main" {
  assert_decision deny 'git commit -m "message"'
}

@test "allows a commit on a working branch" {
  git switch -q -c feat
  assert_decision '' 'git commit -m "message"'
}

@test "allows a commit on a branch whose name only starts with main" {
  git switch -q -c main-fix
  assert_decision '' 'git commit -m "message"'
}

@test "allows a commit on a detached HEAD" {
  git -c user.email=hook@test -c user.name=hook commit -q --allow-empty -m init
  git switch -q --detach
  assert_decision '' 'git commit -m "message"'
}

@test "denies a commit whose branch the same command creates" {
  assert_decision deny 'git switch -c feat && git commit -m x'
  assert_decision deny 'git checkout -b feat && git commit -m x'
  assert_decision deny 'git switch --create feat && git commit -m x'
  assert_decision deny 'git checkout -B feat && git commit -m x'
  assert_decision deny $'git switch -c feat\ngit commit -m x'
}

@test "allows the same commit once the branch is a command of its own" {
  git switch -q -c feat
  assert_decision '' 'git commit -m x'
}

@test "denies a commit that switches branches only afterwards" {
  assert_decision deny 'git commit -m x && git switch -c feat'
}

@test "denies a commit that switches to main first, even from a working branch" {
  git switch -q -c feat
  assert_decision deny 'git switch main && git commit -m x'
  assert_decision deny 'git checkout main && git commit -m x'
  assert_decision deny 'git switch main; git commit -m x'
  assert_decision deny 'git switch main&&git commit -m x'
  assert_decision deny $'git switch main\ngit commit -m x'
}

@test "denies a commit that force-creates main first" {
  git switch -q -c feat
  assert_decision deny 'git checkout -B main && git commit -m x'
}

@test "denies a commit that branches off again after switching to main" {
  git switch -q -c feat
  assert_decision deny 'git switch main && git pull && git switch -c fix && git commit -m x'
}

@test "denies a commit that returns to main after branching off" {
  assert_decision deny 'git switch -c feat && git switch main && git commit -m x'
}

@test "allows a commit that only restores files from main" {
  git switch -q -c feat
  assert_decision '' 'git checkout main -- README.md && git commit -m x'
}

@test "allows a commit after switching to a branch whose name only starts with main" {
  git switch -q -c feat
  assert_decision '' 'git switch main-fix && git commit -m x'
}

@test "denies a merely quoted mention" {
  assert_decision deny 'echo "git commit"'
}

@test "denies a commit continued onto the next line" {
  assert_decision deny $'git \\\n  commit -m x'
  git switch -q -c feat
  assert_decision deny $'git switch main && \\\n  git commit -m x'
}

@test "allows a file restore continued onto the next line" {
  git switch -q -c feat
  assert_decision '' $'git checkout main -- \\\n  README.md && git commit -m x'
}

@test "reads a quoted branch name as the branch name" {
  git switch -q -c feat
  assert_decision deny "git switch 'main' && git commit -m x"
  assert_decision '' "git switch 'main-fix' && git commit -m x"
}

@test "allows a commit whose message merely mentions switching to main" {
  git switch -q -c feat
  assert_decision '' 'git commit -m "switch to main"'
}

@test "leaves push and PR creation to the other hook" {
  assert_decision '' 'git push origin main'
  assert_decision '' 'gh pr create --fill'
}

@test "stays silent when the words fall in different pipeline segments" {
  assert_decision '' 'git log --oneline | grep commit'
}

@test "stays silent for a path whose name carries the subcommand" {
  assert_decision '' 'git show HEAD:.claude/hooks/deny-commit-on-main.sh'
  assert_decision '' 'git log --oneline -- .claude/hooks/ask-before-commit-push-pr.sh'
  assert_decision '' 'git blame .claude/tests/deny-commit-on-main.bats'
}

@test "stays silent when the words fall on different lines" {
  assert_decision '' $'git log --oneline\ngrep commit'
}

@test "stays silent outside a git repository" {
  cd "${BATS_TEST_TMPDIR}" || return 1
  assert_decision '' 'git commit -m "message"'
}

@test "denies on main when the tool call carries no command" {
  assert_answer deny-commit-on-main.sh '{}' .hookSpecificOutput.permissionDecision deny
}

@test "denies on main when the command is not text" {
  assert_answer deny-commit-on-main.sh '{"tool_input": {"command": 123}}' \
    .hookSpecificOutput.permissionDecision deny
}

@test "denies on main when the tool call is not JSON" {
  assert_answer deny-commit-on-main.sh 'not json' .hookSpecificOutput.permissionDecision deny
}

@test "stays silent off main even for an unreadable tool call" {
  git switch -q -c feat
  assert_answer deny-commit-on-main.sh 'not json' .hookSpecificOutput.permissionDecision ''
  assert_answer deny-commit-on-main.sh '{}' .hookSpecificOutput.permissionDecision ''
}
