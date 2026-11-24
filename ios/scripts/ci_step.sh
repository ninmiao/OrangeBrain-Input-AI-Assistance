#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs one CI step, keeps its whole output in a log file next to the console
# output, and records the exit code for the results channel.
#
#   CI_OUT=<dir> ci_step.sh <step-name> -- <command> [args...]
#
# Files written under $CI_OUT:
#   logs/<step>.log          full output (not published)
#   logs/<step>.tail.txt     last 400 lines when the step failed, last 40 otherwise
#   logs/<step>.errors.txt   error-looking lines with line numbers (failed steps only)
#   steps.tsv                step <TAB> exit code <TAB> seconds
set -uo pipefail

name="${1:?step name}"
shift
if [ "${1:-}" = "--" ]; then shift; fi
out="${CI_OUT:?CI_OUT must point at the output directory of the job}"
mkdir -p "$out/logs"
log="$out/logs/$name.log"

echo "::group::$name"
start=$(date +%s)
"$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
end=$(date +%s)
echo "::endgroup::"

printf '%s\t%s\t%s\n' "$name" "$code" "$((end - start))" >> "$out/steps.tsv"
if [ "$code" -ne 0 ]; then
  tail -n 400 "$log" > "$out/logs/$name.tail.txt"
  grep -n -E 'error:|\*\*\* |Test Case .* failed|XCTAssert|Fatal error|Assertion failed|Undefined symbols|undefined symbol|ld: |clang: error|FAILED|Segmentation fault|Traceback' "$log" \
    | head -n 200 > "$out/logs/$name.errors.txt" || true
  echo "::error::step '$name' failed with exit code $code"
  # The first error-looking lines also become annotations, which the public
  # check-runs API shows while the workflow is still running.
  head -n 8 "$out/logs/$name.errors.txt" 2>/dev/null | while IFS= read -r line; do
    printf '::error title=%s::%s\n' "$name" "$(printf '%s' "${line:0:300}" | sed 's/%/%25/g')"
  done || true
else
  tail -n 40 "$log" > "$out/logs/$name.tail.txt"
fi
exit "$code"
