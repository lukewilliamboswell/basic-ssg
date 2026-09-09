#!/usr/bin/env python3
"""Create and validate a signed public-example release follow-up PR."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ("tests.yaml", "release.yml")
REQUIRED_JOBS = ("CI required", "Bundle required")


def run(args: list[str], *, data: str | None = None) -> str:
    return subprocess.run(
        args, cwd=ROOT, input=data, text=True, capture_output=True, check=True
    ).stdout.strip()


def api(endpoint: str, data: object | None = None, method: str | None = None) -> object:
    args = ["gh", "api", endpoint, "-H", "X-GitHub-Api-Version: 2026-03-10"]
    if method:
        args += ["--method", method]
    if data is not None:
        args += ["--input", "-"]
    output = run(args, data=json.dumps(data) if data is not None else None)
    return json.loads(output) if output else None


def publish_status(sha: str, context: str, state: str, target_url: str) -> None:
    api(
        f"repos/{os.environ['GITHUB_REPOSITORY']}/statuses/{sha}",
        {
            "context": context,
            "state": state,
            "description": f"Release follow-up validation {state}",
            "target_url": target_url,
        },
        "POST",
    )


def changed_examples() -> list[str]:
    changed = run(["git", "diff", "--name-only", "--diff-filter=M", "--", "examples"]).splitlines()
    all_changed = run(["git", "diff", "--name-only"]).splitlines()
    if not changed or changed != all_changed:
        raise ValueError(f"Release follow-up must modify only existing example files: {all_changed}")
    if any(
        not re.fullmatch(r"examples/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\.roc", path)
        for path in changed
    ):
        raise ValueError(f"Release follow-up contains an unexpected path: {changed}")
    return changed


def create_signed_commit(version: str, paths: list[str]) -> tuple[str, str]:
    repository = os.environ["GITHUB_REPOSITORY"]
    base = os.environ["GITHUB_SHA"]
    default = os.environ["DEFAULT_BRANCH"]
    live = api(f"repos/{repository}/git/ref/heads/{default}")
    if live["object"]["sha"] != base or run(["git", "rev-parse", "HEAD"]) != base:
        raise ValueError("Default branch moved during release; create the follow-up from current main")
    branch = f"release-followup/{version}"
    refs = api(f"repos/{repository}/git/matching-refs/heads/{branch}")
    if any(item["ref"] == f"refs/heads/{branch}" for item in refs):
        raise ValueError(f"Follow-up branch already exists: {branch}")
    api(f"repos/{repository}/git/refs", {"ref": f"refs/heads/{branch}", "sha": base}, "POST")
    additions = [
        {
            "path": path,
            "contents": base64.b64encode((ROOT / path).read_bytes()).decode(),
        }
        for path in paths
    ]
    request = {
        "query": """mutation($input: CreateCommitOnBranchInput!) {
          createCommitOnBranch(input: $input) { commit { oid } }
        }""",
        "variables": {"input": {
            "branch": {"repositoryNameWithOwner": repository, "branchName": branch},
            "expectedHeadOid": base,
            "message": {"headline": f"Update examples for {version}"},
            "fileChanges": {"additions": additions},
        }},
    }
    response = api("graphql", request, "POST")
    sha = response["data"]["createCommitOnBranch"]["commit"]["oid"]
    commit = api(f"repos/{repository}/commits/{sha}")
    if not commit["commit"]["verification"]["verified"]:
        raise ValueError("GitHub did not verify the release follow-up signature")
    api(
        f"repos/{repository}/pulls",
        {
            "title": f"Update examples for {version}",
            "head": branch,
            "base": default,
            "body": (
                f"Release follow-up for {version}.\n\n"
                "Updates public examples to the exact published platform bundle. "
                "The commit is GitHub-signed and validation is dispatched explicitly."
            ),
        },
        "POST",
    )
    return branch, sha


def validate(branch: str, sha: str) -> None:
    repository = os.environ["GITHUB_REPOSITORY"]
    controller_url = (
        f"{os.environ['GITHUB_SERVER_URL']}/{repository}/actions/runs/"
        f"{os.environ['GITHUB_RUN_ID']}"
    )
    for context in REQUIRED_JOBS:
        publish_status(sha, context, "pending", controller_url)
    runs = []
    try:
        for workflow in WORKFLOWS:
            dispatched = api(
                f"repos/{repository}/actions/workflows/{workflow}/dispatches",
                {"ref": branch, "inputs": {"nightly_validation": True}},
                "POST",
            )
            runs.append({"workflow": workflow, "id": dispatched["workflow_run_id"]})
        deadline = time.monotonic() + 85 * 60
        while True:
            complete = True
            for item in runs:
                result = api(f"repos/{repository}/actions/runs/{item['id']}")
                if result["head_sha"] != sha or result["head_branch"] != branch:
                    raise ValueError("Follow-up validation run identity mismatch")
                item["status"] = result["status"]
                item["conclusion"] = result["conclusion"]
                complete &= result["status"] == "completed"
            if complete:
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Timed out waiting for release follow-up validation")
            time.sleep(30)
        if any(item["conclusion"] != "success" for item in runs):
            raise ValueError(f"Release follow-up validation failed: {runs}")
        successful_jobs = set()
        for item in runs:
            jobs = api(f"repos/{repository}/actions/runs/{item['id']}/jobs?filter=latest&per_page=100")
            successful_jobs.update(
                job["name"] for job in jobs["jobs"]
                if job["status"] == "completed" and job["conclusion"] == "success"
            )
        if not set(REQUIRED_JOBS).issubset(successful_jobs):
            raise ValueError(f"Required aggregate jobs did not pass: {successful_jobs}")
    except BaseException:
        for context in REQUIRED_JOBS:
            publish_status(sha, context, "failure", controller_url)
        raise
    for context in REQUIRED_JOBS:
        publish_status(sha, context, "success", controller_url)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", args.version) is None:
        raise SystemExit(f"Invalid release version: {args.version!r}")
    try:
        paths = changed_examples()
        branch, sha = create_signed_commit(args.version, paths)
        validate(branch, sha)
        print(f"Created and validated signed release follow-up {sha}")
    except (KeyError, OSError, ValueError, TimeoutError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Release follow-up failed: {error}") from None


if __name__ == "__main__":
    main()
