#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
qa_dir="${INSOMAC_QA_DIR:-$project_dir/build/qa/insomac-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$qa_dir"
"$project_dir/scripts/build.sh" 2>&1 | tee "$qa_dir/build.log"
"$project_dir/scripts/test.sh" 2>&1 | tee "$qa_dir/tests.log"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework AppKit -framework IOKit "$project_dir/Tests/AppLifecycleTests.swift" \
    -o "$project_dir/build/tests/AppLifecycleTests"
"$project_dir/build/tests/AppLifecycleTests" "$project_dir/build/InsoMac.app/Contents/MacOS/InsoMac" \
    2>&1 | tee "$qa_dir/lifecycle.log"
"$project_dir/scripts/preview.sh" 2>&1 | tee "$qa_dir/preview.log"
printf 'All local checks passed.\n'
printf 'Evidence: %s\n' "$qa_dir"
