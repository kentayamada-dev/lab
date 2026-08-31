# Security policy

## Where to report

**Do not report vulnerabilities in public issues or Discussions.** Publishing the details before a fix exists hands out the attack recipe.

Reports are received through GitHub's **private vulnerability reporting**. Click **Report a vulnerability** on the repository's **Security** tab, fill in the form, and send it. The exchange happens on a private advisory visible only to the reporter and the maintainers; the advisory is published once the fix is out.

**If you cannot find Report a vulnerability**, private reporting is not enabled (the script in [Setup](README.md#setup) enables it). Open an issue saying only that you want to get in touch about a security matter, without any details.

Reference: [Privately reporting a security vulnerability](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)

## What to include in a report

Include whatever you know — partial information is fine. Reproduction steps speed up the investigation.

- The affected area (a workflow, a script, a configuration file, and so on)
- Steps to reproduce, or the conditions under which the attack works
- The expected impact (what becomes readable, writable, or executable)
- The environment you confirmed it in (OS, tool versions, commit SHA)
- Any workaround or fix you are aware of (if any)

## Scope

The scope is **what is in this repository** (the list under [What's included](README.md#whats-included) is exactly the scope).

| Status | Description |
| --- | --- |
| In scope | Over-broad workflow permissions, injection into `run`, leaked secrets, dangerous behavior in the scripts |
| Out of scope | The application code of a repository created from this template (report it to that repository) |
| Out of scope | Vulnerabilities in the tools or actions this template depends on (report them upstream; we pick up fixes through version updates) |
| Out of scope | Anything already surfaced as an alert on the Security tab |

## Supported versions

**Only the latest commit on main.** Because this is a template, fixes are not backported to past commits or releases. To pick up a fix, apply the change from main in the derived repository.

We cannot promise a response time. If two weeks pass with no reply, follow up through the same channel.

## Automated checks

Before reporting, you can use these to see whether something has already been detected. Findings appear under Code scanning on the Security tab. The security-related checks are [CodeQL](docs/ci-jobs.md#codeql), [ghalint](docs/ci-jobs.md#ghalint), [zizmor](docs/ci-jobs.md#zizmor), [gitleaks](docs/ci-jobs.md#gitleaks), [osv-scanner](docs/ci-jobs.md#osv-scanner), and [Scorecard](docs/ci-jobs.md#scorecard); what each looks at is in [CI check jobs](docs/ci-jobs.md#ci-check-jobs).

These checks only cover known patterns and known vulnerabilities. Design flaws and operational gaps sail straight through them, so tell us through the channel above if you notice one.
