#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$project_dir/build/tests"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$test_dir"

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" \
    "$project_dir"/Sources/Core/*.swift \
    "$project_dir/Tests/SessionTests.swift" -o "$test_dir/SessionTests"
"$test_dir/SessionTests"

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" -framework AppKit \
    "$project_dir"/Sources/Core/*.swift \
    "$project_dir/Sources/App/StatusPresentation.swift" \
    "$project_dir/Tests/SmokeTests.swift" -framework IOKit -o "$test_dir/SmokeTests"
"$test_dir/SmokeTests"

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" -framework IOKit \
    "$project_dir"/Sources/Core/*.swift "$project_dir/Tests/ProcessCleanupTests.swift" \
    -o "$test_dir/ProcessCleanupTests"
"$test_dir/ProcessCleanupTests"

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" \
    "$project_dir/Sources/Platform/ParentProcessMonitor.swift" \
    "$project_dir/Tests/ParentProcessMonitorTests.swift" -o "$test_dir/ParentProcessMonitorTests"
"$test_dir/ParentProcessMonitorTests"
