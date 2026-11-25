#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fails a test step that did not really test: no test executed, or a test was skipped.

    check_tests.py <xcodebuild log> [--allow-skip NAME ...]

A skipped test is not a pass (a missing data folder or a missing simulator feature silently turns a gate
into a no-op); a run that executed zero tests is not a pass either.
"""
import argparse
import pathlib
import re
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("--allow-skip", nargs="*", default=[])
    args = parser.parse_args()
    text = pathlib.Path(args.log).read_text(encoding="utf8", errors="replace")
    totals = re.findall(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", text)
    executed = max((int(t[0]) for t in totals), default=0)
    skipped = [m for m in re.findall(r"Test Case '-\[(\S+ \S+)\]' skipped", text) if not any(a in m for a in args.allow_skip)]
    problems = []
    if executed == 0:
        problems.append("no test was executed")
    if skipped:
        problems.append("skipped: " + ", ".join(sorted(set(skipped))))
    if problems:
        print("check_tests: " + "; ".join(problems))
        return 1
    print(f"check_tests: {executed} tests executed, none skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
