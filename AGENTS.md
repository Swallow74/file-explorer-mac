# AGENTS.md — rules for AI agents working on this repo

## Releases (READ THIS BEFORE SHIPPING ANYTHING)

The user tests the app through **GitHub Releases**, not through a local build:
`/Applications/File Explorer.app` self-updates from this repo's releases
(`Sources/Updater.swift`). If asked to "update the repo" or "publish", that
means: commit → push → **create a GitHub release**.

1. **The version number comes from GitHub, never from local state.**
   Local tags go stale. Always run first:
   `gh release list -R Swallow74/file-explorer-mac -L 3`
   and `git fetch --tags`. New version = latest published + 0.0.1 unless the
   user says otherwise (e.g. latest `1.4.6` → `1.4.7`). A published
   downgrade breaks the auto-updater for every user — never invent the number
   from `git tag -l` alone.
2. **Commit and push `main` before releasing**, so the release matches a
   published commit (release notes / source diff are what the user sees).
3. `./Tools/release.sh <version>` builds arm64, signs (Developer ID,
   keychain), notarizes (`dev-notary` profile, a few minutes), staples, and
   zips to `build/FileExplorer-<version>-macOS-arm64.zip`.
   **It does NOT publish** — it only prints the command. Publishing is:
   `gh release create -R Swallow74/file-explorer-mac v<version> --title "File Explorer for Mac <version>" "build/FileExplorer-<version>-macOS-arm64.zip"`
   (always pass `-R`: an `upstream` remote exists, and without `-R` `gh`
   resolves the wrong repo; the tag `v<version>` is created by that command;
   the title format above is what earlier releases use).
4. Kill dev instances before the user tests, and **never touch or "fix"
   `/Applications/File Explorer.app`** — it updates itself from step 3/4.
   Dev instances run as `.../build/File Explorer.app/Contents/MacOS/FileExplorer`
   (kill by that path; the installed one shares the same executable name, so
   match on the full path, not just `pgrep FileExplorer`).

## Building and testing

- `./build.sh` — arm64 build to `build/File Explorer.app` (~30 s;
  Apple Silicon only). `WINEXP_SELFTEST=1` runs the self-test
  suite (must stay green: it covers grouping, l10n, archives, tabs…).
- **`./Tools/check.sh` is the gate**: build + self-test, non-zero exit on
  failure (~36 s, 171 checks). A pre-push hook (`.githooks/pre-push`, enabled
  with `git config core.hooksPath .githooks`) runs it on every push to
  `main` and blocks the push if a check fails. `git push --no-verify` or
  `FE_SKIP_PREPUSH=1` skips it. **Run it before committing**, so nothing
  broken reaches the repo.
- **CI is release-only.** `.github/workflows/release.yml` triggers on
  `release: published` and verifies the *artifact*: it compiles the source in
  a clean environment, then downloads the published zip, checks the Developer
  ID signature, the notarization ticket and the staple, and runs the suite
  again on the shipped binary. There is no push-triggered workflow on
  purpose — the runner queue on `macos-latest` is slow and was cancelled
  constantly. Do not add one back without asking the user.
- The release workflow needs the release to exist: `gh release create` pushes
  the tag *before* the assets are attached, so a `push: tags` trigger would
  race with the upload. `release: published` is the correct trigger.
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
- The `pre-push` hook is opt-in per clone: after `git clone`, run
  `git config core.hooksPath .githooks` to get the local gate back.
