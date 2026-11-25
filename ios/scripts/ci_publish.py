#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Publishes a workflow run's results to the orphan branch `ci-results`.

Runs in the `publish-results` job at the end of every iOS workflow. The branch
is a scratch channel: it is rebuilt as a single orphan commit each time and
force-pushed (with a lease), so nothing else ever depends on its history.

Layout written:
  runs/<run_id>/status.json   run id, workflow, branch, sha, per-job conclusions, timestamps
  runs/<run_id>/summary.md    human summary (test counts, failures, memory numbers)
  runs/<run_id>/logs/*.txt    failing-step tails, error excerpts, JSON reports
  runs/<run_id>/screenshots/  simulator / UI-test PNGs
  by-sha/<sha>.json           pointer to the run directory
  sidestore/source.json       SideStore source (kept from the last release job)

Environment: GITHUB_REPOSITORY GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_WORKFLOW
GITHUB_REF_NAME GITHUB_SHA GITHUB_EVENT_NAME GITHUB_SERVER_URL GITHUB_TOKEN
NEEDS_JSON (toJSON(needs)) COLLECTED (directory with the downloaded ci-* artifacts)
"""
import base64
import datetime
import json
import os
import pathlib
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

KEEP_RUNS = 15
BRANCH = "ci-results"
MAX_TEXT = 200_000


def env(name, default=""):
    return os.environ.get(name, default)


REPO = env("GITHUB_REPOSITORY")
RUN_ID = env("GITHUB_RUN_ID")
TOKEN = env("GITHUB_TOKEN")
SHA = env("GITHUB_SHA")
SERVER = env("GITHUB_SERVER_URL", "https://github.com")
API = "https://api.github.com"
AUTH_BASE64 = base64.b64encode(f"x-access-token:{TOKEN}".encode()).decode() if TOKEN else ""
SECRETS = [TOKEN, AUTH_BASE64]


def api_get(path):
    request = urllib.request.Request(
        API + path,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "orangecell-ci-publish",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def fetch_jobs():
    if env("CI_PUBLISH_OFFLINE"):
        return []
    try:
        return api_get(f"/repos/{REPO}/actions/runs/{RUN_ID}/jobs?per_page=100").get("jobs", [])
    except Exception as error:  # noqa: BLE001
        print(f"warning: could not list jobs: {error}")
        return []


def job_log_tail(job_id, lines=400):
    """Last lines of a job's raw log (needs actions: read). curl drops the auth header on the redirect."""
    try:
        result = subprocess.run(
            ["curl", "-sSL", "--max-time", "120", "-H", f"Authorization: Bearer {TOKEN}",
             "-H", "Accept: application/vnd.github+json", f"{API}/repos/{REPO}/actions/jobs/{job_id}/logs"],
            capture_output=True, text=True, errors="replace",
        )
        text = result.stdout
        return "\n".join(text.splitlines()[-lines:]) + "\n"
    except Exception as error:  # noqa: BLE001
        return f"could not fetch log: {error}\n"


def slug(text):
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", text).strip("-").lower() or "job"


def overall(needs):
    results = [v.get("result") for v in needs.values()]
    if any(r == "failure" for r in results):
        return "failure"
    if any(r == "cancelled" for r in results):
        return "cancelled"
    if results and all(r in ("success", "skipped") for r in results):
        return "success"
    return "unknown"


def copy_job_outputs(collected, run_dir, summaries):
    """Copy the small, useful files of every collected job directory."""
    logs_dir = run_dir / "logs"
    shots_dir = run_dir / "screenshots"
    logs_dir.mkdir(parents=True, exist_ok=True)
    shots_dir.mkdir(parents=True, exist_ok=True)
    if not collected.exists():
        return
    for job_dir in sorted(p for p in collected.iterdir() if p.is_dir()):
        job = job_dir.name.removeprefix("ci-")
        # Each job uploads its own ci-out/<job> directory as artifact ci-<job>.
        inner = job_dir
        if not (inner / "summary.md").exists() and not (inner / "logs").exists():
            candidates = list(job_dir.rglob("summary.md")) + list(job_dir.rglob("steps.tsv"))
            inner = candidates[0].parent if candidates else job_dir
        summary = inner / "summary.md"
        if summary.exists():
            summaries.append(summary.read_text(encoding="utf8", errors="replace"))
        for pattern in ("logs/*.tail.txt", "logs/*.errors.txt", "logs/*.json", "logs/ui-*.txt", "logs/*-failures.txt",
                        "logs/prefs-*.txt", "logs/footprint-*.txt", "logs/vmmap-*.txt", "logs/sim-*.txt", "logs/crash-*",
                        "logs/toolchain.txt", "logs/ipa-info.txt", "logs/*.md"):
            for file in inner.glob(pattern):
                if file.is_file() and file.stat().st_size > 0:
                    data = file.read_bytes()[-MAX_TEXT:]
                    (logs_dir / f"{job}--{file.name}").write_bytes(data)
        for file in (inner / "screenshots").glob("*.png") if (inner / "screenshots").exists() else []:
            shutil.copy2(file, shots_dir / f"{job}--{file.name}")
        for name in ("steps.tsv", "e2e.md"):
            if (inner / name).exists():
                shutil.copy2(inner / name, logs_dir / f"{job}--{name}.txt")


def shrink_screenshots(directory):
    if not shutil.which("convert") and not shutil.which("magick"):
        return
    tool = ["magick"] if shutil.which("magick") else ["convert"]
    for png in directory.glob("*.png"):
        if png.stat().st_size > 400_000:
            subprocess.run(tool + [str(png), "-resize", "50%", str(png)], check=False)


class GitError(RuntimeError):
    """A git failure whose message never contains the command line or a credential."""


def redact(text):
    for secret in SECRETS:
        if secret:
            text = text.replace(secret, "***")
    return text


def git_environment(authenticated):
    """Credentials go through the environment, never through argv (argv shows up in logs)."""
    environment = dict(os.environ)
    environment["GIT_TERMINAL_PROMPT"] = "0"
    if authenticated:
        environment.update({
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "http.https://github.com/.extraheader",
            "GIT_CONFIG_VALUE_0": f"AUTHORIZATION: basic {AUTH_BASE64}",
        })
    return environment


def git(*args, cwd=None, authenticated=False, check=True):
    command = ["git"] + (["-C", str(cwd)] if cwd else []) + list(args)
    result = subprocess.run(command, capture_output=True, text=True, env=git_environment(authenticated))
    if check and result.returncode != 0:
        raise GitError(f"git {args[0]} failed (exit {result.returncode}): {redact(result.stderr).strip()[-300:]}")
    return result


def main():
    for secret in SECRETS:
        if secret:
            print(f"::add-mask::{secret}")
    needs = json.loads(env("NEEDS_JSON", "{}") or "{}")
    collected = pathlib.Path(env("COLLECTED", "ci-collected"))
    jobs = fetch_jobs()
    conclusion = overall(needs)
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    job_rows = []
    failed_logs = {}
    for job in jobs:
        if job.get("name", "").startswith("publish-results"):
            continue
        job_rows.append({
            "name": job.get("name"),
            "id": job.get("id"),
            "status": job.get("status"),
            "conclusion": job.get("conclusion"),
            "started_at": job.get("started_at"),
            "completed_at": job.get("completed_at"),
            "url": job.get("html_url"),
            "steps": [{"name": s.get("name"), "conclusion": s.get("conclusion")} for s in job.get("steps", [])],
        })
        if job.get("conclusion") in ("failure", "cancelled", "timed_out"):
            failed_logs[job.get("name")] = job_log_tail(job.get("id"))
    if not job_rows:  # API unavailable: fall back to the needs context
        for name, value in needs.items():
            job_rows.append({"name": name, "conclusion": value.get("result"), "steps": []})

    status = {
        "run_id": int(RUN_ID) if RUN_ID.isdigit() else RUN_ID,
        "run_number": env("GITHUB_RUN_NUMBER"),
        "workflow": env("GITHUB_WORKFLOW"),
        "event": env("GITHUB_EVENT_NAME"),
        "branch": env("GITHUB_REF_NAME"),
        "head_sha": SHA,
        "conclusion": conclusion,
        "url": f"{SERVER}/{REPO}/actions/runs/{RUN_ID}",
        "published_at": now,
        "jobs": job_rows,
    }

    summaries = []
    work = pathlib.Path(tempfile.mkdtemp(prefix="ci-results-"))
    stage = pathlib.Path(tempfile.mkdtemp(prefix="ci-stage-"))
    run_dir = stage / "runs" / RUN_ID
    run_dir.mkdir(parents=True)
    copy_job_outputs(collected, run_dir, summaries)
    for name, text in failed_logs.items():
        (run_dir / "logs" / f"{slug(name)}--joblog-tail.txt").write_text(text, encoding="utf8")
    shrink_screenshots(run_dir / "screenshots")

    header = [
        f"# {status['workflow']} — run {RUN_ID} (#{status['run_number']}) — **{conclusion}**",
        "",
        f"- commit `{SHA}` on `{status['branch']}` ({status['event']})",
        f"- {status['url']}",
        "",
        "| job | conclusion | duration |",
        "| --- | --- | --- |",
    ]
    for row in job_rows:
        duration = ""
        if row.get("started_at") and row.get("completed_at"):
            fmt = "%Y-%m-%dT%H:%M:%SZ"
            seconds = (datetime.datetime.strptime(row["completed_at"], fmt) - datetime.datetime.strptime(row["started_at"], fmt)).total_seconds()
            duration = f"{int(seconds // 60)}m{int(seconds % 60):02d}s"
        header.append(f"| {row['name']} | {row.get('conclusion') or row.get('status')} | {duration} |")
    for row in job_rows:
        failed = [s["name"] for s in row.get("steps", []) if s.get("conclusion") == "failure"]
        if failed:
            header.append("")
            header.append(f"**{row['name']}** failed in step(s): " + ", ".join(failed))
    header.append("")
    (run_dir / "summary.md").write_text("\n".join(header) + "\n" + "\n".join(summaries), encoding="utf8")
    (run_dir / "status.json").write_text(json.dumps(status, indent=2, ensure_ascii=False) + "\n", encoding="utf8")

    source_json = None
    for candidate in collected.rglob("source.json") if collected.exists() else []:
        source_json = candidate
        break

    # CI_PUBLISH_GIT_URL lets the script be tried against a local bare repository.
    url = env("CI_PUBLISH_GIT_URL") or f"https://github.com/{REPO}.git"
    authenticated = url.startswith("https://")
    last_error = ""

    # Overlapping workflow runs publish concurrently; the lease makes a lost race fail
    # loudly and the loop re-reads the branch and tries again.
    for attempt in range(1, 13):
        try:
            shutil.rmtree(work, ignore_errors=True)
            work.mkdir(parents=True)
            git("init", "-q", "-b", BRANCH, str(work))
            remote_sha = ""
            listing = git("ls-remote", url, f"refs/heads/{BRANCH}", authenticated=authenticated)
            if listing.stdout.strip():
                remote_sha = listing.stdout.split()[0]
                git("fetch", "-q", "--depth", "1", url, f"refs/heads/{BRANCH}", cwd=work, authenticated=authenticated)
                git("checkout", "-q", "FETCH_HEAD", "--", ".", cwd=work)
            # new run directory
            target = work / "runs" / RUN_ID
            shutil.rmtree(target, ignore_errors=True)
            (work / "runs").mkdir(exist_ok=True)
            shutil.copytree(run_dir, target)
            # retention
            runs = sorted((p for p in (work / "runs").iterdir() if p.is_dir() and p.name.isdigit()), key=lambda p: int(p.name), reverse=True)
            keep = {p.name for p in runs[:KEEP_RUNS]}
            for old in runs[KEEP_RUNS:]:
                shutil.rmtree(old)
            # pointers
            by_sha = work / "by-sha"
            by_sha.mkdir(exist_ok=True)
            for pointer in by_sha.glob("*.json"):
                try:
                    data = json.loads(pointer.read_text(encoding="utf8"))
                    data["runs"] = {k: v for k, v in data.get("runs", {}).items() if str(v.get("run_id")) in keep}
                    if data["runs"]:
                        pointer.write_text(json.dumps(data, indent=2) + "\n", encoding="utf8")
                    else:
                        pointer.unlink()
                except Exception:  # noqa: BLE001
                    pointer.unlink()
            pointer_path = by_sha / f"{SHA}.json"
            pointer = {"sha": SHA, "runs": {}}
            if pointer_path.exists():
                try:
                    pointer = json.loads(pointer_path.read_text(encoding="utf8"))
                except Exception:  # noqa: BLE001
                    pass
            pointer.setdefault("runs", {})[status["workflow"]] = {
                "run_id": status["run_id"], "path": f"runs/{RUN_ID}", "conclusion": conclusion, "published_at": now,
            }
            pointer.update({"run_id": status["run_id"], "path": f"runs/{RUN_ID}", "workflow": status["workflow"],
                            "conclusion": conclusion, "published_at": now})
            pointer_path.write_text(json.dumps(pointer, indent=2) + "\n", encoding="utf8")
            # SideStore source
            if source_json is not None:
                (work / "sidestore").mkdir(exist_ok=True)
                target = work / "sidestore" / "source.json"

                def build_of(path):
                    try:
                        return int(json.loads(path.read_text(encoding="utf8"))["apps"][0]["versions"][0]["buildVersion"])
                    except Exception:  # noqa: BLE001
                        return -1

                # An older run that finishes late must not replace the source of a newer build.
                if target.exists() and build_of(target) > build_of(source_json):
                    print(f"sidestore/source.json already points at build {build_of(target)}, newer than {build_of(source_json)}: kept")
                else:
                    shutil.copy2(source_json, target)
            (work / "README.md").write_text(
                "Scratch branch written by the iOS workflows (ios/scripts/ci_publish.py). "
                "It is rebuilt as one orphan commit per run; do not rely on its history.\n", encoding="utf8")

            # The fresh repository has no history, so this commit is a root commit (an orphan).
            git("add", "-A", cwd=work)
            git("-c", "user.name=github-actions[bot]", "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
                "commit", "-q", "-m", f"ci-results: {status['workflow']} run {RUN_ID} ({conclusion}) {SHA[:12]}", cwd=work)
            lease = f"--force-with-lease=refs/heads/{BRANCH}:{remote_sha}"
            git("push", "-q", lease, url, f"HEAD:refs/heads/{BRANCH}", cwd=work, authenticated=authenticated)
            print(f"published runs/{RUN_ID} to {BRANCH} (attempt {attempt})")
            return 0
        except GitError as error:
            last_error = str(error)
            print(f"publish attempt {attempt} failed: {last_error}")
            time.sleep(random.uniform(1.0, 4.0) * min(attempt, 5))
    print(f"could not publish results: {last_error}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
