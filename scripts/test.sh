#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="${INSOMAC_BUILD_DIR:-$project_dir/build}/tests"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$test_dir"

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" \
    "$project_dir"/Sources/Core/*.swift \
    "$project_dir/Tests/SessionTests.swift" -o "$test_dir/SessionTests"
"$test_dir/SessionTests"

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" -framework IOKit \
    "$project_dir"/Sources/Core/*.swift \
    "$project_dir/Tests/AssertionSmokeTests.swift" -o "$test_dir/AssertionSmokeTests"
"$test_dir/AssertionSmokeTests"

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

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" \
    "$project_dir"/Sources/Core/*.swift "$project_dir/Tests/SessionCoordinatorTests.swift" \
    -o "$test_dir/SessionCoordinatorTests"
"$test_dir/SessionCoordinatorTests"

xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" \
    "$project_dir/Sources/Platform/VirtualDisplayProcessIO.swift" \
    "$project_dir/Tests/VirtualDisplayProcessIOTests.swift" -o "$test_dir/VirtualDisplayProcessIOTests"
"$test_dir/VirtualDisplayProcessIOTests"

xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Werror -O2 \
    -target "$(uname -m)-apple-macosx13.0" -isysroot "$sdk_path" \
    -c "$project_dir/Sources/Bridge/VirtualDisplayBridge.m" -o "$test_dir/VirtualDisplayBridge.o"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" -framework Foundation -framework CoreGraphics \
    -import-objc-header "$project_dir/Sources/Bridge/VirtualDisplayBridge.h" \
    "$project_dir/Tests/VirtualDisplayPolicyTests.swift" "$test_dir/VirtualDisplayBridge.o" \
    -o "$test_dir/VirtualDisplayPolicyTests"
"$test_dir/VirtualDisplayPolicyTests"

xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk_path" \
    "$project_dir/Tools/MachTimebase.swift" "$project_dir/Tests/MachTimebaseTests.swift" \
    -o "$test_dir/MachTimebaseTests"
"$test_dir/MachTimebaseTests"

PYTHONDONTWRITEBYTECODE=1 python3 "$project_dir/Tests/ReleaseToolingTests.py"
