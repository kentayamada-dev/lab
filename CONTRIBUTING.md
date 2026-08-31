# Contributing guide

This page summarizes the entry points for contributing. The details of each procedure live in the README and under docs/, and this page links to the relevant section.

## Where to report and ask

| Topic | Where |
| --- | --- |
| Something behaves incorrectly or raises an error | [Bug report issue](.github/ISSUE_TEMPLATE/bug_report.yml) |
| A feature to add or work that needs doing | [Task issue](.github/ISSUE_TEMPLATE/task.yml) |
| Questions, direction discussions, or anything you cannot classify as a bug or a request | Discussions (there is a link on the issue creation page) |
| A security problem | [SECURITY.md](SECURITY.md) (**do not write it in an issue**) |

For details on choosing between them, see [Issue templates](README.md#issue-templates).

## How changes land

main is protected and every change lands through a PR ([Development flow](README.md#development-flow)). There are three things to know.

- **Write the PR title in Conventional Commits format** ([the format](README.md#pr-title-format)). On a squash merge it becomes, verbatim, the title of the commit that lands on main.
- **Nothing merges until the required CI check `ci` passes** ([the list of check jobs](docs/ci-jobs.md#ci-check-jobs)).
- Indentation, line endings, and trailing whitespace are checked by CI too ([Consistent formatting](README.md#consistent-formatting)).

## Bilingual documentation

[README.md](README.md) and the files under `docs/` exist in two languages: `X.md` is the English original and `X.ja.md` is the Japanese translation. **English is the authoritative version.** When the two disagree, the English one is right and the translation is the thing to fix.

- **Change both sides in the same PR.** No check enforces this — a PR that updates only one side passes — so keeping the pair in step is on you. A change that genuinely needs no counterpart, such as an English typo fix, needs nothing done to the translation.
- **Write the English first**, then bring the translation across. Doing it the other way round leaves the authoritative version trailing the one nobody is supposed to trust.
- **Anchors are per-language.** Each language links within its own set (`docs/ci-jobs.ja.md` links to `../README.ja.md#...`), and the anchors come from the headings, so renaming a heading means fixing that language's links. The `lychee` job catches what you miss.
- **Nothing else is translated.** Anything a tool emits or matches on stays English-only: the notification issue titles (the workflows find an open issue by exact title), the script's `--help` and runtime output, the issue and PR templates, workflow step names, and code comments.

## Code of conduct

The [code of conduct](CODE_OF_CONDUCT.md) applies to all interactions in this repository.
