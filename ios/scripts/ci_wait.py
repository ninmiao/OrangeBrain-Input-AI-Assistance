#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Waits for the CI results of a commit and prints them.

    python ios/scripts/ci_wait.py <sha> [--timeout-min 75] [--remote origin]

The iOS workflows publish their results to the orphan branch `ci-results`
(ios/scripts/ci_publish.py). This script polls that branch with plain `git
fetch` (so it uses the machine's normal git credentials and no API quota) until
by-sha/<sha>.json exists, then prints runs/<run id>/summary.md and unpacks the
run's logs and screenshots into .tools/ci-results/<run id>/ (git-ignored).

While waiting it asks the unauthenticated runs API (at most once every two
minutes, 60 requests/hour are shared) whether every workflow run of that commit
has already finished without publishing, e.g. after a YAML error.

Exit status: 0 all green, 1 results say failure, 2 timeout or run ended without
results, 3 usage / git problems.
"""
import argparse
import io
import json
import pathlib
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request

REPO = "ninmiao/OrangeBrain-Input-AI-Assistance"
BRANCH = "ci-results"
POLL_SECONDS = 30
API_EVERY_SECONDS = 120


def run_git(*args, check=False):
    return subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf8", errors="replace", check=check)


def fetch(remote):
    """Fetches the results branch. Returns True when it exists on the remote."""
    result = run_git("fetch", "--quiet", "--force", remote, f"+refs/heads/{BRANCH}:refs/remotes/{remote}/{BRANCH}")
    if result.returncode == 0:
        return True
    if "couldn't find remote ref" in result.stderr or "Couldn't find remote ref" in result.stderr:
        return False
    print(f"git fetch problem: {result.stderr.strip()[-300:]}", file=sys.stderr)
    return False


def show(ref_path, binary=False):
    result = subprocess.run(["git", "show", ref_path], capture_output=True)
    if result.returncode != 0:
        return None
    return result.stdout if binary else result.stdout.decode("utf8", errors="replace")


def api_runs(sha):
    url = f"https://api.github.com/repos/{REPO}/actions/runs?head_sha={sha}&per_page=20"
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "orangecell-ci-wait"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response).get("workflow_runs", [])
    except (urllib.error.URLError, OSError, ValueError) as error:
        print(f"(runs API unavailable: {error})")
        return None


def newer_running(sha, workflow, known_run_id):
    """Id of a run of `workflow` for this commit that is newer than known_run_id and not finished."""
    runs = api_runs(sha) or []
    for run in runs:
        if (not workflow or run.get("name") == workflow) and run["id"] > known_run_id and run["status"] != "completed":
            return run["id"]
    return None


def unpack(remote, run_path, destination):
    """Extracts runs/<id> from the results branch into destination."""
    result = subprocess.run(["git", "archive", "--format=tar", f"{remote}/{BRANCH}", run_path], capture_output=True)
    if result.returncode != 0:
        print(f"could not archive {run_path}: {result.stderr.decode(errors='replace')}", file=sys.stderr)
        return []
    written = []
    with tarfile.open(fileobj=io.BytesIO(result.stdout)) as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            relative = pathlib.PurePosixPath(member.name).relative_to(run_path)
            target = destination / pathlib.Path(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
            written.append(target)
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sha", help="full or abbreviated commit sha")
    parser.add_argument("--timeout-min", type=float, default=75)
    parser.add_argument("--remote", default="origin")
    parser.add_argument("--workflow", default="iOS CI",
                        help="wait for this workflow's results (default: iOS CI); '' accepts whichever run published last")
    parser.add_argument("--not-before-run-id", type=int, default=0,
                        help="ignore published results of this run id or older (use it when the same commit is built again)")
    args = parser.parse_args()

    full = run_git("rev-parse", "--verify", f"{args.sha}^{{commit}}")
    sha = full.stdout.strip() if full.returncode == 0 else args.sha
    if len(sha) < 40:
        print("need a commit known to this clone (or a full 40-character sha)", file=sys.stderr)
        return 3
    print(f"waiting for CI results of {sha} (timeout {args.timeout_min:g} min)")

    deadline = time.time() + args.timeout_min * 60
    last_api = 0.0
    finished_since = None
    announced = ""
    while True:
        if fetch(args.remote):
            raw = show(f"{args.remote}/{BRANCH}:by-sha/{sha}.json")
            if raw:
                pointer = json.loads(raw)
                entry = pointer if not args.workflow else pointer.get("runs", {}).get(args.workflow)
                if entry and int(entry.get("run_id", 0)) > args.not_before_run_id:
                    # A re-run of the same commit may already be under way: the pointer then still
                    # shows the earlier run. Ask the runs API before trusting it.
                    newer = newer_running(sha, args.workflow, int(entry.get("run_id", 0)))
                    if newer:
                        if announced != f"newer:{newer}":
                            print(f"results exist from run {entry.get('run_id')}, but run {newer} of this commit is still in progress; waiting for it")
                            announced = f"newer:{newer}"
                    else:
                        run_path = entry["path"]
                        break
        now = time.time()
        if now - last_api >= API_EVERY_SECONDS:
            last_api = now
            runs = api_runs(sha)
            if runs is not None:
                if not runs:
                    line = "no workflow run for this commit yet (push filters, or still registering)"
                else:
                    line = "; ".join(f"{r['name']}: {r['status']}/{r.get('conclusion') or '-'}" for r in runs)
                if line != announced:
                    print(time.strftime("%H:%M:%S"), line)
                    announced = line
                if runs and all(r["status"] == "completed" for r in runs):
                    finished_since = finished_since or now
                    if now - finished_since > 240:
                        print("every run of this commit has completed but nothing was published to ci-results.")
                        for r in runs:
                            print(f"  {r['name']}: {r.get('conclusion')}  {r['html_url']}")
                        print("Likely a workflow-file error or a failed publish step; open the run page above.")
                        return 2
                else:
                    finished_since = None
        if time.time() > deadline:
            print("timeout waiting for results")
            return 2
        time.sleep(POLL_SECONDS)

    run_id = pathlib.PurePosixPath(run_path).name
    print(f"using the results of run {run_id} (pass --not-before-run-id {run_id} to skip it when the commit is built again)")
    destination = pathlib.Path(".tools") / "ci-results" / run_id
    written = unpack(args.remote, run_path, destination)
    summary = destination / "summary.md"
    print()
    print(summary.read_text(encoding="utf8", errors="replace") if summary.exists() else "(no summary.md)")
    print()
    print(f"results unpacked to {destination.resolve()}")
    logs = sorted(p for p in written if "logs" in p.parts)
    shots = sorted(p for p in written if "screenshots" in p.parts)
    if logs:
        print("logs:")
        for path in logs:
            print(f"  {path.resolve()}")
    if shots:
        print("screenshots:")
        for path in shots:
            print(f"  {path.resolve()}")
    status_file = destination / "status.json"
    conclusion = "unknown"
    if status_file.exists():
        conclusion = json.loads(status_file.read_text(encoding="utf8")).get("conclusion", "unknown")
    print(f"conclusion: {conclusion}")
    return 0 if conclusion == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
