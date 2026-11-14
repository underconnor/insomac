#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${INSOMAC_BUILD_DIR:-$project_dir/build}"
test_dir="$build_dir/tests"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$test_dir"
xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" -framework AppKit -framework IOKit \
    "$project_dir"/Sources/Core/*.swift "$project_dir/Sources/App/StatusPresentation.swift" \
    "$project_dir/Tests/SmokeTests.swift" -o "$test_dir/SmokeTests"
"$test_dir/SmokeTests"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" -framework AppKit -framework IOKit \
    "$project_dir/Tests/AppLifecycleTests.swift" -o "$test_dir/AppLifecycleTests"
"$test_dir/AppLifecycleTests" "$build_dir/InsoMac.app/Contents/MacOS/InsoMac"
