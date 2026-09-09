# Roc nightly updates

This repository checks once daily at 13:25 UTC, about four hours after the
upstream build. Exact compiler authority lives in the `roc` fields of the roots
listed by `.github/roc-nightly.json`; there is no `.roc-version`.

The caller and configuration workflows pin `roc-automation` to
`5c1f09b7190118f43eb901eaed0110cd53029199`. Candidate validation dispatches
`tests.yaml` and `release.yml` with `nightly_validation: true`. These paths test
published examples, current source, and release bundles without publishing or
deploying anything.

Automatic merging is enabled with `auto_merge: true`. The active `main` ruleset:

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

Follow the shared [package maintainer guide](https://github.com/lukewilliamboswell/roc-automation/blob/5c1f09b7190118f43eb901eaed0110cd53029199/docs/package-maintainer-guide.md)
and [integration guide](https://github.com/lukewilliamboswell/roc-automation/blob/5c1f09b7190118f43eb901eaed0110cd53029199/docs/integration.md).
