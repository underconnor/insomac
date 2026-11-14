#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
compile_only=false
if [ "$#" -eq 1 ] && [ "$1" == --compile-only ]; then
    compile_only=true
    shift
fi
seconds="${1:-60}"
output_dir="${2:-$project_dir/build/qa/insomac-profile-$(date -u +%Y%m%dT%H%M%SZ)}"
app_dir="${INSOMAC_APP_PATH:-${INSOMAC_BUILD_DIR:-$project_dir/build}/InsoMac.app}"
if [ "$#" -gt 2 ] || [[ ! "$seconds" =~ ^[0-9]+$ ]] || [ "$seconds" -lt 60 ] || [ "$seconds" -gt 120 ]; then
    printf 'Usage: %s [seconds: 60-120] [output-directory]\n' "$0" >&2
    exit 2
fi
if ! $compile_only && [ ! -x "$app_dir/Contents/MacOS/InsoMac" ]; then
    printf 'Build the app first with scripts/build.sh.\n' >&2
    exit 2
fi
mkdir -p "$project_dir/build/tools"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework AppKit -framework IOKit "$project_dir/Tools/MachTimebase.swift" "$project_dir/Tools/MeasureIdle.swift" \
    -o "$project_dir/build/tools/insomac-measure-idle"
if $compile_only; then
    printf 'Compiled native resource measurement tool without launching an app.\n'
    exit 0
fi
mkdir -p "$output_dir"
"$project_dir/build/tools/insomac-measure-idle" "$app_dir/Contents/MacOS/InsoMac" "$seconds" "$output_dir" \
    | tee "$output_dir/samples.jsonl"
