# Renovate

**English** | [日本語](renovate.ja.md)

[renovate.yml](../.github/workflows/renovate.yml) runs [Renovate](https://docs.renovatebot.com/) once a week (Monday 09:00 JST) and creates update PRs when newer versions of dependencies are available. It is self-hosted, running [renovate/renovate from Docker Hub](https://hub.docker.com/r/renovate/renovate) as is, rather than using Mend's hosted GitHub App. When there are dependencies that can be updated, a `Dependency updates are available` issue is opened ([The update list issue](#the-update-list-issue)).

The trigger is the cron on the workflow side, so all times involved are UTC (Renovate's own date and time handling is also left at its UTC default). If a `schedule` is ever added to [renovate.json5](../.github/renovate.json5), set `timezone` along with it so its times are not read as UTC.

The image is specified in the job's `container:` and the steps run inside it (no wrapper action is involved). The two gotchas specific to job containers are handled on the workflow side. The container runs with `--user root`, because the image's non-root user cannot write the files the runner creates: neither `$GITHUB_OUTPUT`, through which the job passes what it found to the later jobs, nor the `/github/home` the runner points `HOME` at. And the step sets `shell: bash`, because the default shell for `run:` in a job container is `sh`.

To run it manually:

```bash
gh workflow run renovate.yml
```

(`--field log_level=debug` makes the log verbose.)

## Registering the token

**Nothing happens until the `RENOVATE_TOKEN` secret is registered** (if it is not, the job says so and fails). The token to issue is a fine-grained PAT. Create it in the browser the same way as [`SETTINGS_TOKEN`](drift-check.md#creating-settings_token) (a token name such as `renovate (OWNER/REPO)`), granting the following repository permissions instead (nothing outside this table is needed).

| Permission | Purpose |
| --- | --- |
| Contents: Read and write | Creating branches and pushing |
| Pull requests: Read and write | Creating and updating PRs |
| Workflows: Read and write | Updating files under `.github/workflows/` |
| Issues: Read and write | Opening a warning issue when the configuration has a problem |
| Dependabot alerts: Read-only | Reading the alerts that [Setup](../README.md#setup) enables. At the next run, a dependency with a known vulnerability gets a fix PR of its own, separate from the grouped update (Renovate's `vulnerabilityAlerts`, on by default). When the permission is missing, Renovate only warns and skips this, so the run still succeeds |

Register the token as a secret and run once to confirm (a PR is created if there is an update).

```bash
gh secret set RENOVATE_TOKEN
gh workflow run renovate.yml
gh run watch
```

You cannot tell whether the permissions are right until it runs. If any are missing, the Actions log says which permission is needed.

**The default `GITHUB_TOKEN` is not a substitute.** It cannot rewrite workflow files (and almost everything updated in this repository is a workflow), and on top of that other workflows do not start on a PR created by `GITHUB_TOKEN`, which produces a PR that cannot be merged because the required check `ci` is never reported.

## When a run fails

**When a run fails, an issue is opened** (the `notify` job in [renovate.yml](../.github/workflows/renovate.yml)). If a scheduled failure goes unnoticed, update PRs quietly stop arriving. The usual causes are `RENOVATE_TOKEN` being expired, missing, or lacking permissions ([Registering the token](#registering-the-token)).

The issue is titled `Renovate runs are failing` and gets the `maintenance` label ([Labels](../README.md#labels)); the body holds the run log URL and how to fix it. While the same issue is already open nothing more is created (so it does not pile up weekly), and once a run succeeds it closes automatically.

Creating and closing the issue uses the workflow's `GITHUB_TOKEN` (`issues: write`). `RENOVATE_TOKEN` is deliberately not used, so the notification still works when it has expired.

**The automatic disabling of the schedule cannot be caught by this notification.** GitHub [disables the schedule after 60 days without repository activity](ci-jobs.md#when-the-scheduled-run-stops), and since no run happens, no issue is opened either. GitHub's deactivation email is the only clue (see the comment in [renovate.yml](../.github/workflows/renovate.yml)).

## When a dependency cannot be resolved

**When the latest version of some dependencies could not be fetched, a `Some dependencies cannot be resolved` issue is opened** (the `lookup` job in [renovate.yml](../.github/workflows/renovate.yml)). This failure is quiet: Renovate itself succeeds, update PRs are created normally for the dependencies it could resolve, and only the unresolved ones quietly stop getting updates.

The issue gets the `maintenance` label; the body holds the warning Renovate emitted and the run log URL. While the same issue is already open the body is rewritten (which dependencies fail changes from run to run), and once everything resolves it closes automatically.

The usual causes are `RENOVATE_TOKEN` lacking permissions or being expired ([Registering the token](#registering-the-token)), and a temporary outage at the distribution source. In the latter case the next run fixes it by itself.

The mechanism is scraping the run log. Renovate only writes this warning to the log as `Package lookup failures`; it appears neither in the exit code nor in the PR body (because `warnings` was removed; see [Body](#body)). The `renovate` job saves the log, puts the warning lines that follow it into a job output, and the `lookup` job turns that into an issue. The detection depends on that string alone, so a change in the log format means the details can no longer be extracted, but the issue is still opened in that case (with a body saying to look at the run log).

## The update list issue

**When there are dependencies that can be updated, a `Dependency updates are available` issue is opened** (the `dashboard` job in [renovate.yml](../.github/workflows/renovate.yml)). The scheduled run is only weekly, so a separate signal is needed to notice that an update PR has arrived.

The issue gets the `dependencies` label ([Labels](../README.md#labels)); the body holds the list of PRs and the run log URL. While the same issue is already open the body is rewritten, and once no update PRs remain it closes automatically.

In other words, **there are updates to deal with only while the issue is in the issue list**. That determination only happens during a run, so besides the cron the workflow also runs when Renovate's own update PRs are merged. Merging all the PRs closes the issue in that run.

The list covers open PRs whose branch name starts with `renovate/` (`branchPrefix` is left at its default; the `dependencies` label is not used as the marker because people can apply it too). The issue operations use the workflow's `GITHUB_TOKEN`, not `RENOVATE_TOKEN`. When the run fails this job does not run and the list stays as it was.

### Why the built-in Dependency Dashboard is not used

Renovate has a [Dependency Dashboard](https://docs.renovatebot.com/configuration-options/#dependencydashboard) that collects update status into an issue, but it is turned off with `dependencyDashboard: false`. Its layout cannot be made to match the other automated issues (all the configuration lets you change is the title and the text before and after the body).

Two things are lost in exchange. If the built-in dashboard becomes necessary, removing `dependencyDashboard: false` and dropping the `dashboard` job restores it.

| What is lost | The alternative |
| --- | --- |
| The checkbox controls (create a held-back PR now / rebase and retry / run manually) | Nothing is held back thanks to `prConcurrentLimit: 0` and `prHourlyLimit: 0`. Rebase is Update branch on the PR page, and re-running is `gh workflow run renovate.yml` |
| Detected Dependencies (the list of dependencies picked up as update candidates) | The run log of `gh workflow run renovate.yml --field log_level=debug` |

## PR wording

**The title and body of update PRs are written by hand** ([renovate.json5](../.github/renovate.json5)), so that they read the same way as the other automated issues rather than following Renovate's generated defaults.

### Title

The whole phrase is carried in `commitMessageTopic`, with `commitMessageAction` and `commitMessageExtra` left empty. Renovate concatenates the title as `prefix + action + topic + extra`, so splitting the wording across all of them makes the phrasing hard to control.

| Kind of update | Example title |
| --- | --- |
| A grouped update (the `non-major` group) | `chore(deps): update non-major dependencies` |
| major | `chore(deps): update actions/checkout to v8` |
| Digest only | `chore(deps): update renovate/renovate digest to e49d149` |
| Pinning a version (such as the first run with `pinDigests: true`) | `chore(deps): pin dependency versions` |
| Replacement (when `replacements:all` picks one up) | `chore(deps): replace old with new` |

The `chore(deps):` prefix comes from `semanticCommits: 'enabled'` (a preset included in `config:recommended` makes it `fix(deps):` for the application's own dependencies). The shape of the prefix is unchanged, so CI's [`pr-title`](../README.md#pr-title-format) passes.

`groupSlug` is stated explicitly in `packageRules` so the branch name stays fixed independently of the group name wording. The group name is also used in the branch name (`renovate/non-major`), and if that breaks it also affects the filter used by [The update list issue](#the-update-list-issue) (branches starting with `renovate/`).

### Body

`prBodyTemplate` is set to `{{{header}}}{{{table}}}{{{footer}}}`, which keeps Renovate's table of updates and removes the rest of what Renovate generates. The wording around the table is only what is written in `prHeader` (what to do with the PR, and a note switched with `{{#if isReplacement}}` that appears only on replacement PRs) and `prFooter` (how a stale PR catches up, what closing means, that Renovate created the PR, and where the configuration and this document live).

Five things were removed. To bring one back, just add it to `prBodyTemplate`.

| What was removed | What it was | The replacement |
| --- | --- | --- |
| `notes` | Notes such as rebase instructions | Whatever is needed is written in `prFooter` |
| `warnings` | Configuration warnings and the "some dependencies could not be resolved" notice | A dedicated issue ([When a dependency cannot be resolved](#when-a-dependency-cannot-be-resolved)) |
| `configDescription` | Explanations of schedule / automerge / rebase / ignore | The notes in `prFooter` |
| `controls` | The rebase and retry checkboxes | Update branch on the PR page |
| `changelogs` | The collapsed Release Notes | Read them by following the package name link in the table |

Warnings about the configuration itself are caught by the warning issue Renovate opens on its own (created with the `issues` permission of `RENOVATE_TOKEN`) and by CI's [`renovate-config`](#validating-the-configuration), which fails at PR time.

Since `changelogs` was removed, fetching release notes is turned off too (`fetchChangeLogs: 'off'`), so nothing is fetched on every PR only to be left unshown. When restoring `{{{changelogs}}}`, restore this line along with it (`'pr'` is the default).

### Table

The table listing the updates is Renovate's `table`, with the columns adjusted through `prBodyColumns` and `prBodyDefinitions`. `table` always prepends the sentence `This PR contains the following updates:` and there is no way to remove just that; an earlier revision assembled the table by hand in `prHeader` to avoid it, but its deduplication depended on the ordering of `upgrades`, while `table` folds occurrences of the same update into one row regardless of order, so `table` is used and the fixed sentence accepted.

```text
| Package | Update | Change |
| --- | --- | --- |
| [actions/checkout](https://github.com/actions/checkout) | digest | `a1b2c3d` → `3d3c42e` |
| [jdx/mise](https://github.com/jdx/mise) | patch | `2026.8.8` → `2026.9.1` |
```

- `Update` rewrites only the two pin-related `updateType` values into plain wording (`pin` → `pin version`, `pinDigest` → `pin digest`); every other value (`major` / `minor` / `patch` / `digest`, and so on) is already a plain word and is printed as is.
- The `Type` and `Pending` columns present in Renovate's default table were dropped: `Type` (`depType`) is a manager-side identifier that means little on its own, and `Pending` only carries a value with update-delaying options (such as `minimumReleaseAge`) that this configuration does not use.
- `Change` prints only the new value when there is no old one (when pinning a version, for example).

**Mistakes in the wording are not caught by [Validating the configuration](#validating-the-configuration).** The validator looks at the format of keys and values, not at the result of expanding a template. After changing it, create a real PR with `gh workflow run renovate.yml` and check.

## Labels on PRs and issues

Update PRs get `dependencies` (`labels` in [renovate.json5](../.github/renovate.json5)). [The update list issue](#the-update-list-issue) gets the same label; [Labels](../README.md#labels) covers who creates it and what to keep in step when changing it.

When self-hosting, the PR author is whoever owns `RENOVATE_TOKEN` (usually you), so filtering by `author:app/renovate` as with the hosted version is not possible, which makes this label the only marker.

## Commit author

The author of the commits Renovate creates is stated explicitly with `RENOVATE_GIT_AUTHOR` in [renovate.yml](../.github/workflows/renovate.yml) (the default is `github-actions[bot]`). A fine-grained PAT cannot read the token owner's email address, so Renovate's own automatic detection does not work.

To change it, set a repository variable in `Name <email>` form (the default is used when it is unset).

```bash
gh variable set RENOVATE_GIT_AUTHOR --body 'Renovate Bot <bot@example.com>'
```

## Validating the configuration

[renovate.json5](../.github/renovate.json5) is checked on every PR by the `renovate-config` job in [ci.yml](../.github/workflows/ci.yml). It runs `renovate-config-validator`, which is bundled with Renovate, using the same image as [renovate.yml](../.github/workflows/renovate.yml) as a job container.

A mistake in the configuration is caught by no other check, and CI stays green while update PRs quietly stop arriving. This job makes that fail at PR time instead. `--strict` is set, so even warnings such as deprecated options make it fail. It does not check whether the intended dependencies are being picked up, though. After changing how a version is written, confirm separately with the verbose log (`gh workflow run renovate.yml --field log_level=debug`).

Implementation notes:

- The container runs with `--user root`, for the same reason as [renovate.yml](../.github/workflows/renovate.yml): the image's non-root user cannot write what the runner owns. What fails here is `actions/checkout`, which cannot create files in the working directory.
- No file name is passed to the validator. Passing one switches it into the mode that validates a bot-wide configuration, which would let through options that cannot appear in a repository configuration (`token`, for example). Instead, the job checks that the file exists first, so that renaming the configuration file cannot leave the job green with nothing to check.

To run it locally, use the same image as CI (the tag can be the latest; CI pins it to a digest and Renovate itself proposes the updates).

```bash
docker run --rm -v "$PWD:/repo:ro" -w /repo \
  --entrypoint renovate-config-validator \
  renovate/renovate --strict
```

## Settings tailored to this repository

These are the points where [renovate.json5](../.github/renovate.json5) differs from the defaults. Renovate works without any of them, but dropping one either adds manual work or departs from the intent of this setup.

| Setting | Reason | If dropped |
| --- | --- | --- |
| `semanticCommits: 'enabled'` | Makes PR titles `chore(deps): ...` so they pass [`pr-title`](../README.md#pr-title-format) | It falls back to the default `auto` (inferred from history), and a wrong inference makes `pr-title` fail so the PR cannot be merged |
| `rebaseWhen: 'behind-base-branch'` | Being up to date before merging is required, so PRs follow along once the base moves ahead | Bringing a PR whose base moved ahead up to date becomes manual work (Update branch) |
| `prHourlyLimit: 0` | The run is weekly, so nothing should be carried over by the default limit of two per hour | The third and later PRs are carried over to next week's run |
| `prConcurrentLimit: 0` | Every update becomes a PR, so that [The update list issue](#the-update-list-issue) is a complete list | Once more than 10 are open the rest are held back and do not appear in the list |
| `dependencyDashboard: false` | Turns off the built-in dashboard and uses a hand-rolled issue for the list ([why](#why-the-built-in-dependency-dashboard-is-not-used)) | A `Dependency Dashboard` issue is opened, duplicating the hand-rolled one |
| `pinDigests: true` | Tags can be re-pointed, so pin all the way to the digest ([Pinning digests](#pinning-digests)) | Only the tag is specified, and a swap of the contents can no longer be tracked |
| `helpers:pinGitHubActionDigestsToSemver` in `extends` | Keeps the comment beside a pinned SHA at an exact version such as `# v7.0.1` ([Pinning digests](#pinning-digests)) | A moving major tag such as `# v7` is written, and once upstream re-points it the comment no longer names the pinned commit, which [`zizmor`](ci-jobs.md#zizmor) reports as `ref-version-mismatch` |
| `non-major` in `packageRules` | Groups everything except major into a single PR | A PR is opened per update and the count grows |
| The `commitMessage*` / `pr*` wording | Writes the title and body of update PRs by hand ([PR wording](#pr-wording)) | It reverts to the generated default wording, which does not match the automated issues |
| `fetchChangeLogs: 'off'` | Release notes are not shown in the PR, so they are not fetched ([Body](#body)) | Release notes that are never displayed are fetched on every run |

## What gets updated

| How it is written | How it is picked up |
| --- | --- |
| `uses: actions/checkout@<commit sha> # v7.0.1` | The github-actions manager (automatic) |
| `uses: <owner>/<repo>/.github/workflows/<name>.yml@<commit sha> # v2.5.1` | Same as above (automatic) |
| `uses: docker://<image>:<tag>@sha256:...` | Same as above (automatic) |
| A job's `container:` — `image: <image>:<tag>@sha256:...` | Same as above (automatic) |
| `[tools]` in [mise.toml](../mise.toml) | The mise manager (automatic) |
| The `version` input of `jdx/mise-action` | The github-actions manager (automatic) |

Everything is written in a form Renovate reads out of the box, and no `customManagers` are used. Specify Docker images with `uses: docker://` or a job's `container:`. Nothing picks up an image name written directly inside `run:`.

Files such as `package.json` and `go.mod` added along with application code are detected automatically by the preset (`config:recommended`), so no extra configuration is needed.

## Pinning digests

With `pinDigests: true`, actions and Docker images are pinned to a digest in addition to a tag. Because the contents behind a tag can be swapped later, a tag alone does not determine what CI actually runs. With the digest pinned, the contents change only when a Renovate PR is merged.

| Target | Update |
| --- | --- |
| An action, a reusable workflow | Renovate maintains both the SHA and the trailing comment |
| A `docker://` image, a job's `container:` | Renovate updates both the tag and the digest |

Write new jobs in the same form ([What gets updated](#what-gets-updated)). The digest does not have to be added by hand even the first time (Renovate pins it). To add it by hand, fetch it like this:

```bash
gh api repos/actions/checkout/commits/v7.0.1 --jq .sha    # the action's commit SHA
docker buildx imagetools inspect <image>:<tag> --format '{{.Manifest.Digest}}'
```

The tools written in [mise.toml](../mise.toml) have no digest. Instead, mise verifies what it downloads with checksums and signatures ([Installing and verifying the tools](ci-jobs.md#installing-and-verifying-the-tools)).

## Automerge

PRs are not merged automatically in the initial state. For updates where passing `ci` is judged to be enough (patches, for example), adding `automerge: true` to `packageRules` in [renovate.json5](../.github/renovate.json5) makes them merge through the repository's auto-merge feature.
