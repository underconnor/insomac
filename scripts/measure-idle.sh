#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -x "$project_dir/build/InsoMac.app/Contents/MacOS/InsoMac" ]; then
    printf 'Build the app first with scripts/build.sh.\n' >&2
    exit 2
fi
mkdir -p "$project_dir/build/tools"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework AppKit "$project_dir/Tools/MeasureIdle.swift" \
    -o "$project_dir/build/tools/insomac-measure-idle"
"$project_dir/build/tools/insomac-measure-idle" "$project_dir/build/InsoMac.app/Contents/MacOS/InsoMac"
