#!/bin/bash
# Checks the tick arithmetic that the widget and the in-app readout share.
#
# Runs without Xcode and without an iOS SDK: everything under Shared/ is
# Foundation-only by design, so it compiles for the host Mac. The SwiftUI,
# WidgetKit and DeviceActivity layers on top of it need a real iOS build.
set -euo pipefail

cd "$(dirname "$0")"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

swiftc -O -o "$OUT/tests" Tests/main.swift Shared/*.swift
"$OUT/tests"
