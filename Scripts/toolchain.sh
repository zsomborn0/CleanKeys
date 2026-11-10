#!/bin/bash
# Shared, side-effect-free compiler selection for local builds and checks.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if [[ -d /Library/Developer/CommandLineTools ]]; then
        export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    else
        export DEVELOPER_DIR="$(xcode-select -p)"
    fi
fi
CLEANKEYS_SDK=$(xcrun --sdk macosx --show-sdk-path)
# The CLT 27 SDK requires SwiftUI macro plugins supplied by full Xcode.
if [[ "$DEVELOPER_DIR" == /Library/Developer/CommandLineTools && -d "$DEVELOPER_DIR/SDKs/MacOSX26.5.sdk" ]]; then
    CLEANKEYS_SDK="$DEVELOPER_DIR/SDKs/MacOSX26.5.sdk"
fi
export CLEANKEYS_SDK
