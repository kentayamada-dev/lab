# CI check jobs

**English** | [日本語](ci-jobs.ja.md)

The list of check jobs present in [ci.yml](../.github/workflows/ci.yml) in the initial state. When a check fails or you change a setting, read only the relevant section.

| Job | What it looks at | Section |
| --- | --- | --- |
| `codeql` | Static analysis of the code (workflow files only in the initial state) | [CodeQL](#codeql) |
| `pr-title` | Whether the PR title is in Conventional Commits format | [PR title format](../README.md#pr-title-format) |
| `format` | Indentation, line endings, trailing whitespace | [Consistent formatting](../README.md#consistent-formatting) |
| `actionlint` | Syntax and expression errors in workflow definitions | [actionlint](#actionlint) |
| `shellcheck` | Shell-script patterns that misbehave silently | [shellcheck](#shellcheck) |
| `hadolint` | Dockerfile patterns that cost you reproducibility, size, or privilege | [hadolint](#hadolint) |
| `typos` | Typos | [typos](#typos) |
| `lychee` | Broken links and broken anchors in Markdown | [lychee](#lychee) |
| `markdownlint` | Markdown formatting | [markdownlint-cli2](#markdownlint-cli2) |
| `ghalint` | Workflow security (how they are written) | [ghalint](#ghalint) |
| `zizmor` | Workflow security (attack paths) | [zizmor](#zizmor) |
| `gitleaks` | Secrets that crept into the commit history | [gitleaks](#gitleaks) |
| `setup-script` | That the run-once scripts actually run | [setup-script](#setup-script) |
| `hooks` | That the Claude Code hooks still allow and refuse what CLAUDE.md says | [hooks](#hooks) |
| `script-tests` | That the scripts the workflows call still decide the same way | [script-tests](#script-tests) |
| `issue-forms` | Whether the issue forms follow the schema | [Issue templates](../README.md#issue-templates) |
| `renovate-config` | Validation of the Renovate configuration | [Validating the configuration](renovate.md#validating-the-configuration) |
| `osv-scanner-diff` | Vulnerabilities in dependencies the PR newly introduces | [osv-scanner](#osv-scanner) |

Checks whose result can change without any code change (the [settings drift check](drift-check.md#settings-drift-check), the full scan in [osv-scanner](#osv-scanner), the [external link check](#scheduled-external-link-checks), [Scorecard](#scorecard)) would stop unrelated PRs if they were part of `ci`, so they are scheduled runs in separate workflows.

## Adding a job to CI

The `ci` job in [ci.yml](../.github/workflows/ci.yml) is a gate job that aggregates the results of all the other jobs. `ci` is the only required status check, so **adding a job just means adding it to `ci`'s `needs`** — no change on the branch protection side is needed.

```yaml
jobs:
  lint:   # the job you added
    ...
  test:   # the job you added
    ...
  ci:
    needs: [lint, test]   # add it here
```

Forgetting to add it to `needs` is checked by the `ci` job itself (it compares the job list in ci.yml against `needs`) and fails the PR that forgot; the error message explains the risk.

Note that `ci` treats `skipped` jobs as successes. Skipping with a job-level `if` does not block the PR, but the flip side is that such a skip can paint a previous failure green.

Things to note:

- Always write `permissions` and `timeout-minutes` on a job, and add `persist-credentials: false` to `actions/checkout`. [`ghalint`](#ghalint) enforces this. The exception is a job that calls a reusable workflow with `uses`, where `timeout-minutes` cannot be written ([`osv-scanner-diff`](#osv-scanner) is one).
- Where possible, put the job's command in a `check:<job>` task in [mise.toml](../mise.toml) and have the job run that, so the check stays reproducible locally ([Reproducing the checks locally](#reproducing-the-checks-locally)).
- Do not add a `paths` filter to the whole workflow. On an out-of-scope PR, `ci` is never reported and the PR stays unmergeable, waiting for the required check. To narrow the scope, use a job-level `if`.
- When renaming the `ci` job, change `context` in [main.json](../.github/rulesets/main.json) to match.
- **Do not make CI report from anything other than GitHub Actions.** Alongside `context`, `integration_id` (GitHub Actions' App ID) is specified, and a check of the same name reported by another App or token is ignored. When migrating to an external CI, this value has to change to the new App ID as well, or the PR gets stuck waiting for the required check ([how to check](troubleshooting.md#troubleshooting)).
- CI runs twice per change (on the PR, and on main after the merge). Each time the base is brought up to date, the PR side runs again. Account for that cost when adding a long-running job. The run on main produces the "analysis result for the default branch" that CodeQL uses as the baseline for alerts.
- Consecutive pushes to the same PR cancel the older run, but **pushes to main do not** (`cancel-in-progress` under `concurrency` is set to `github.event_name == 'pull_request'`). If consecutive merges cancelled the run for an earlier commit, that commit would be left with `cancelled` and its [CodeQL](#codeql) analysis would be missing.

## After adding application code

Along with adding lint / test / build jobs to `ci`'s `needs` ([Adding a job to CI](#adding-a-job-to-ci)), revisit the three things below that assume "there is no application code yet".

- Add the language to `matrix.language` for [CodeQL](#codeql)
- Revisit the [CodeQL](#codeql) alert thresholds. Both are `all`, so even a note-level quality alert blocks a merge. That is bearable while the workflow files are the only target, but it turns noisy once a real language is analyzed
- Drop `--allow-no-lockfiles` from [osv-scanner](#osv-scanner) ([It passes silently when there is nothing to scan](#it-passes-silently-when-there-is-nothing-to-scan))

A lockfile (`package-lock.json`, `go.mod`, and so on) is detected by osv-scanner and [Renovate](renovate.md#renovate) with no configuration as soon as it is added.

## Installing and verifying the tools

The CLI tools used for the checks are installed with [mise](https://mise.jdx.dev/) and run directly, even for tools that have an official action or Docker image. That keeps [mise.toml](../mise.toml) as the single source of truth for versions. Updates are proposed as PRs by [Renovate](renovate.md#renovate) (the mise manager is supported out of the box).

There are three exceptions, each explained in its own section. [osv-scanner](#osv-scanner) calls the official reusable workflow, [renovate-config](renovate.md#validating-the-configuration) uses the validator bundled with the Renovate image, and [markdownlint-cli2](#markdownlint-cli2) uses the official action.

mise resolves the download source from the [aqua](https://aquaproj.github.io/) registry, and what it downloads is verified against whatever checksums or signatures the distributor provides before use. That plays the same role as [pinning digests](renovate.md#pinning-digests): a swap or tampering fails at install time. How strong the verification is depends on the distributor.

| Tool | Verification |
| --- | --- |
| ghalint | SLSA provenance (an attestation signed by the release workflow) and checksums |
| actionlint / hadolint / zizmor | GitHub Artifact Attestations (a signed attestation attached to the release) and checksums |
| editorconfig-checker / gitleaks | Checksums only (the release carries neither provenance nor attestations) |
| shellcheck / shfmt / typos | None (the release carries neither checksums nor signatures; all that can be pinned is the version) |
| bats | None (what is installed is the source archive GitHub generates from the tag; the release carries no assets, so nothing beyond the version pins it) |
| lychee | None (the release does carry a `.sha256`, but the aqua registry has no configuration for it so no verification runs) |
| check-jsonschema | Only the file hash PyPI returns (it does not go through aqua; see below) |

`check-jsonschema` is written in Python and is not in aqua, so [mise.toml](../mise.toml) states the backend explicitly as `"pipx:check-jsonschema"` and installs it from PyPI. PyPI does not allow replacing an already published file, so pinning the version determines the contents. What actually runs it is the Python and pipx in the runner image, so there is no need to add `python` to `mise.toml`. Note, though, that **check-jsonschema requires Python 3.10 or newer** (the system Python on macOS is 3.9). In an environment with only an older Python, this one tool cannot be installed.

The version of mise itself is pinned with the `version` input of [mise-action](https://github.com/jdx/mise-action) (Renovate reads that input out of the box). The action itself is pinned to a commit SHA like the others. There is no `mise.lock` (see the comment in [mise.toml](../mise.toml) for why).

Cache writes are limited to pushes to main with `cache_save: ${{ github.event_name == 'push' }}`. Caches are branch-scoped, and one saved on a PR branch lingers for seven days after the merge without anyone using it. The cache on main is readable from every branch, so PRs that do not touch [mise.toml](../mise.toml) still hit it and lose no speed.

### Reproducing the checks locally

The commands the check jobs run are defined once, as tasks in [mise.toml](../mise.toml) named after the jobs, and each job's `run:` step calls its task with `mise run --skip-tools check:<job>` (the flag keeps mise from installing every tool in mise.toml — the job's mise-action step already installed what its task needs). The same tasks reproduce CI at your desk, with [mise](https://mise.jdx.dev/) as the only prerequisite:

```bash
mise run check              # every check that works from a local checkout
mise run check:shellcheck   # one job's check
```

The first run installs the pinned tools; the results match CI because both sides read the same commands and versions from the same file. Two caveats: [zizmor](#zizmor) runs offline without a `GITHUB_TOKEN` in the environment, so its online audits are skipped with a warning, and [gitleaks](#gitleaks) needs the full history a shallow clone does not have.

The jobs with no task are those that cannot run from a local checkout alone: [CodeQL](#codeql) and `pr-title` need the GitHub side, [setup-script](#setup-script) needs a token and the API, and [markdownlint-cli2](#markdownlint-cli2), [renovate-config](renovate.md#validating-the-configuration), and [osv-scanner](#osv-scanner) are the three exceptions above that do not run through mise.

## CodeQL

The `codeql` job in [ci.yml](../.github/workflows/ci.yml) performs static analysis, and the results appear under Code scanning on the Security tab. It is in `ci`'s `needs`, so a failed analysis makes the PR unmergeable. However, **the job does not fail merely because an alert was found** (`analyze` only uploads the results). Merges are blocked by branch protection instead: the `code_scanning` rule in [main.json](../.github/rulesets/main.json) stops a merge on any alert, whatever its severity (both `alerts_threshold` and `security_alerts_threshold` are `all`). Adjust those two there to change how strict it is. For an alert you have judged not to be a problem, dismiss it under Code scanning on the Security tab; the merge is no longer blocked.

In the initial state the only analysis target is `actions` (the workflow files themselves). Once you add application code, add it to `matrix.language`.

```yaml
    strategy:
      matrix:
        language: [actions, javascript-typescript]
```

Which languages can be specified, and which of them additionally need a `build-mode`, is in [CodeQL's supported languages](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/).

Things to note:

- **It cannot be combined with default setup.** This template uses the advanced setup style, where you own the workflow. If default setup is enabled on the repository, turn it off first.

  ```bash
  gh api repos/OWNER/REPO/code-scanning/default-setup --jq .state
  gh api --method PATCH repos/OWNER/REPO/code-scanning/default-setup -f state=not-configured
  ```

- On a PR from a fork, `security-events: write` is not granted and uploading the analysis results may fail (unverified). Check this once you start accepting outside PRs, and if it fails, add an `if` to the job to skip it for fork PRs (`skipped` counts as a success in `ci`). In that case, changes from a fork are first analyzed by the run on main after the merge. Skipping the job also leaves the `code_scanning` rule in [main.json](../.github/rulesets/main.json) with no CodeQL results to judge, so check whether the merge is still allowed, and drop that rule as well if it is not.

## actionlint

The `actionlint` job in [ci.yml](../.github/workflows/ci.yml) checks the workflow definitions themselves. References to nonexistent contexts, type errors in expressions, wrong action input names — flaws you would not notice until the workflow runs — are caught at PR time. It covers everything under `.github/workflows/` with no arguments needed.

How the shell checks divide up: **`run:` inside a workflow is covered by actionlint (and the shellcheck it calls), `*.sh` / `*.bash` in the repository by the [shellcheck](#shellcheck) job, and `RUN` in a Dockerfile by [hadolint](#hadolint) (and the ShellCheck bundled with it)**.

**This job installs shellcheck alongside actionlint**, because actionlint silently skips checking `run:` when shellcheck is not on PATH. Likewise, once you start writing Python in `run:`, add pyflakes to [mise.toml](../mise.toml) and to `install_args`.

## shellcheck

The `shellcheck` job in [ci.yml](../.github/workflows/ci.yml) checks the `*.sh` / `*.bash` files under git. Unquoted variable expansions, unintended word splitting, comparisons that are always true — the kind of flaw that raises no error and misbehaves silently. It does not look at formatting (indentation and so on); that is the job of shfmt in the [`format`](../README.md#consistent-formatting) job.

```bash
git ls-files -z '*.sh' '*.bash' \
  | xargs -0 -r shellcheck --color=always --external-sources
```

| Option | Reason |
| --- | --- |
| `git ls-files` | Do not check untracked files (local throwaway scripts and so on) |
| `-z` / `-0` | Pass file names NUL-separated so names containing spaces do not break |
| `-r` | Do not start shellcheck when there is nothing to check |
| `--external-sources` | Follow files pulled in with `source` |

Scripts without an extension (files identified only by a shebang) are out of scope. If you add one, add a pattern to `git ls-files`.

## hadolint

The `hadolint` job in [ci.yml](../.github/workflows/ci.yml) checks the Dockerfiles under git. An unpinned base image tag (`FROM node:latest`), an `apt-get install` without a version, a final `USER` left as root — in short, **constructs that `docker build` accepts but that cost you reproducibility, size, or privilege**. The shell written in `RUN` is covered too, by the bundled ShellCheck, from the same angle as the [shellcheck](#shellcheck) job.

```bash
git ls-files -z '*Dockerfile' '*Dockerfile.*' '*.dockerfile' \
  | xargs -0 -r hadolint
```

The reasons for `git ls-files` / `-z` / `-0` are the same as in [shellcheck](#shellcheck). `-r` is there because hadolint reads stdin as a Dockerfile when it is given no file name, and an empty invocation should be avoided.

**hadolint does not walk directories; the files to check must be passed by name.** The patterns above pick up `Dockerfile` / `Dockerfile.dev` / `api.Dockerfile` / `web.dockerfile` and the like, including in subdirectories. If you use another name, such as `Containerfile`, add a pattern.

There is no color option because hadolint has no way to force color (CI logs, not being a tty, come out uncolored).

The rules, the severity threshold (`-t`, `info` and above by default), and how to suppress a finding are in [hadolint's Rules](https://github.com/hadolint/hadolint#rules). There is no `.hadolint.yaml` in the initial state.

### It passes silently while there is no Dockerfile

This template has no Dockerfile yet, so this job succeeds without checking anything (`xargs -r` never starts hadolint and nothing appears in the log). Adding a Dockerfile brings it into scope automatically from that point. Note that "nothing to check" and "checked and found nothing" are hard to tell apart in the log (the same as [osv-scanner](#osv-scanner)).

## typos

The `typos` job in [ci.yml](../.github/workflows/ci.yml) checks the whole repository for typos. Code, comments, documentation, and file names are covered, and it only flags words that are in its **dictionary of common misspellings**, such as `recieve` → `receive`. A word that is not in the dictionary (a proper noun or an abbreviation) passes silently, so it does not drown you in false positives. Text in other languages is not covered.

The configuration lives in [.typos.toml](../.typos.toml). Two things are set in the initial state.

```toml
[files]
ignore-hidden = false
```

**typos skips files and directories starting with `.` by default.** Without turning that off, all of `.github/` would be out of scope. `.git` itself is listed in [.gitignore](../.gitignore), so it is excluded by the default behavior of honoring gitignore.

The other is `extend-ignore-re`, which excludes the misspelling example in this section (without it, typos flags this very file).

Suppressions for false positives go in the same file ([all options](https://github.com/crate-ci/typos/blob/master/docs/reference.md)).

## lychee

The `lychee` job in [ci.yml](../.github/workflows/ci.yml) checks Markdown for broken links. Most of the links in this repository are anchors to headings and relative paths to files in the repository, and they break silently when a heading is renamed or a file is moved. This job fails the PR for that.

```bash
lychee --offline --include-fragments --no-progress .
```

| Option | Reason |
| --- | --- |
| `--offline` | Exclude everything but the `file` scheme (= no network access) |
| `--include-fragments` | Also match the `#anchor` inside the target file |
| `--no-progress` | Drop the progress bar for non-interactive shells |
| `.` | Walk the repository root recursively (excluding what is in [.gitignore](../.gitignore)) |

**This job does not check external URLs.** With `--offline` removed, a temporary outage or a rate limit at the far end would fail CI and turn it red for reasons unrelated to the code. External URLs are covered by a scheduled run in a separate workflow ([Scheduled external link checks](#scheduled-external-link-checks)).

Anchors are matched against the IDs lychee generates from headings. The generation rules match GitHub's rendering, Japanese headings included — the text becomes the ID as-is (`#### Two exceptions` → `#two-exceptions`, `#### 2 つの例外` → `#2-つの例外`; the second and later headings with the same wording get `-1`, `-2`).

### Scheduled external link checks

External URLs are checked by [link-check.yml](../.github/workflows/link-check.yml) daily (08:00 JST), on pushes to main, and manually (`workflow_dispatch`). It is the same lychee, in a different role.

| | The `lychee` job in `ci` | The `link-check` workflow |
| --- | --- | --- |
| What it looks at | Relative paths and heading anchors inside the repository | External URLs |
| Network | No (`--offline`) | Yes |
| Anchor matching | Yes | No |
| Required check | Yes (part of `ci`) | No (a separate workflow) |
| On failure | The PR cannot be merged | An issue is opened |

```bash
lychee --no-progress --exclude 'OWNER/REPO' .
```

In CI, `--mode plain` is added and the output goes through `tee` so it can be put into the issue body without ANSI escapes.

It is not part of `ci` because link targets disappear without anything happening on our side and a temporary outage makes it fail (= the result changes without a code change). Making it a required check would stop unrelated PRs for as long as a link target is down.

**Anchors are not checked** (`--include-fragments` is not passed). The heading IDs of an external page are decided by whatever renders it (GitHub prefixes README headings with `user-content-`), so it would only produce false positives. Anchors inside the repository are covered on the `ci` side.

`--exclude 'OWNER/REPO'` (a regular expression) excludes the nonexistent URL used as an example in the documentation. The pattern is not the URL itself because lychee also scans the workflow file, so writing `https://...` there would be picked up as a link. Add any permanently uncheckable URL here in the same way. A temporary outage is absorbed by the default `--max-retries` (3).

`GITHUB_TOKEN` is passed. lychee checks github.com links through the GitHub API, so without it the unauthenticated rate limit makes existing links fail.

Failure notification uses [the same mechanism as the settings drift check](drift-check.md#notification-on-failure). An issue titled `External links are broken` is opened with the `maintenance` label, and once fixed it closes automatically on the next run. Being a scheduled run, it also [stops when there is no activity](#when-the-scheduled-run-stops).

## markdownlint-cli2

The `markdownlint` job in [ci.yml](../.github/workflows/ci.yml) checks Markdown formatting. Skipped heading levels, code blocks without a language — writing that renders fine but is not consistent — are caught (typos are handled by [typos](#typos), broken links by [lychee](#lychee)).

The rules applied live in [.markdownlint-cli2.jsonc](../.markdownlint-cli2.jsonc) ([the list of rules](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)). **What gets checked is decided by the `globs` the job passes, not by that file.** The action's default only looks at the repository root, so `**/*.md` is stated explicitly. Forgetting to pass it silently leaves out everything under `.github/`.

Four things differ from the defaults.

| Rule | Change | Reason |
| --- | --- | --- |
| `MD009` (trailing whitespace) | `strict` | Hard line breaks (two trailing spaces) are not used |
| `MD013` (line length) | 1000 characters for body text (headings and tables inherit the same limit), 120 for code blocks | Body text is written one paragraph per line rather than wrapped (just below). Code blocks cannot be wrapped, and a long one turns into a horizontal scroll |
| `MD041` (first line is an h1) | Disabled | [pull_request_template.md](../.github/pull_request_template.md) is pasted as part of a PR body, where not starting with an h1 is correct |
| Notation styles (`MD003` `MD004` `MD029` `MD046` `MD048` `MD049` `MD050`) | Fixed to concrete values instead of `consistent` | `consistent` only aligns things within a single file |

**Body text is written one paragraph per line, with no line breaks inside a paragraph.** Markdown renders a newline inside a paragraph as a space (in Japanese text that surfaces as a stray space in the middle of the rendered sentence), so wrapping is a rendering decision rather than a source one, and keeping a paragraph on one line keeps diffs paragraph-sized — fixing a word does not reflow every line after it. That is why the body limit of `MD013` is raised to 1000 characters.

Trailing whitespace is covered by `MD009`. What [.editorconfig](../.editorconfig) leaves out by excluding `*.md` ([the exceptions](../README.md#two-exceptions)) is filled in here.

**This job alone uses the official [action](https://github.com/DavidAnson/markdownlint-cli2-action) rather than going through mise**, because markdownlint-cli2 is only distributed on npm and installing it with mise would also require a separate node to run it. The version used for the check is the one bundled with the action, and the action is pinned to a commit SHA.

## ghalint

The `ghalint` job in [ci.yml](../.github/workflows/ci.yml) checks workflow definitions **from a security angle**. Over-broad permissions, leftover tokens — configurations that work but are dangerous — fail the check. Even within that same security angle it covers different ground than [zizmor](#zizmor), so both are included.

The policies are listed in [ghalint's documentation](https://github.com/suzuki-shunsuke/ghalint#policies). The ones you will hit when adding a job — `permissions` and `timeout-minutes` on every job, `persist-credentials: false` on `actions/checkout` — are covered in [Adding a job to CI](#adding-a-job-to-ci). Action references must also be 40-character commit SHAs, and `secrets: inherit` and workflow-level or job-level secret envs are forbidden.

`persist-credentials: false` is what removes the token checkout leaves in `.git/config`. Leaving it there makes it readable from every later step, including any Docker image that runs in one. If you add a job that needs to push, make an exception for just that job in `ghalint.yaml`.

```yaml
excludes:
  - policy_name: checkout_persist_credentials_should_be_false
    workflow_file_path: .github/workflows/ci.yml
    job_name: format
```

It covers everything under `.github/workflows/`. Once you add a composite action (`action.yaml`), make sure `ghalint run-action` is run as well (`run` alone does not check it).

## zizmor

The `zizmor` job in [ci.yml](../.github/workflows/ci.yml) checks workflow definitions **from an attacker's point of view**. Where [ghalint](#ghalint) looks at how they are written, this looks at the attack paths that arise from combinations of expressions and triggers.

The audits are listed in [zizmor's documentation](https://docs.zizmor.sh/audits/): template injection (`${{ }}` embedded directly in `run:`), dangerous triggers such as `pull_request_target`, excessive permissions, unpinned actions and images, and more.

Two audits that check pinned SHAs and used actions against the GitHub API (`impostor-commit`, `known-vulnerable-actions`) are silently skipped without a token. The job passes `github.token` as `GITHUB_TOKEN` to enable them (`contents: read` is enough, since only public information is referenced).

It covers the repository root (`.`) and automatically collects composite actions and the Dependabot configuration as well. `--strict-collection` is set, so a file it cannot parse becomes a failure rather than a warning it passes over.

Suppressing a finding, and the pedantic persona that adds stylistic suggestions to the findings with real impact reported by default, are covered in [zizmor's documentation](https://docs.zizmor.sh/).

## gitleaks

The `gitleaks` job in [ci.yml](../.github/workflows/ci.yml) looks for secrets that crept into the commit history (API keys, access tokens, private keys, and so on). A secret that has been pushed once can be recovered from the history even after a later commit removes it, so **it has to be stopped before it lands**. The first line of defense is secret scanning push protection, which the setup script enables ([Setup](../README.md#setup)): GitHub rejects the push itself. This job is the second line, covering what push protection does not recognize and any history that predates it, and it stops such a commit before the merge. It is in `ci`'s `needs`, so a detection makes the PR unmergeable.

Detection uses the 200-plus rules built into the tool (per-provider regular expressions plus entropy analysis of the value) ([the default configuration](https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml)).

It scans the entire history. `gitleaks git` uses `git log -p` internally, so `fetch-depth: 0` is added to `actions/checkout` to avoid a shallow clone (at the default depth of 1, a value in an older commit would be missed).

```bash
gitleaks git --redact --verbose --no-banner
```

`--redact` keeps the detected value itself out of the log. Run logs are public on a public repository, so without it the check itself would become a leak path. `--verbose` prints where it was found (commit / file / line / rule ID / fingerprint).

### When something is detected

**Revoke the value first** (reissue the key, revoke the token). Treat it as something others could already have obtained the moment it was pushed; rewriting history can wait. Then remove the value from the repository and change it to be passed through an environment variable or GitHub Secrets.

Excluding a false positive (a dummy value used in a test, for example) is done with a `# gitleaks:allow` comment, a `.gitleaksignore`, or a `.gitleaks.toml`, all covered in [gitleaks' documentation](https://github.com/gitleaks/gitleaks).

## setup-script

The `setup-script` job in [ci.yml](../.github/workflows/ci.yml) actually runs the script from [Setup](../README.md#setup) with `--dry-run`. [shellcheck](#shellcheck) is a static check, so a mistyped variable name passes it. The script is run exactly once, right after the repository is created, and if it is broken the person who finds out is whoever created a repository from the template. Its one and only execution path is exercised in CI.

`--dry-run` is read-only and changes nothing: the script only prints what it would send. A broken `.github/rulesets/*.json` fails here, so a JSON syntax error in a ruleset is caught on the PR as well. The job also confirms that the `--help` output is not empty (the help is carved out of the comment at the top of the script with awk, so removing the comment silently empties it).

`gh` and `jq` ship with GitHub-hosted runners, so they are not added to [mise.toml](../mise.toml). The workflow's `GITHUB_TOKEN` is enough for authentication.

This job does not run on a private repository (the setup script refuses anything but public, so running it would always fail). A skip counts as a success in `ci`, so PRs are not blocked on a private repository either.

## hooks

The `hooks` job in [ci.yml](../.github/workflows/ci.yml) runs the [bats](https://bats-core.readthedocs.io/) tests in [.claude/tests/](../.claude/tests) against the hook scripts next to them in [.claude/hooks/](../.claude/hooks). A hook is a filter — the tool call arrives as JSON on stdin, the verdict leaves as JSON on stdout — so one test feeds one command and reads the verdict back.

```bash
git ls-files -z '.claude/tests/*.bats' \
  | xargs -0 -r bats --print-output-on-failure
```

What the tests are for is the borders, not the obvious cases: a commit that creates its branch first is allowed while the same commit without the branch is denied, and `git log | grep push` is not a push. Those borders are matched textually rather than by parsing the shell, so the false positives that come with it (a quoted `echo "git commit"` is denied all the same) are asserted too — a failure there means the behaviour moved, not that it improved.

The wiring is tested too, because a hook is only ever reached through [.claude/settings.json](../.claude/settings.json): a script renamed without the setting, a hook registered under an event it does not answer with, and a hook script with no test file of its own each fail the job — none of them would fail a test of the scripts alone.

So is the content of the prompt hook. The Conventional Commits type list is written out in [ci.yml](../.github/workflows/ci.yml) (the `PATTERN` and the failure message beside it), in the tables of both READMEs, and in the prompt hook, and nothing derives one copy from another, so the tests compare each copy against the `PATTERN` — the one the `pr-title` job actually enforces.

The tests for the branch rule create a throwaway repository under the bats temporary directory, so their verdict never depends on the branch the runner happens to be on. `jq` ships with GitHub-hosted runners and is what the hooks themselves call, so bats is the only addition to [mise.toml](../mise.toml).

The tests live under `.claude/` rather than in a `tests/` directory of their own, so that deleting the hooks takes their tests out with them, and so that the repository built from the template keeps the obvious place for its own tests free. `-r` is what keeps this job green afterwards: with no `.bats` file left, bats is never started. Delete the job along with the hooks if you drop them.

## script-tests

The `script-tests` job in [ci.yml](../.github/workflows/ci.yml) runs the [bats](https://bats-core.readthedocs.io/) tests in two directories, each against the scripts next to them. [.github/scripts/tests/](../.github/scripts/tests) covers [.github/scripts/](../.github/scripts) — the two the scheduled workflows call to report a failing check as an issue and to retract it once the check passes. [scripts/tests/](../scripts/tests) covers [sync-repo-config.sh](../scripts/sync-repo-config.sh) in [scripts/](../scripts) — the script whose OK / DRIFT / UNKNOWN verdicts the [settings drift check](drift-check.md#settings-drift-check) relies on.

```bash
git ls-files -z '.github/scripts/tests/*.bats' 'scripts/tests/*.bats' \
  | xargs -0 -r bats --print-output-on-failure
```

The tests replace `gh` with a stub (the `helper.bash` next to them explains how), so nothing reaches GitHub and no token is needed — which is what makes the decisions around those calls (the ones each script's `--help` describes) testable at all. This job reaches what [setup-script](#setup-script) cannot: a dry run stops before any verdict or write, so the OK / DRIFT / UNKNOWN classification of `--check` and the apply path are only exercised here.

Being reachable by a test is the reason this logic sits in `.github/scripts/` rather than inline in the workflows. A `run:` block can only be exercised by triggering the workflow around it, and for these that means waiting for a scheduled check to fail.

As with [hooks](#hooks), bats is the only addition to [mise.toml](../mise.toml). [shellcheck](#shellcheck) and [format](../README.md#consistent-formatting) pick the scripts up without being told, because both walk `git ls-files` over `*.sh` and `*.bash`.

## osv-scanner

osv-scanner checks for **known vulnerabilities in dependency packages**. It queries the packages and versions written in lockfiles against [OSV](https://osv.dev), a vulnerability database. Where [CodeQL](#codeql) looks at defects in the code you wrote, this looks at known defects in dependencies other people wrote.

The same tool is split into two layers with different roles.

| | What it looks at | Where | On a detection |
| --- | --- | --- | --- |
| Diff scan | Only the vulnerabilities **the PR newly introduces** | The `osv-scanner-diff` job in [ci.yml](../.github/workflows/ci.yml) (per PR) | The job fails (it is in `ci`'s `needs`, so the PR cannot be merged) |
| Full scan | Known vulnerabilities across all dependencies | [osv-scanner.yml](../.github/workflows/osv-scanner.yml) (daily + pushes to main + manual) | An alert under Code scanning on the Security tab (the job does not fail) |

The reason for the split is that this check's result changes without any code change. Vulnerabilities are disclosed later, so the full picture is tracked by a scheduled run. Making that a required check on PRs would stop unrelated PRs over a vulnerability already on main, so the PR side looks only at the diff and fails on that. This two-layer arrangement is the setup [the official action](https://github.com/google/osv-scanner-action) recommends.

### It is handled differently from the other CLI tools

Both layers call the officially distributed reusable workflow as-is. The tool is not installed with mise and is not listed in [mise.toml](../mise.toml). The diff comparison is done by a separate tool (osv-reporter) rather than osv-scanner itself, so installing just the main tool cannot reproduce it, and aligning only one layer with the official workflow would leave two version streams, so something that passed on the PR could get flagged by the scheduled run.

Two costs are accepted:

- The version is not pinned in this repository. Keeping up happens as updates to `@<commit sha>`, which [Renovate](renovate.md#renovate) picks up.
- The same check cannot be reproduced locally.

### Full scan (scheduled)

[osv-scanner.yml](../.github/workflows/osv-scanner.yml) has three triggers.

| | Trigger | Purpose |
| --- | --- | --- |
| `schedule` | Daily 06:00 JST | Notice newly disclosed vulnerabilities |
| `push` (main) | Merging a PR that touched dependencies | Produce results without waiting for the next scheduled run. Creates the "analysis result for the default branch" that Code scanning alerts are measured against |
| `workflow_dispatch` | Manual | Confirming things right after a configuration change |

```yaml
  osv-scanner:
    permissions:
      contents: read
      actions: read
      security-events: write
    uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@<commit sha> # v<tag>
    with:
      scan-args: |-
        -r
        --allow-no-lockfiles
        ./
      fail-on-vuln: false
```

`fail-on-vuln: false` is set (the default is `true`). Detections show up as Code scanning alerts, so the job is not failed. Failing it would turn things red every day over the same vulnerability, with no way to record "handled" or "watching" individually. Alerts are updated on every run, and the alert for a fixed vulnerability closes automatically. To be notified, watch the repository and enable Code scanning alert notifications.

When the run itself fails — as opposed to finding vulnerabilities — the `notify` job opens an issue titled `osv-scanner runs are failing` with the `maintenance` label, using [the same mechanism as the settings drift check](drift-check.md#notification-on-failure), and once a run passes it closes automatically. Without the issue the failure would be invisible: a scan that found nothing and a scan that never ran look the same from the Security tab.

### Diff scan (on PRs)

The `osv-scanner-diff` job in [ci.yml](../.github/workflows/ci.yml) scans both the base and the PR, takes the difference, and fails on vulnerabilities present only on the PR side (`fail-on-vuln: true`). A vulnerability already on main does not fail it. Detections appear both as annotations in the run log and in Code scanning. Fixing them works [the same way as for the full scan](#how-to-fix-it-and-how-to-write-an-exception).

Things to note:

- **`timeout-minutes` cannot be written** (the exception covered in [Adding a job to CI](#adding-a-job-to-ci)). The limit becomes GitHub's default of six hours. The same applies to the full scan.
- On a PR from a fork, `security-events: write` is not granted and the SARIF upload may fail (the same story as [CodeQL](#codeql)). Once you start accepting outside PRs, pass `upload-sarif: false` (the diff determination and the job's pass/fail keep working).
- On `push` (= a merge) there is no base to compare against, so it is skipped (`skipped` counts as a success in `ci`).

### The "1 configuration not found" shown on PRs

An entry named **`osv-scanner` (GitHub Advanced Security)** appears in the PR's check list, greyed out (`neutral`) with a `1 configuration not found` warning. **This state is normal and does not block the merge** (the only required check is the gate job `ci`).

To report "the alerts this PR newly introduces", Code scanning matches the base-side and head-side analysis results for each configuration present on the base (identified as "workflow file : job name"). The full scan (`osv-scanner.yml:osv-scan`) does not run on PRs, so there is no head-side result and it says it cannot judge that configuration. It is the natural consequence of the two-layer arrangement, and it does not go away once a lockfile is added.

Removing it would mean adding `pull_request` to the `on` of [osv-scanner.yml](../.github/workflows/osv-scanner.yml), which is deliberately not done. All it buys is turning the grey entry green, at the price of scanning all dependencies twice on every PR and undermining [the reason for the two layers](#osv-scanner). Aligning the SARIF category so the two look like one configuration is not possible either, because the official reusable workflow has no category input.

For what it is worth, no official GitHub documentation explaining this warning could be found. The above was confirmed from the check's actual conclusion (`neutral`) and the run conditions of the two configurations. The conclusion can be inspected with:

```bash
gh api repos/OWNER/REPO/commits/<sha>/check-runs \
  --jq '.check_runs[] | select(.name == "osv-scanner") | {conclusion, title: .output.title}'
```

### How to fix it and how to write an exception

**Bump to the fixed version first.** The report names the version that contains the fix, so upgrading to that version makes the finding disappear (bumping by hand is sometimes faster than waiting for a [Renovate](renovate.md#renovate) update PR).

When you cannot bump right away, or on a false positive, exclude it individually in an `osv-scanner.toml` ([the configuration format](https://google.github.io/osv-scanner/configuration/)). **Always give the exception a deadline** (`ignoreUntil`, or `effectiveUntil` when excluding a whole package). Without one the exception is permanent, and nobody notices when a fixed version ships.

Only a configuration file in the same directory as the file being scanned takes effect; it does not propagate into subdirectories. In a layout with lockfiles in subdirectories where you want one file at the root to apply to everything, add `--config=osv-scanner.toml` to `scan-args`.

### It passes silently when there is nothing to scan

What it reads is the lockfiles and manifests committed to the repository ([the list of supported formats](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/)). `-r` is set, so it walks subdirectories too.

This template has no readable lockfile at all, so nothing is being checked yet. Checking begins the moment a lockfile is added, with no configuration to add.

When there is nothing to scan, osv-scanner fails with exit code 128 rather than silently succeeding having scanned nothing. Both invocations therefore pass **`--allow-no-lockfiles`** to allow that state explicitly (without it the callee emits a deprecation warning, which will eventually turn CI red).

The cost is that "nothing was checked" no longer surfaces as a warning. **Drop this flag once you add dependencies.** With it dropped, "no readable lockfile at all" becomes a job failure, catching an oversight such as putting the lockfile in `.gitignore` on the spot.

### When the scheduled run stops

GitHub automatically disables schedule triggers after 60 days without repository activity (the owner is notified). When it stops, re-enable it from the Actions tab. Keep in mind that on a quiet repository, the check stops silently.

### Where queries are sent

By default the package names and versions are sent to [api.osv.dev](https://osv.dev) for matching (the source code is not sent). If you want nothing to leave the runner, add `--offline-vulnerabilities` (with `--download-offline-databases` for the first fetch) to `scan-args` to match against a vulnerability database downloaded onto the runner.

## Scorecard

[OpenSSF Scorecard](https://github.com/ossf/scorecard) scores **the repository's security posture as a whole** on a 0–10 scale against a public set of checks: branch protection, token permissions, dependency pinning, dangerous workflow patterns, and so on. The other checks each guard one kind of artifact; Scorecard grades the combination, so a regression that no individual check owns still surfaces.

[scorecard.yml](../.github/workflows/scorecard.yml) has the same three triggers as the [osv-scanner full scan](#full-scan-scheduled), except the schedule is weekly (Tuesday 05:00 JST) — the score follows settings and workflow definitions, which change far less often than vulnerability disclosures. Findings appear under Code scanning on the Security tab as the `Scorecard` tool.

**Findings do not block merges**: the `code_scanning` rule in [main.json](../.github/rulesets/main.json) names only CodeQL. Scorecard findings are graded advice about posture, not defects in the change at hand, so they are reviewed from the Security tab and adopted deliberately rather than enforced per PR.

### The published score and the workflow restrictions

`publish_results: true` sends the score to the public [Scorecard API](https://scorecard.dev), where anyone can view it at `https://scorecard.dev/viewer/?uri=github.com/OWNER/REPO`. To show it in the README, add a badge:

```markdown
[![OpenSSF Scorecard](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.scorecard.dev%2Fprojects%2Fgithub.com%2FOWNER%2FREPO&query=%24.score&label=openssf%20scorecard)](https://scorecard.dev/viewer/?uri=github.com/OWNER/REPO)
```

The badge reads the score from the API through shields.io's dynamic JSON badge, because the plain badge endpoint (`https://api.scorecard.dev/projects/github.com/OWNER/REPO/badge`) redirects to a badge that still queries a retired API host and renders an error instead of the score. The cost is that the score is not colour-coded by value.

In exchange, the API [restricts how the producing workflow may be written](https://github.com/ossf/scorecard-action#workflow-restrictions): the steps of the `analysis` job are limited to an approved list of actions, and the job can carry no `env`, containers, or services. **Adding a step to that job — installing a tool with mise, for example — makes publishing fail** (it surfaces through the issue below). Put anything extra in a separate job; `notify` already is one.

### Two checks that cannot reach full marks

- **Branch-Protection** — reading the full protection settings requires admin access, and the workflow runs with the default `GITHUB_TOKEN`, which has none. Scorecard scores what is publicly visible and stops there. Registering another long-lived admin token is not worth the difference: the settings themselves are already verified daily by the [settings drift check](drift-check.md#settings-drift-check).
- **CII-Best-Practices** — scores holding an [OpenSSF Best Practices badge](https://www.bestpractices.dev/), which is an application to an external program, not a repository setting.

### When the run fails

When the run itself fails — the Scorecard API being down, or an edit that broke the restrictions above — the `notify` job opens an issue titled `scorecard runs are failing` with the `maintenance` label, using [the same mechanism as the settings drift check](drift-check.md#notification-on-failure), and once a run passes it closes automatically.
