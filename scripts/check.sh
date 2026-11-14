#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:---graphics}"
if [ "$#" -gt 1 ] || { [ "$mode" != --headless ] && [ "$mode" != --graphics ]; }; then
    printf 'Usage: %s [--headless|--graphics]\n' "$0" >&2
    exit 2
fi
build_dir="${INSOMAC_BUILD_DIR:-$project_dir/build}"
qa_dir="${INSOMAC_QA_DIR:-$project_dir/build/qa/insomac-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$qa_dir"
"$project_dir/scripts/build.sh" 2>&1 | tee "$qa_dir/build.log"
"$project_dir/scripts/test.sh" 2>&1 | tee "$qa_dir/tests.log"
"$project_dir/scripts/verify-app.sh" "$build_dir/InsoMac.app" --runtime \
    2>&1 | tee "$qa_dir/bundle-verification.json"
if [ "$mode" == --graphics ]; then
    "$project_dir/scripts/test-graphics.sh" 2>&1 | tee "$qa_dir/graphics.log"
    "$project_dir/scripts/preview.sh" 2>&1 | tee "$qa_dir/preview.log"
fi
printf 'All local checks passed.\n'
printf 'Evidence: %s\n' "$qa_dir"
