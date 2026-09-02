#!/usr/bin/env bats

# The hook reads the branch of the checkout it runs in, so each test gets a
# throwaway repository. An unborn HEAD still reports its branch name, which is
# why no commit is needed here.
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

@test "allows a commit that creates its branch first" {
  assert_decision '' 'git switch -c feat && git commit -m x'
  assert_decision '' 'git checkout -b feat && git commit -m x'
  assert_decision '' 'git switch --create feat && git commit -m x'
  assert_decision '' $'git switch -c feat\ngit commit -m x'
}

@test "allows a commit that force-creates its branch first" {
  assert_decision '' 'git checkout -B feat && git commit -m x'
  assert_decision '' 'git switch -C feat && git commit -m x'
}

@test "denies a commit that switches branches only afterwards" {
  assert_decision deny 'git commit -m x && git switch -c feat'
}

# The branch flag has to stand on its own to be read as one, so this branch is
# created and the commit denied all the same. Writing it as -c feat is the way
# through.
@test "denies a commit behind a branch flag stuck to its value" {
  assert_decision deny 'git switch -cfeat && git commit -m x'
}

@test "denies a merely quoted mention" {
  assert_decision deny 'echo "git commit"'
}

@test "leaves push and PR creation to the other hook" {
  assert_decision '' 'git push origin main'
  assert_decision '' 'gh pr create --fill'
}

@test "stays silent when the words fall in different pipeline segments" {
  assert_decision '' 'git log --oneline | grep commit'
}

@test "stays silent when the words fall on different lines" {
  assert_decision '' $'git log --oneline\ngrep commit'
}

@test "stays silent outside a git repository" {
  cd "${BATS_TEST_TMPDIR}" || return 1
  assert_decision '' 'git commit -m "message"'
}

# The hook fails closed: on main, a tool call it cannot read is denied rather
# than waved through.
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

# Off main there is nothing for this hook to protect, so failing closed does
# not reach there: even an unreadable tool call passes.
@test "stays silent off main even for an unreadable tool call" {
  git switch -q -c feat
  assert_answer deny-commit-on-main.sh 'not json' .hookSpecificOutput.permissionDecision ''
  assert_answer deny-commit-on-main.sh '{}' .hookSpecificOutput.permissionDecision ''
}
