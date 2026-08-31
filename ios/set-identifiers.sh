#!/bin/bash
# Rewrites the bundle identifier prefix across every file that hardcodes it.
#
# Bundle IDs and App Group IDs have to be unique across all of Apple, so the
# defaults in this repo will not work for anyone else. The prefix appears in the
# XcodeGen spec, in three entitlements files and in one Swift constant, and all
# five have to agree or the widget silently reads an empty app group.
#
# Usage:  ./set-identifiers.sh com.yourname
set -euo pipefail

cd "$(dirname "$0")"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <new-prefix>        e.g. $0 com.yourname" >&2
    exit 1
fi

NEW="$1"
OLD=$(sed -n 's/^  bundleIdPrefix: //p' project.yml)

if [ -z "$OLD" ]; then
    echo "Could not read bundleIdPrefix from project.yml" >&2
    exit 1
fi

if [ "$OLD" = "$NEW" ]; then
    echo "Prefix is already ${NEW}; nothing to do."
    exit 0
fi

# A reversed-domain prefix, so the resulting IDs are actually valid.
if ! printf '%s' "$NEW" | grep -Eq '^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$'; then
    echo "\"${NEW}\" does not look like a reverse-domain prefix (e.g. com.yourname)." >&2
    exit 1
fi

echo "==> ${OLD}  ->  ${NEW}"
FILES=$(grep -rl "$OLD" --include='*.yml' --include='*.swift' --include='*.entitlements' .)

for f in $FILES; do
    # A literal string replacement; the prefix is validated above, so it contains
    # nothing that sed would treat as special.
    sed -i '' "s|${OLD}|${NEW}|g" "$f"
    echo "    $f"
done

echo
echo "==> Verifying"
if grep -rq "$OLD" --include='*.yml' --include='*.swift' --include='*.entitlements' .; then
    echo "    still found ${OLD}; check the files above by hand" >&2
    exit 1
fi
grep -rh -o "${NEW}[A-Za-z.]*" --include='*.yml' --include='*.swift' --include='*.entitlements' . \
  | sort -u | sed 's/^/    /'

if command -v xcodegen >/dev/null 2>&1; then
    echo
    echo "==> Regenerating project"
    xcodegen generate
else
    echo
    echo "note: xcodegen is not installed, so ScreenTimer.xcodeproj still has the" >&2
    echo "      old identifiers. Either brew install xcodegen and re-run, or change" >&2
    echo "      them in Xcode's Signing & Capabilities pane for all four targets." >&2
fi
