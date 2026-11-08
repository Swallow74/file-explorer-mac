# AGENTS.md — rules for AI agents working on this repo

## Releases (READ THIS BEFORE SHIPPING ANYTHING)

The user tests the app through **GitHub Releases**, not through a local build:
`/Applications/File Explorer.app` self-updates from this repo's releases
(`Sources/Updater.swift`). If asked to "update the repo" or "publish", that
means: commit → push → **create a GitHub release**.

1. **The version number comes from GitHub, never from local state.**
   Local tags go stale. Always run first:
   `gh release list -R Swallow74/windows-explorer-mac -L 3`
   and `git fetch --tags`. New version = latest published + 0.0.1 unless the
   user says otherwise (e.g. latest `1.4.6` → `1.4.7`). A published
   downgrade breaks the auto-updater for every user — never invent the number
   from `git tag -l` alone.
2. **Commit and push `main` before releasing**, so the release matches a
   published commit (release notes / source diff are what the user sees).
3. `./Tools/release.sh <version>` builds universal, signs (Developer ID,
   keychain), notarizes (`dev-notary` profile, a few minutes), staples, and
   zips to `build/FileExplorer-<version>-macOS-universal.zip`.
   **It does NOT publish** — it only prints the command. Publishing is:
   `gh release create v<version> --title "File Explorer for Mac <version>" "build/FileExplorer-<version>-macOS-universal.zip"`
   (the tag `v<version>` is created by that command; the title format above
   is what earlier releases use).
4. Kill dev instances before the user tests, and **never touch or "fix"
   `/Applications/File Explorer.app`** — it updates itself from step 3/4.
   Dev instances run as `.../build/File Explorer.app/Contents/MacOS/FileExplorer`
   (kill by that path; the installed one shares the same executable name, so
   match on the full path, not just `pgrep FileExplorer`).

## Building and testing

- `./build.sh` — host-arch build to `build/File Explorer.app` (~30 s;
  `--universal` for both arches). `WINEXP_SELFTEST=1` runs the self-test
  suite (must stay green: it covers grouping, l10n, archives, tabs…).
- GUI smoke-test without clicking: launch the binary directly with env vars
  (`WINEXP_START=<path>` to open at a folder — use it to test a network
  volume, e.g. `WINEXP_START=/Volumes/muletto` — `WINEXP_SIZE=WxH`,
  `WINEXP_SNAPSHOT=<file.png>`). `agent-desktop`'s synthesized key presses
  (`alt+d`, `ctrl+l`) do NOT reach SwiftUI command shortcuts; drive the UI
  with clicks, snapshots and the WINEXP_ helpers instead.
- UI behavior must never block the main thread: Bonjour/Browser probes,
  `Host.names()`, `getnameinfo` and anything touching remote volumes (SMB/NAS
  listing can hang for minutes on a sleeping host) belong on a background
  queue, with the "waiting for server" card (`Explorer.waitingTab` in
  `Sources/FileList.swift`) covering the gap.

## Repo conventions

- New UI strings: use English as the key and add the translation to **all 16**
  `Resources/*.lproj/Localizable.strings` (placeholders `%@`/`%1$@` kept in
  order; plurals separated by `|`). The self-test checks every language.
- Any user-facing behavior change must update **README.md** in the same
  commit: the feature paragraph (e.g. **Network shares**), the *Deliberate
  differences* bullet (e.g. **Drives**), the file map in *How it is built*
  (list every new file under `Sources/`), and the matching category in
  *Changes in this fork*.
- Commit messages are Italian, one line, dense — follow the style of
  `git log --oneline` (e.g. "Questo PC: solo unità locali …").
