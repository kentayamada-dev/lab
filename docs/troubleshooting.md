# Troubleshooting

**English** | [日本語](troubleshooting.ja.md)

When a CI job fails, look up the relevant section from the table in [CI check jobs](ci-jobs.md#ci-check-jobs).

## A PR is stuck waiting for a required check

The check named `ci` has not arrived from the expected reporter. Check whether a `paths` filter was added to the workflow, or whether the job name changed from `ci`.

If Actions is green but it keeps waiting, the `integration_id` in [main.json](../.github/rulesets/main.json) disagrees with the actual reporter. Check the `app.id` on the `ci` row with the following command, update the JSON to match, and run the script again.

```bash
gh api repos/OWNER/REPO/commits/main/check-runs --jq '.check_runs[] | "\(.name)\t\(.app.id)\t\(.app.slug)"'
```

## A merge is blocked while CI is green

Two protections other than the required check can hold the merge button ([What branch protection enforces](../README.md#what-branch-protection-enforces)).

- An unresolved review thread. Resolve every thread on the Files changed tab, including the ones you left on your own PR.
- A Code scanning alert, whatever its severity. Open Code scanning on the Security tab and either fix the alert or dismiss it ([CodeQL](ci-jobs.md#codeql)).

## Renovate does not create PRs

Look at the run log of the `renovate` workflow on the Actions tab. Almost always `RENOVATE_TOKEN` is unset, expired, or lacking permissions. If the log alone is not enough, produce a verbose log with `gh workflow run renovate.yml --field log_level=debug`.

When the run succeeds but no PR arrives, look at the `Dependency updates are available` issue ([The update list issue](renovate.md#the-update-list-issue)). If it is not open, there was nothing to update as of the last run (the concurrent PR limit is lifted, so nothing is merely being held back).

## The scheduled osv-scanner run does not fire

GitHub automatically disables schedule triggers after 60 days without repository activity. Open the `osv-scanner` workflow on the Actions tab and re-enable it if it is disabled ([details](ci-jobs.md#when-the-scheduled-run-stops)).

If it runs but detects nothing, drop `--allow-no-lockfiles` from `scan-args` and run it once. If no lockfile could be read at all the job fails, so you find out on the spot whether something is being missed ([details](ci-jobs.md#it-passes-silently-when-there-is-nothing-to-scan)).

## A greyed-out `osv-scanner` appears on the PR

That is the `1 configuration not found` warning. It is normal and does not block the merge. The reason for it, and the reason it is left in place, are in [The "1 configuration not found" shown on PRs](ci-jobs.md#the-1-configuration-not-found-shown-on-prs).

## CI is broken and main cannot be fixed

Setting `enforcement` in [main.json](../.github/rulesets/main.json) to `disabled` and running the script again lifts the protection temporarily. Set it back to `active` once things are restored.
