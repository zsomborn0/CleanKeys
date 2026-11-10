#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain.sh
mkdir -p Build/Release Build/ModuleCache
stage_dir=$(mktemp -d "$PWD/Build/.staging.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
app="$stage_dir/CleanKeys.app"
mkdir -p "$app/Contents/MacOS"
architectures=("$(uname -m)")
if [[ "${1:-}" == --universal ]]; then
    architectures=(arm64 x86_64)
elif [[ -n "${1:-}" ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi
binaries=()
for architecture in "${architectures[@]}"; do
    printf 'Compiling CleanKeys for %s…\n' "$architecture"
    binary="$stage_dir/CleanKeys-$architecture"
    xcrun swiftc -O -swift-version 5 -target "$architecture-apple-macosx14.0" \
        -sdk "$CLEANKEYS_SDK" -module-cache-path "$PWD/Build/ModuleCache" \
        CleanKeys/*.swift -o "$binary"
    binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/CleanKeys"
python3 Scripts/package-app.py "$app"
plutil -lint "$app/Contents/Info.plist" >/dev/null
codesign --force --sign - --options runtime "$app"
codesign --verify --strict "$app"
# Only replace the previous build after the new bundle is complete and verified.
if [[ -d Build/Release/CleanKeys.app ]]; then
    mv Build/Release/CleanKeys.app "$stage_dir/previous.app"
fi
mv "$app" Build/Release/CleanKeys.app
ditto -c -k --sequesterRsrc --keepParent Build/Release/CleanKeys.app "$stage_dir/CleanKeys.zip"
mv "$stage_dir/CleanKeys.zip" Build/Release/CleanKeys.zip
printf 'Built %s/Build/Release/CleanKeys.app\n' "$PWD"
