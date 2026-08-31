# CLAUDE.md

## Critical rules

- When the user's intent or the implementation approach is unclear, or you are torn between approaches, ask the user right away instead of guessing
- Claude edits files only; do not commit, push, or create a PR unless explicitly asked
- README.md and the files under `docs/` are bilingual pairs (`X.md` English-first + `X.ja.md`, same PR — see CONTRIBUTING.md); everything else is English-only, code comments included

## Project overview

A template repository providing groundwork for repository operations: branch protection, CI, Renovate. It contains no application code — changes here are to workflows, scripts, and documentation.

## Documentation

- No duplication: comments say only what the nearby code and repo docs cannot tell; repo docs say only what the code and easily found online references cannot tell

## Repository etiquette

- PR titles must follow Conventional Commits
- main cannot be pushed to; every change lands through a PR, squash merge only
- Before committing, fetch and integrate the latest remote main, then create a working branch from it
- Write commit messages and PR titles/bodies in English (on squash the PR title becomes, verbatim, the commit title on main, and the messages are concatenated into its body)

## References

Plain links, not @imports, to keep session context small.

- Development flow and PR title format: [README.md](README.md)
- Bilingual documentation rules: [CONTRIBUTING.md](CONTRIBUTING.md)
- Per-job details: [docs/ci-jobs.md](docs/ci-jobs.md)
