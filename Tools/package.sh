#!/bin/bash
# Zips the app together with the unlock script: package.sh <app> <zip>
set -e
cd "$(dirname "$0")/.."
APP="${1:?usage: package.sh <app> <zip>}"; ZIP="${2:?usage: package.sh <app> <zip>}"
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/$(basename "$APP")"
cp "Tools/Unlock File Explorer.command" "$STAGE/"
rm -f "$ZIP"
ditto -c -k "$STAGE" "$ZIP"
rm -rf "$STAGE"
