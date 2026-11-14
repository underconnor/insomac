#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [seconds], from 1 through 120.\n' "$0" >&2
    exit 2
fi
mkdir -p "$project_dir/build/tools"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework CoreGraphics "$project_dir/Tools/DisplayProbe.swift" \
    -o "$project_dir/build/tools/insomac-display-probe"
"$project_dir/build/tools/insomac-display-probe" "${1:-10}"
