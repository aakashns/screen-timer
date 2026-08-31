#!/bin/bash
# Regenerates ScreenTimer.xcodeproj from project.yml, then builds it.
#
# Unlike the macOS build this cannot be done with a bare swiftc call: the app
# ships three app extensions, which need a real project to be embedded into the
# bundle, signed, and provisioned with the app group.
set -euo pipefail

cd "$(dirname "$0")"

if command -v xcodegen >/dev/null 2>&1; then
    echo "==> Regenerating project"
    xcodegen generate
else
    echo "==> xcodegen not installed; using the committed ScreenTimer.xcodeproj"
    echo "    (brew install xcodegen to regenerate it from project.yml)"
fi

echo "==> Checking the shared tick arithmetic"
./test.sh

if ! xcodebuild -version >/dev/null 2>&1; then
    echo
    echo "Xcode is required to build the app itself; only the Command Line Tools" >&2
    echo "are active, which have no iOS SDK. Install Xcode, then:" >&2
    echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    echo >&2
    echo "The project is ready to open: ios/ScreenTimer.xcodeproj" >&2
    exit 1
fi

echo "==> Building"
# Signing is left to Xcode: the Family Controls and app-group entitlements need a
# real team, so a generic unsigned build would fail here for the wrong reason.
xcodebuild \
  -project ScreenTimer.xcodeproj \
  -scheme ScreenTimer \
  -destination 'generic/platform=iOS' \
  build "$@"
