#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain.sh
if [[ ! -d Build/Release/CleanKeys.app ]]; then
    Scripts/build-app.sh
fi
python3 Scripts/check-resources.py
check_dir=$(mktemp -d /tmp/cleankeys-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
mkdir -p Build/ModuleCache
sources=()
for source in CleanKeys/*.swift; do
    [[ "$source" == CleanKeys/CleanKeysApp.swift ]] && continue
    sources+=("$source")
done
xcrun swiftc -parse-as-library -swift-version 5 -sdk "$CLEANKEYS_SDK" \
    -module-cache-path "$PWD/Build/ModuleCache" \
    "${sources[@]}" Tests/BehaviorChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
