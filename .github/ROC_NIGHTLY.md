# Roc nightly updates

This repository checks once daily at 13:25 UTC, about four hours after the
upstream build. Exact compiler authority lives in the `roc` fields of the roots
listed by `.github/roc-nightly.json`; there is no `.roc-version`.

The caller and configuration workflows pin `roc-automation` to
`19c8c1a3f780d648b85678bd31cf735d3584eb01`. Candidate validation dispatches
`tests.yaml` and `release.yml` with `nightly_validation: true`. These paths test
published examples, current source, and release bundles without publishing or
deploying anything.

Automatic merging uses the updater's default-on policy. Set `auto_merge: false`
to opt out. The active `main` ruleset:

- requires pull requests;
- requires the `CI required` and `Bundle required` GitHub Actions contexts;
- uses strict, up-to-date required checks;
- requires zero approvals and gives the Actions bot no bypass; and
- blocks force pushes and branch deletion and retains signature protection.

The controller immediately squash-merges only a verified, single-commit,
pin-literal-only bot PR after both dispatched workflows pass. It never approves
itself, queues a later
merge, merges source changes, or needs the repository-wide GitHub auto-merge
setting. Disable the caller workflow for an emergency stop.

Before relying on unattended updates, inspect the effective rules with
`gh api repos/lukewilliamboswell/basic-ssg/rules/branches/main`, manually dispatch
one successful update, confirm the signed candidate and exact run SHAs, exercise
a no-op, and retain evidence that a failed candidate stays open. The reserved
branch `automation/roc-nightly` must contain no human work.

Follow the shared [package maintainer guide](https://github.com/lukewilliamboswell/roc-automation/blob/19c8c1a3f780d648b85678bd31cf735d3584eb01/docs/package-maintainer-guide.md)
and [integration guide](https://github.com/lukewilliamboswell/roc-automation/blob/19c8c1a3f780d648b85678bd31cf735d3584eb01/docs/integration.md).
