#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes the human summary fragment (summary.md) of one CI job.

    ci_summary.py core-linux  --out DIR
    ci_summary.py build-test  --out DIR [--xcresult PATH]
    ci_summary.py ipa         --out DIR

DIR is the job's CI_OUT directory (logs/, screenshots/, steps.tsv ...). Every
number reported is read from files the job produced; nothing is assumed.
"""
import argparse
import json
import pathlib
import re
import subprocess

EXECUTED = re.compile(r"Executed (\d+) tests?, with (\d+) failures? \((\d+) unexpected\)")


def read(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf8", errors="replace")
    except OSError:
        return ""


def steps_table(out: pathlib.Path) -> str:
    rows = []
    for line in read(out / "steps.tsv").splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            name, code, seconds = parts
            rows.append(f"| {name} | {'ok' if code == '0' else 'FAILED (' + code + ')'} | {seconds}s |")
    if not rows:
        return ""
    return "| step | result | time |\n| --- | --- | --- |\n" + "\n".join(rows) + "\n"


def xctest_total(text: str):
    """Total of the last 'Executed N tests' line (XCTest prints one per suite and a grand total)."""
    last = None
    for match in EXECUTED.finditer(text):
        last = match
    if not last:
        return None
    return int(last.group(1)), int(last.group(2))


def ocinfo(text: str) -> dict:
    info = {}
    for line in text.splitlines():
        match = re.search(r"OCINFO (\S+?)=(.*)$", line)
        if match:
            info[match.group(1)] = match.group(2).strip()
    return info


def xcresult_summary(path: pathlib.Path, out: pathlib.Path, name: str):
    """Test totals and failure messages from an .xcresult (Xcode 16+ xcresulttool)."""
    if not path or not path.exists():
        return None, []
    summary = None
    failures = []
    try:
        raw = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(path), "--compact"],
            capture_output=True, text=True, timeout=120, check=True,
        ).stdout
        (out / "logs" / f"{name}-summary.json").write_text(raw, encoding="utf8")
        summary = json.loads(raw)
    except Exception as error:  # noqa: BLE001 - diagnostics only
        failures.append(f"xcresulttool summary failed: {error}")
    try:
        raw = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(path), "--compact"],
            capture_output=True, text=True, timeout=120, check=True,
        ).stdout
        tree = json.loads(raw)

        def walk(node, trail):
            if isinstance(node, dict):
                label = node.get("name", "")
                kind = node.get("nodeType", "")
                if kind == "Failure Message":
                    failures.append(f"{' / '.join(trail)}: {label}")
                for child in node.get("children", []) or []:
                    walk(child, trail + ([label] if kind in ("Test Case", "Test Suite", "Unit test bundle", "UI test bundle") else []))
            elif isinstance(node, list):
                for item in node:
                    walk(item, trail)

        walk(tree, [])
    except Exception as error:  # noqa: BLE001
        failures.append(f"xcresulttool tests failed: {error}")
    if failures:
        (out / "logs" / f"{name}-failures.txt").write_text("\n".join(failures) + "\n", encoding="utf8")
    return summary, failures


def core_linux(out: pathlib.Path) -> str:
    lines = ["#### core-linux"]
    ctest = read(out / "logs" / "native-core-test.log")
    match = re.search(r"(\d+) native truncation/format/envelope cases passed", ctest)
    lines.append(f"- native-core C++ test (CMake, with the C API cases): {match.group(1) + ' cases passed' if match else 'no result'}")
    swift = xctest_total(read(out / "logs" / "swift-test-linux.log"))
    lines.append(f"- OCCore `swift test` on Linux: {f'{swift[0]} tests, {swift[1]} failures' if swift else 'no result'}")
    lines.append("")
    lines.append(steps_table(out))
    return "\n".join(lines)


def build_test(out: pathlib.Path, xcresult: pathlib.Path) -> str:
    lines = ["#### build-test (macos-26)"]
    toolchain = read(out / "logs" / "toolchain.log").strip().splitlines()
    if toolchain:
        lines.append("- toolchain: " + "; ".join(l.strip() for l in toolchain[:3]))

    unit_log = read(out / "logs" / "unit-tests.log")
    summary, failures = xcresult_summary(xcresult, out, "unit")
    if summary and "totalTestCount" in summary:
        lines.append(
            f"- app unit tests (OrangeCellTests, simulator): {summary.get('passedTests', '?')} passed, "
            f"{summary.get('failedTests', '?')} failed, {summary.get('skippedTests', 0)} skipped "
            f"of {summary.get('totalTestCount', '?')}"
        )
    else:
        total = xctest_total(unit_log)
        lines.append(f"- app unit tests (OrangeCellTests, simulator): {f'{total[0]} tests, {total[1]} failures' if total else 'no result'}")
    for failure in failures[:30]:
        lines.append(f"  - FAIL {failure}")

    mac = xctest_total(read(out / "logs" / "swift-test-macos.log"))
    lines.append(f"- OCCore `swift test` on macOS: {f'{mac[0]} tests, {mac[1]} failures' if mac else 'no result'}")

    info = ocinfo(read(out / "logs" / "ocinfo.txt") + "\n" + unit_log)
    if info:
        lines.append("- librime link check (from the unit-test log):")
        for key in ("librime.version", "librime.modules.beforeStart", "librime.modules.afterStart",
                    "librime.started", "librime.missingRequired", "oc_core.encode", "appgroup.source", "test.footprintMB"):
            if key in info:
                lines.append(f"  - `{key}` = `{info[key]}`")

    e2e = read(out / "e2e.md").strip()
    if e2e:
        lines += ["", e2e, ""]

    report = out / "logs" / "report-keyboard.json"
    if report.exists():
        try:
            data = json.loads(read(report))
            lines.append("- keyboard extension self-report (report-keyboard.json):")
            lines.append(f"  - librime `{data.get('rimeVersion')}`, modules `{' '.join(data.get('rimeModules', []))}`")
            lines.append(f"  - oc_core round trip: `{data.get('ocCoreOK')}`, full access: `{data.get('fullAccess')}`")
            lines.append(f"  - in-process phys_footprint: **{data.get('footprintMB')} MB**")
            lines.append(f"  - App Group: `{data.get('groupResolved')}` ({data.get('groupSource')}), container `{data.get('containerPath')}`")
            peer = data.get("peerProbe")
            lines.append(f"  - sees the app's probe file: `{bool(peer)}`")
            for probe in data.get("keyStorage", []):
                lines.append(f"  - key storage `{probe.get('backend')}`: cross-process read `{probe.get('crossProcessReadOK')}` {probe.get('detail', '')}")
        except Exception as error:  # noqa: BLE001
            lines.append(f"- keyboard report unreadable: {error}")
    else:
        lines.append("- keyboard extension self-report: NOT FOUND (the extension never wrote one)")

    app_report = out / "logs" / "report-app.json"
    if app_report.exists():
        try:
            data = json.loads(read(app_report))
            lines.append(f"- app diagnostics: group `{data.get('groupResolved')}` ({data.get('groupSource')}), "
                         f"probe written `{data.get('probeWritten')}`, sees keyboard probe `{bool(data.get('peerProbe'))}`, "
                         f"librime `{data.get('rimeVersion')}`")
        except Exception as error:  # noqa: BLE001
            lines.append(f"- app report unreadable: {error}")

    fp = read(out / "footprint-keyboard-mb.txt").strip()
    if fp:
        lines.append(f"- keyboard process footprint measured from outside (`footprint`): **{fp} MB**")

    fp_text = read(out / "logs" / "footprint-keyboard.txt")
    categories = []
    for line in fp_text.splitlines():
        match = re.match(r"\s*([\d.]+ (?:KB|MB|GB|B))\s+([\d.]+ (?:KB|MB|GB|B))\s+([\d.]+ (?:KB|MB|GB|B))\s+(\d+)\s+(.+)$", line)
        if match and match.group(5).strip() != "TOTAL":
            categories.append(f"{match.group(5).strip()} {match.group(1)} dirty")
    if categories:
        lines.append("  - biggest dirty categories: " + ", ".join(categories[:5]))

    shots = sorted(p.name for p in (out / "screenshots").glob("*.png")) if (out / "screenshots").exists() else []
    if shots:
        lines.append("- screenshots: " + ", ".join(f"`{s}`" for s in shots))
    lines += ["", steps_table(out)]
    return "\n".join(lines)


def ipa(out: pathlib.Path) -> str:
    lines = ["#### ipa-device"]
    for name in ("ipa-info.txt",):
        text = read(out / "logs" / name).strip()
        if text:
            lines.append("```")
            lines.append(text)
            lines.append("```")
    lines += ["", steps_table(out)]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("job", choices=["core-linux", "build-test", "ipa"])
    parser.add_argument("--out", required=True)
    parser.add_argument("--xcresult", default="")
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    (out / "logs").mkdir(parents=True, exist_ok=True)
    if args.job == "core-linux":
        text = core_linux(out)
    elif args.job == "build-test":
        text = build_test(out, pathlib.Path(args.xcresult) if args.xcresult else None)
    else:
        text = ipa(out)
    (out / "summary.md").write_text(text + "\n", encoding="utf8")
    print(text)


if __name__ == "__main__":
    main()
