#!/bin/bash
# Double-click to unlock File Explorer: clears the macOS quarantine flag so the
# app opens without the "can't be opened" warning. Looks next to this file
# first, then in /Applications and ~/Applications.
cd "$(dirname "$0")" || exit 1
found=""
for app in "./File Explorer.app" "/Applications/File Explorer.app" "$HOME/Applications/File Explorer.app"; do
    [ -d "$app" ] || continue
    xattr -dr com.apple.quarantine "$app" && echo "Unlocked: $app"
    [ -z "$found" ] && found="$app"
done
if [ -z "$found" ]; then
    echo "File Explorer.app not found. Put this file next to the app, or install the app in /Applications."
    read -n 1 -s -r -p "Press any key to close."
    exit 1
fi
open "$found"
