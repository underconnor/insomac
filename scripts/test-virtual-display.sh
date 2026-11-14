#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$project_dir/build/tests"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
architecture="$(uname -m)"
mkdir -p "$test_dir"
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Werror -O2 \
    -target "$architecture-apple-macosx13.0" -isysroot "$sdk_path" \
    -c "$project_dir/Sources/Bridge/VirtualDisplayBridge.m" -o "$test_dir/VirtualDisplayBridge.o"
xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$architecture-apple-macosx13.0" -sdk "$sdk_path" \
    -framework AppKit -framework CoreGraphics -framework IOKit \
    -import-objc-header "$project_dir/Sources/Bridge/VirtualDisplayBridge.h" \
    "$project_dir"/Sources/Core/*.swift "$project_dir"/Sources/Platform/*.swift \
    "$project_dir/Tests/VirtualDisplaySmokeTests.swift" "$test_dir/VirtualDisplayBridge.o" \
    -o "$test_dir/VirtualDisplaySmokeTests"
"$test_dir/VirtualDisplaySmokeTests"
