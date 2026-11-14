#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build/tools"
xcrun swiftc -swift-version 6 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework AppKit "$project_dir"/Sources/Core/*.swift \
    "$project_dir/Sources/App/StatusPresentation.swift" "$project_dir/Tools/RenderPreview.swift" \
    -o "$project_dir/build/tools/insomac-render-preview"
"$project_dir/build/tools/insomac-render-preview" "$project_dir/build/preview"
mkdir -p "$project_dir/docs/assets"
cp "$project_dir/build/preview/insomac-states-light.png" "$project_dir/docs/assets/insomac-states-light.png"
cp "$project_dir/build/preview/insomac-states-dark.png" "$project_dir/docs/assets/insomac-states-dark.png"
