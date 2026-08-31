# repo-baseline

**English** | [日本語](README.ja.md)

[![ci](https://github.com/kentayamada-dev/repo-baseline/actions/workflows/ci.yml/badge.svg)](https://github.com/kentayamada-dev/repo-baseline/actions/workflows/ci.yml) [![OpenSSF Scorecard](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.scorecard.dev%2Fprojects%2Fgithub.com%2Fkentayamada-dev%2Frepo-baseline&query=%24.score&label=openssf%20scorecard)](https://scorecard.dev/viewer/?uri=github.com/kentayamada-dev/repo-baseline)

A template repository providing the groundwork for repository operations: branch protection and a CI workflow built to be extended.

**It contains no application code.** The application itself is built in a repository created from this template ([After adding application code](docs/ci-jobs.md#after-adding-application-code)). **It is for public repositories only** (the conditions for using rulesets and Code scanning differ on private ones).

## How to read this

You only need to read these two sections up front.

- [Setup](#setup) — the one-time work right after creating a repository from the template
- [Development flow](#development-flow) — how PRs are handled day to day

The rest is reference material to look up when you need it.

- [What's included](#whats-included) — the list of files in the repository
- [Settings drift check](docs/drift-check.md#settings-drift-check) — the daily check that repository settings have not drifted from the definitions
- [Releases](#releases) — the constraints immutable releases impose
- [CI check jobs](docs/ci-jobs.md#ci-check-jobs) — look up the relevant section when a check fails or when you add a job
- [Renovate](docs/renovate.md#renovate) — automated dependency updates
- [Troubleshooting](docs/troubleshooting.md#troubleshooting) — look up by symptom

## What's included

| Path | Description |
| --- | --- |
| [.github/rulesets/main.json](.github/rulesets/main.json) | The branch protection definition for main (a GitHub Repository Ruleset) |
| [scripts/sync-repo-config.sh](scripts/sync-repo-config.sh) | A script that applies and checks the ruleset above together with the repository settings |
| [scripts/tests/](scripts/tests) | Tests for the script above, run in CI ([script-tests](docs/ci-jobs.md#script-tests)) |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | CI. The gate job `ci` that serves as the required check, plus the check jobs ([list](docs/ci-jobs.md#ci-check-jobs)) |
| [.github/workflows/osv-scanner.yml](.github/workflows/osv-scanner.yml) | Scheduled scan for known vulnerabilities in dependencies (daily / [osv-scanner](docs/ci-jobs.md#osv-scanner)) |
| [.github/workflows/scorecard.yml](.github/workflows/scorecard.yml) | Scheduled scoring of the repository's security posture with OpenSSF Scorecard (weekly / [Scorecard](docs/ci-jobs.md#scorecard)) |
| [.github/workflows/repo-settings.yml](.github/workflows/repo-settings.yml) | Scheduled check for drift in repository settings and rulesets (daily / [Settings drift check](docs/drift-check.md#settings-drift-check)) |
| [.github/workflows/link-check.yml](.github/workflows/link-check.yml) | Scheduled check of the external links in the documentation (daily / [Scheduled external link checks](docs/ci-jobs.md#scheduled-external-link-checks)) |
| [.github/workflows/renovate.yml](.github/workflows/renovate.yml) | Runs Renovate ([The update list issue](docs/renovate.md#the-update-list-issue)) |
| [.github/scripts/](.github/scripts) | The scripts the scheduled workflows above call to report a failing check as an issue and to retract it |
| [.github/scripts/tests/](.github/scripts/tests) | Tests for the scripts above, run in CI ([script-tests](docs/ci-jobs.md#script-tests)) |
| [.github/renovate.json5](.github/renovate.json5) | Renovate configuration |
| [.github/pull_request_template.md](.github/pull_request_template.md) | The PR body template |
| [.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE) | Issue templates (bug report / task) |
| [CLAUDE.md](CLAUDE.md) | Instructions Claude Code reads. Replace it with the instructions for your own repository |
| [.claude/settings.json](.claude/settings.json) | Claude Code settings, wiring up the hook scripts below |
| [.claude/hooks/](.claude/hooks) | The hook scripts that enforce the rules in CLAUDE.md |
| [.claude/skills/docs-check/SKILL.md](.claude/skills/docs-check/SKILL.md) | The duplication and stale-docs check to run (run as `/docs-check`) |
| [.claude/tests/](.claude/tests) | Tests for the hook scripts and the settings that wire them up, run in CI ([hooks](docs/ci-jobs.md#hooks)) |
| [mise.toml](mise.toml) | Versions of the check tools used in CI, and the tasks that run the same checks locally (`mise run check`) |
| [.markdownlint-cli2.jsonc](.markdownlint-cli2.jsonc) | Configuration for markdownlint-cli2, the Markdown format checker |
| [.typos.toml](.typos.toml) | Configuration for typos, the typo checker |
| [.editorconfig](.editorconfig) | Editor-side formatting settings (indentation / line endings / encoding) |
| [.gitattributes](.gitattributes) | The git setting that fixes line endings to LF |
| [.gitignore](.gitignore) | What git does not track (it also excludes those paths from typos) |
| [docs/drift-check.md](docs/drift-check.md) | Reference: the settings drift check and `SETTINGS_TOKEN` |
| [docs/ci-jobs.md](docs/ci-jobs.md) | Reference: the CI check jobs |
| [docs/renovate.md](docs/renovate.md) | Reference: Renovate |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Reference: troubleshooting |
| [SECURITY.md](SECURITY.md) | Where to report vulnerabilities and what is in scope |
| [CONTRIBUTING.md](CONTRIBUTING.md) | The contributing guide (GitHub shows it on the issue / PR creation pages) |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Code of conduct (based on Contributor Covenant v2.1) |
| [LICENSE](LICENSE) | The MIT license ([License](#license)) |
| `*.ja.md` | The Japanese versions: [README.ja.md](README.ja.md) and the four files under `docs/`. The `.md` of the same name is the English original |

**The English is the authoritative version** ([Bilingual documentation](CONTRIBUTING.md#bilingual-documentation)). Everything a tool emits or matches on stays English-only, which is why this document quotes markers such as `DRIFT` and `UNKNOWN` in English.

## Setup

One-time work to do right after creating your own repository from the template.

1. **Run the setup script** (just below)
2. **Commit the [config.yml](.github/ISSUE_TEMPLATE/config.yml) the script rewrote** ([Issue templates](#issue-templates))
3. **Register the `SETTINGS_TOKEN` secret** ([how to create it](docs/drift-check.md#creating-settings_token)) — without it the [settings drift check](docs/drift-check.md#settings-drift-check) fails with "UNKNOWN" and opens an issue
4. **If you use [Renovate](docs/renovate.md#renovate), register the `RENOVATE_TOKEN` secret** ([how to create it](docs/renovate.md#registering-the-token)) — without it the Monday scheduled run fails and opens an issue

Prerequisites: [gh](https://cli.github.com/) and [jq](https://jqlang.github.io/jq/), with `gh auth login` already done.

```bash
./scripts/sync-repo-config.sh
```

That enables everything below. Add `--dry-run` if you only want to see what would be sent; the other options and environment variables are in `--help`.

- Branch protection on main ([What branch protection enforces](#what-branch-protection-enforces))
- Auto-merge and automatic branch deletion after merging
- The "Update branch" suggestion on PRs that have fallen behind the base (being up to date before merging is required)
- Restricting the merge method to squash only (merge commits / rebase are disabled)
- Always using the PR title as the commit title on squash ([PR title format](#pr-title-format))
- Enabling Discussions, Issues, and Projects (stated explicitly rather than relying on GitHub's defaults)
- Creating only the missing issue and PR labels ([Labels](#labels))
- Disabling the Wiki (it is unused: main protection and CI do not cover it, and it is not copied from a template)
- Immutable releases ([Releases](#releases))
- Private vulnerability reporting (received through a private channel rather than public issues)
- Dependabot alerts (GitHub notifies the moment a known vulnerability is published for a dependency. Unlike the daily [osv-scanner](docs/ci-jobs.md#osv-scanner) scan, it keeps working after scheduled workflows are disabled by 60 days without activity)
- Secret scanning push protection (a push that carries a credential is rejected before it lands, where [gitleaks](docs/ci-jobs.md#gitleaks) only reports what is already in the history)
- Fixing the default permissions of the Actions `GITHUB_TOKEN` to read and forbidding `GITHUB_TOKEN` from creating or approving PRs (so the ceiling when a workflow forgets its `permissions` does not depend on the default)

> The script refuses repositories that are not public.

When applying this to an existing repository, a leftover classic branch protection on main applies alongside the ruleset and makes the behavior hard to follow. The script only warns and continues (`--dry-run` and `--check` do not perform this check), so delete it if it is still there.

```bash
gh api --method DELETE repos/OWNER/REPO/branches/main/protection
```

### What branch protection enforces

| Item | Setting |
| --- | --- |
| Direct push to main | Forbidden |
| PR | Required |
| Approvals | 0 (self-merge allowed) |
| Review threads | All must be resolved before merging |
| CI (`ci`) | Required (only a report from GitHub Actions counts) |
| Code scanning alerts | Block merging on any alert, whatever its severity ([CodeQL](docs/ci-jobs.md#codeql)) |
| Up to date before merging | Required (click Update branch once the base moves ahead) |
| Merge method | Squash only |
| Linear history | Required (no merge commits) |
| Deleting / force-pushing main | Forbidden |

There is a single ruleset, [main.json](.github/rulesets/main.json), and it targets only `main`. Nothing applies to branches other than main, and no bypass is granted, not even to administrators. To change the settings, edit the JSON and run the script again.

Signed commits are not required. The rule reads every commit in the pull request, not just the squash commit GitHub creates and signs on merge, so it would block Renovate's update PRs, whose commits are unsigned.

Zero approvals assumes a single maintainer. Once two or more people work on the repository, change the `pull_request` rule in the JSON: `required_approving_review_count` to 1, and `dismiss_stale_reviews_on_push` and `require_last_push_approval` to `true`. To require a review from the owner of the area that changed, add a `CODEOWNERS` file and turn on `require_code_owner_review` as well.

## Development flow

main is protected and cannot be pushed to directly. Every change lands through a PR.

```bash
git switch -c feat/xxx
# make changes and commit
git push -u origin HEAD
gh pr create
gh pr merge --auto --squash
```

Zero approvals are required, so you can merge your own PR, but nothing merges until CI passes. Adding `gh pr merge --auto --squash` merges automatically as soon as CI passes (squash is the only enabled merge method, and non-interactive runs error out without an explicit method).

The checks CI runs can be reproduced before pushing. With [mise](https://mise.jdx.dev/) installed, the command below runs every check that works from a local checkout, with the same commands and tool versions as CI ([Reproducing the checks locally](docs/ci-jobs.md#reproducing-the-checks-locally)).

```bash
mise run check
```

A PR whose base has moved ahead cannot be merged until it is brought up to date. Click "Update branch" on the PR page, or run `git merge origin/main` and push. CI runs again, and once it passes the PR can be merged.

### PR title format

PR titles are required to follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format.

```text
<type>(<scope>)!: <description>
```

| Element | Required | Description |
| --- | --- | --- |
| `type` | Required | One of `feat` `fix` `docs` `refactor` `test` `build` `ci` `perf` `chore` `revert` |
| `(scope)` | Optional | The area that changed. Written like `fix(cli):` |
| `!` | Optional | Added for a backward-incompatible change. `feat!:` |
| `description` | Required | At least one character |

```text
feat: add a user search endpoint
fix(cli): highlight that config.yml must be committed
feat!: switch the config file format to TOML
```

Titles are constrained because the setting that always uses the PR title as the commit title on squash (`squash_merge_commit_title=PR_TITLE`) means **the PR title becomes the title of the commit that lands on main**. Only the title is constrained; the body is not checked. The commit messages you stacked locally are concatenated into the body of the squash commit and left on main.

The validation is done by CI's `pr-title` job, and since it is part of the required check `ci` it cannot be bypassed. When it fails, fixing the PR title re-runs the check automatically (no new push needed). If you add or remove types, fix the `PATTERN` in [ci.yml](.github/workflows/ci.yml), the table above, and the type list in the prompt hook in [.claude/settings.json](.claude/settings.json) together. The [hooks](docs/ci-jobs.md#hooks) job compares every copy (the failure message in ci.yml included) against the `PATTERN`, so a missed one fails CI.

Re-validation works because `edited` was added to the `types` of `pull_request`. With the default, fixing the title does not start the workflow and it stays failed. The cost is that [CodeQL](docs/ci-jobs.md#codeql) also runs on every title edit, but skipping only `codeql` with an `if` would let the gate job `ci`, which treats `skipped` as a success, paint the previous failure green, so that is not done.

GitHub's default (`COMMIT_OR_PR_TITLE`) uses the commit's own title on a PR with a single commit, so dropping `PR_TITLE` means the title that `pr-title` validated may never land on main. That drift cannot be detected by `pr-title` (it looks at the PR title, not at what actually lands on main); the [settings drift check](docs/drift-check.md#settings-drift-check) catches it. To check locally, run:

```bash
gh api repos/OWNER/REPO --jq .squash_merge_commit_title   # must be PR_TITLE
./scripts/sync-repo-config.sh --check              # checks the other settings and the ruleset too
```

### Consistent formatting

Indentation, line endings, and trailing whitespace are kept consistent by three layers with different degrees of enforcement.

| Mechanism | Enforcement | Role |
| --- | --- | --- |
| [.editorconfig](.editorconfig) | None (a hint) | Gets it right as you type. Silently ignored by editors without the plugin |
| [.gitattributes](.gitattributes) | git normalizes | Fixes line endings to LF. Independent of editor settings and OS |
| The `format` job in `ci` | Required check | Rejects violations on the PR (two tools: editorconfig-checker and shfmt) |

The `format` job checks every item in `.editorconfig` using [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker). `.editorconfig` is the single source of truth; the check items are not copied into CI.

The tab check (`indent_style`) also prevents concrete breakage. YAML cannot use tabs for indentation by specification, so editing `ci.yml` in an environment whose editor defaults to tabs breaks the workflow.

The same job has [shfmt](https://github.com/mvdan/sh) check the formatting of shell scripts.

```bash
git ls-files -z '*.sh' '*.bash' \
  | xargs -0 -r shfmt -d -i 2 -ci
```

| Option | Reason |
| --- | --- |
| `-d` | Print the diff before and after formatting and exit 1 if there is one (it does not rewrite, unlike `-w`) |
| `-i 2` | Indent with 2 spaces |
| `-ci` | Indent the contents of `case` (the existing style in this repository) |

Things to note about shfmt:

- **Passing even one flag makes shfmt ignore `.editorconfig`.** The formatting of shell scripts is decided by these options alone. Options such as `-sr`, which puts spaces around redirects, are left off to match the existing style. To change that, add to these flags.
- **Multiple statements put on one line separated by `;` are rewritten onto separate lines.** One-line guards such as `cmd || { echo "..." >&2; exit 1; }` are expanded too. There is no flag to disable it, so every shell script in the repository is written in that expanded form.

editorconfig-checker and shfmt are installed with mise and run like the other check tools ([Installing and verifying the tools](docs/ci-jobs.md#installing-and-verifying-the-tools), versions in [mise.toml](mise.toml)). **The command name for editorconfig-checker is `ec`** (the `editorconfig-checker` written in [mise.toml](mise.toml) is the package name in the [aqua](https://aquaproj.github.io/) registry, which differs from the binary name).

#### Two exceptions

Shell scripts are excluded from the `indent_size` check (see [.editorconfig](.editorconfig)). The contents of a heredoc are display text printed to the CLI, where aligning the width to a multiple of 2 is meaningless, but editorconfig-checker cannot tell heredoc content apart from code. The excluded files are still covered by shfmt in the same `format` job (shfmt does not format the contents of a heredoc, so it can check without any exclusion). The source of truth for indentation in shell scripts is the shfmt flags, not `.editorconfig`.

`*.md` is excluded from the trailing-whitespace check because in Markdown two trailing spaces mean a hard line break. Removing them uniformly would change the rendering. The excluded files are still covered by `MD009` in markdownlint-cli2 ([markdownlint-cli2](docs/ci-jobs.md#markdownlint-cli2)).

### Issue templates

There are two in [.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE). Both are YAML issue forms. Labels are applied automatically ([Labels](#labels)).

| Template | Purpose | Label applied automatically |
| --- | --- | --- |
| [Bug report](.github/ISSUE_TEMPLATE/bug_report.yml) | Something behaves incorrectly or raises an error | `bug` |
| [Task](.github/ISSUE_TEMPLATE/task.yml) | A feature to add or work that needs doing | `enhancement` |

**Anything that fits neither goes to Discussions.** The issue creation page shows an "Ask in Discussions" link. Once the discussion settles, "Create issue from discussion" on the Discussion page converts it into an issue.

Blank issues are forbidden by `blank_issues_enabled: false` in [config.yml](.github/ISSUE_TEMPLATE/config.yml), so every issue goes through one of the templates. That setting only removes the blank option from the issue creation page, though; the API route (including passing a title and body to `gh issue create`) goes straight through.

**Do not write security problems in issues.** Private vulnerability reporting is enabled, so you can report privately from the Security tab ([SECURITY.md](SECURITY.md)).

Since `contact_links` in `config.yml` only accepts absolute URLs, the template holds `https://github.com/OWNER/REPO/discussions/new/choose`, and the script in [Setup](#setup) rewrites it to the actual repository name. **The rewritten `config.yml` needs to be committed.** Fixing it by hand is fine too; in that case the script does nothing.

The format is checked by the `issue-forms` job in `ci` using [check-jsonschema](https://github.com/python-jsonschema/check-jsonschema). A misspelled `type` or a misplaced `validations` is something GitHub only reveals at run time, and it shows up as **the template disappearing from the issue creation page**. The schema applied is the one from [SchemaStore](https://www.schemastore.org/), bundled with the tool itself, so changes on GitHub's side are picked up by updating the tool version.

The job runs the following. `config.yml` configures the template chooser rather than a form, and its schema is different, so it is checked separately. Both extensions are covered because GitHub accepts `.yml` and `.yaml` alike.

```bash
git ls-files -z '.github/ISSUE_TEMPLATE/*.yml' '.github/ISSUE_TEMPLATE/*.yaml' \
  ':!:.github/ISSUE_TEMPLATE/config.yml' ':!:.github/ISSUE_TEMPLATE/config.yaml' \
  | xargs -0 -r check-jsonschema --builtin-schema vendor.github-issue-forms
git ls-files -z '.github/ISSUE_TEMPLATE/config.yml' '.github/ISSUE_TEMPLATE/config.yaml' \
  | xargs -0 -r check-jsonschema --builtin-schema vendor.github-issue-config
```

Placing no templates at all is a legitimate choice, so when there is nothing to check it passes without checking. The flip side is that moving them out of `.github/ISSUE_TEMPLATE/` turns the job green with nothing to check.

### Labels

The script in [Setup](#setup) creates four labels. None of them are applied by hand.

| Label | Applied to | Where it is applied |
| --- | --- | --- |
| `bug` | Bug report issues | `labels` in [bug_report.yml](.github/ISSUE_TEMPLATE/bug_report.yml) |
| `enhancement` | Task issues | `labels` in [task.yml](.github/ISSUE_TEMPLATE/task.yml) |
| `dependencies` | Renovate update PRs / the update list issue | `labels` in [renovate.json5](.github/renovate.json5) / `--label dependencies` in [renovate.yml](.github/workflows/renovate.yml) |
| `maintenance` | Notification issues opened by failed scheduled checks | `--label maintenance` in each workflow |

`maintenance` exists so that, when browsing issues, bugs reported by people can be distinguished from maintenance work found by automated checks. It expresses the kind of content, not "who created it" (notification issues can be filtered with `author:app/github-actions`).

Labels are applied to notification issues by [upsert-issue.sh](.github/scripts/upsert-issue.sh); why after creation rather than on it — and why a missing label costs only a warning — is explained in its `--help`.

The [settings drift check](docs/drift-check.md#settings-drift-check) verifies daily that the labels have not been deleted (on the issue template side, GitHub silently ignores a nonexistent label, so a deletion goes unnoticed). When changing `labels` in a template or in `renovate.json5`, fix `LABELS_EXPECTED` in the script to match (the check only looks at the definitions in the script).

## Releases

Because immutable releases are enabled, a release published after enabling them cannot be changed afterwards: its assets and its tag are locked, and a fix means publishing a new version ([GitHub's documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) has the details).

The guarantee that the contents behind a given tag never change is a supply-chain safeguard. To disable it, run `gh api --method DELETE repos/OWNER/REPO/immutable-releases`.

## License

MIT ([LICENSE](LICENSE)). Repositories created from this template may replace that file.
