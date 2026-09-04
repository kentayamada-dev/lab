# CLAUDE.md

## Critical rules

- When the user's intent or the implementation approach is unclear, or you are torn between approaches, ask the user right away instead of guessing
- Never state anything as fact without first verifying it in the repo, the tool output, or an authoritative reference; when verification is impossible, say so explicitly instead of guessing
- Claude edits files only; do not commit, push, or create a PR unless explicitly asked
- Which language goes where (Japanese vs English): [CONTRIBUTING.md](CONTRIBUTING.md#ドキュメントの言語)

## Project overview

A Todo app monorepo: a Connect API in Go (api/), a Next.js frontend (web/), protobuf definitions (proto/), and a Postgres schema managed with Atlas (api/schema.sql, db/migrations). Repository operations (branch protection, CI, Renovate) are defined in the repo as well (.github/, scripts/). Local development and the app-code CI jobs share the same entry point — the root Makefile, which runs everything inside docker compose services.

## Documentation

- No duplication: comments say only what the nearby code and repo docs cannot tell; repo docs say only what the code and easily found online references cannot tell

## Repository etiquette

- PR titles must follow Conventional Commits
- main cannot be pushed to; every change lands through a PR, squash merge only
- Never force-push or hard-reset: pushed history and uncommitted work must survive (prefer git stash or a soft reset)
- Before committing, fetch and integrate the latest remote main, then create a working branch from it, as a command of its own: a commit chained onto its own branch creation is denied, so run the two separately
- Write commit messages and PR titles/bodies in Japanese, keeping the Conventional Commits type in the title (on squash the PR title becomes, verbatim, the commit title on main, and the messages are concatenated into its body)
- Pass commit messages and PR bodies via a file (`git commit -F`, `gh pr create --body-file`), not inline: prose that quotes a guarded command inside a command string trips the deny hooks

## References

Plain links, not @imports, to keep session context small.

- Development flow and PR title format: [README.md](README.md)
- Contribution entry points: [CONTRIBUTING.md](CONTRIBUTING.md)
- Per-job details: [docs/ci-jobs.md](docs/ci-jobs.md)
