#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${INSOMAC_BUILD_DIR:-$project_dir/build}"
mkdir -p "$build_dir"
work_dir="$(mktemp -d "$build_dir/.bundle.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
app_dir="$work_dir/InsoMac.app"
target_app="$build_dir/InsoMac.app"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$build_dir/arm64" "$build_dir/x86_64" "$app_dir/Contents/MacOS"

sources=("$project_dir"/Sources/Core/*.swift "$project_dir"/Sources/Platform/*.swift "$project_dir"/Sources/App/*.swift)
for architecture in arm64 x86_64; do
    xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Werror -O2 \
        -target "$architecture-apple-macosx13.0" -isysroot "$sdk_path" \
        -c "$project_dir/Sources/Bridge/VirtualDisplayBridge.m" -o "$build_dir/$architecture/VirtualDisplayBridge.o"
    xcrun swiftc -swift-version 6 -warnings-as-errors -O -whole-module-optimization \
        -target "$architecture-apple-macosx13.0" -sdk "$sdk_path" \
        -framework AppKit -framework IOKit -framework CoreGraphics \
        -import-objc-header "$project_dir/Sources/Bridge/VirtualDisplayBridge.h" \
        "$build_dir/$architecture/VirtualDisplayBridge.o" \
        "${sources[@]}" -o "$build_dir/$architecture/InsoMac"
done

xcrun lipo -create "$build_dir/arm64/InsoMac" "$build_dir/x86_64/InsoMac" \
    -output "$app_dir/Contents/MacOS/InsoMac"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
printf 'APPL????' > "$app_dir/Contents/PkgInfo"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
xcrun lipo -archs "$app_dir/Contents/MacOS/InsoMac"
rm -rf "$target_app"
mv "$app_dir" "$target_app"
printf 'Built %s\n' "$target_app"
