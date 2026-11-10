#!/bin/bash
# Local quality gate: builds the app and runs the self-test suite.
# Exit code 0 means every check passed; non-zero means the push is not
# allowed to happen. Same commands the CI runs, no queue, no network.
#
#   ./Tools/check.sh              build + self-test
#   ./Tools/check.sh --no-build   self-test only (reuses the existing build)
set -e
cd "$(dirname "$0")/.."

APP="build/File Explorer.app"
DO_BUILD=1
[ "${1:-}" = "--no-build" ] && DO_BUILD=0

if [ "$DO_BUILD" = "1" ]; then
    echo "==> Building"
    ./build.sh
fi

if [ ! -x "$APP/Contents/MacOS/FileExplorer" ]; then
    echo "No build found at $APP — run ./build.sh first." >&2
    exit 1
fi

echo "==> Self-test"
# `set -e` would abort here before the message, so the exit code is caught.
status=0
WINEXP_SELFTEST=1 "$APP/Contents/MacOS/FileExplorer" || status=$?

if [ "$status" -eq 0 ]; then
    echo "==> OK"
else
    echo "==> FAILED" >&2
fi
exit $status
