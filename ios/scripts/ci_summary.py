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

    for log in sorted((out / "logs").glob("ui-*.log")):
        total = xctest_total(read(log))
        lines.append(f"- UI tests `{log.stem}`: {f'{total[0]} tests, {total[1]} failures' if total else 'no result'}")

    info = ocinfo(read(out / "logs" / "ocinfo.txt") + "\n" + unit_log)
    plain ={k: v for k, v in info.items() if not k.startswith("memory.")}
    if plain:
        lines.append("- unit-test observations (OCINFO lines):")
        for key in sorted(plain):
            lines.append(f"  - `{key}` = `{plain[key]}`")
    table = memory_table(info)
    if table:
        lines += ["", "Memory with the shipped dictionary (phys_footprint in MB, XCTest process, baseline included):", "", table, ""]

    shots = sorted(p.name for p in (out / "screenshots").glob("*.png")) if (out / "screenshots").exists() else []
    if shots:
        lines.append("- screenshots: " + ", ".join(f"`{s}`" for s in shots))
    lines += ["", steps_table(out)]
    return "\n".join(lines)


def e2e_job(out: pathlib.Path, title: str) -> str:
    """The simulator end-to-end run: its own table, memory numbers, reports of the extension."""
    lines = [f"#### {title} (macos-26)"]
    toolchain = read(out / "logs" / "toolchain.log").strip().splitlines()
    if toolchain:
        lines.append("- toolchain: " + "; ".join(l.strip() for l in toolchain[:3]))
    for log in sorted((out / "logs").glob("ui-*.log")):
        total = xctest_total(read(log))
        lines.append(f"- UI tests `{log.stem}`: {f'{total[0]} tests, {total[1]} failures' if total else 'no result'}")
    table = read(out / "e2e.md").strip()
    if table:
        lines += ["", table, ""]
    footprints = read(out / "footprints.tsv").strip()
    if footprints:
        lines.append("- keyboard process footprint (`footprint`, MB): " + ", ".join(
            f"{row.split(chr(9))[0]} **{row.split(chr(9))[1]}**" for row in footprints.splitlines() if chr(9) in row))
    for tag in ("A", "B"):
        report = out / "logs" / f"report-keyboard-{tag}.json"
        if not report.exists():
            continue
        try:
            data = json.loads(read(report))
            lines.append(f"- keyboard report ({tag}): librime `{data.get('rimeVersion')}`, full access `{data.get('fullAccess')}`, "
                         f"engine running `{data.get('rimeRunning')}`, user dictionary shared `{data.get('userDataShared')}` "
                         f"(`{data.get('userDataDirectory')}`), deploy stamp `{data.get('deployStamp')}`, "
                         f"data `{data.get('rimeDataDictionary')}` / schema `{data.get('rimeDataSchema')}`, "
                         f"in-process phys_footprint {data.get('footprintMB')} MB")
            for probe in data.get("keyStorage", []):
                lines.append(f"  - key storage `{probe.get('backend')}`: cross-process read `{probe.get('crossProcessReadOK')}` {probe.get('detail', '')}")
        except Exception as error:  # noqa: BLE001
            lines.append(f"- keyboard report ({tag}) unreadable: {error}")
    fp_text = read(out / "logs" / "footprint-typing.txt")
    categories = []
    for line in fp_text.splitlines():
        match = re.match(r"\s*([\d.]+ (?:KB|MB|GB|B))\s+([\d.]+ (?:KB|MB|GB|B))\s+([\d.]+ (?:KB|MB|GB|B))\s+(\d+)\s+(.+)$", line)
        if match and match.group(5).strip() != "TOTAL":
            categories.append(f"{match.group(5).strip()} {match.group(1)} dirty")
    if categories:
        lines.append("  - biggest dirty categories after typing: " + ", ".join(categories[:6]))
    shots = sorted(p.name for p in (out / "screenshots").glob("*.png")) if (out / "screenshots").exists() else []
    if shots:
        lines.append("- screenshots: " + ", ".join(f"`{s}`" for s in shots))
    lines += ["", steps_table(out)]
    return "\n".join(lines)


MEMORY_STAGES = ["0-baseline", "1-engine-and-session", "2-first-sentence-typed", "3-committed",
                 "4-five-more-phrases", "5-stopped"]


def memory_table(info: dict) -> str:
    """Rows are stages, columns are the <mode> part of the memory.<mode>.<stage> keys."""
    modes = sorted({k.split(".")[1] for k in info if k.startswith("memory.") and k.count(".") >= 2})
    if not modes:
        return ""
    header = "| stage | " + " | ".join(modes) + " |"
    rule = "| --- | " + " | ".join("---" for _ in modes) + " |"
    rows = []
    for stage in MEMORY_STAGES:
        cells = [info.get(f"memory.{mode}.{stage}", "-") for mode in modes]
        rows.append(f"| {stage} | " + " | ".join(cells) + " |")
    return "\n".join([header, rule] + rows)


def memory_job(out: pathlib.Path) -> str:
    """The Release memory job: the same test once per module list."""
    lines = ["#### memory-release (macos-26)"]
    toolchain = read(out / "logs" / "toolchain.log").strip().splitlines()
    if toolchain:
        lines.append("- toolchain: " + "; ".join(l.strip() for l in toolchain[:3]))
    info = ocinfo(read(out / "logs" / "ocinfo.txt"))
    table = memory_table(info)
    if table:
        lines += ["", "Release, simulator, phys_footprint in MB (the XCTest process itself is in the baseline):", "", table, ""]
        for mode in ("minimal", "all"):
            try:
                delta = float(info[f"memory.{mode}.3-committed"]) - float(info[f"memory.{mode}.0-baseline"])
                lines.append(f"- {mode} modules: engine + dictionary + first sentence cost **{delta:.1f} MB** over the baseline")
            except (KeyError, ValueError):
                pass
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
    parser.add_argument("job", choices=["core-linux", "build-test", "ipa", "memory", "e2e", "e2e-debug"])
    parser.add_argument("--out", required=True)
    parser.add_argument("--xcresult", default="")
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    (out / "logs").mkdir(parents=True, exist_ok=True)
    if args.job == "core-linux":
        text = core_linux(out)
    elif args.job == "build-test":
        text = build_test(out, pathlib.Path(args.xcresult) if args.xcresult else None)
    elif args.job == "memory":
        text = memory_job(out)
    elif args.job in ("e2e", "e2e-debug"):
        text = e2e_job(out, args.job)
    else:
        text = ipa(out)
    (out / "summary.md").write_text(text + "\n", encoding="utf8")
    print(text)


if __name__ == "__main__":
    main()
