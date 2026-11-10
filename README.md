<div align="center">

<img src="Resources/AppIcon.png" width="112" alt="File Explorer icon">

# File Explorer for Mac

**The Windows 11 File Explorer, rebuilt natively for macOS.**

Same layout, same Fluent iconography, same keyboard shortcuts, driving the real macOS filesystem.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-000000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Dependencies](https://img.shields.io/badge/dependencies-none-4CC2FF?style=flat-square)](#build)
[![Tests](https://img.shields.io/badge/tests-171%20passing-6CCB5F?style=flat-square)](#tests)
[![Build](https://github.com/Swallow74/file-explorer-mac/actions/workflows/release.yml/badge.svg)](https://github.com/Swallow74/file-explorer-mac/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-lightgrey?style=flat-square)](LICENSE)

<img src="docs/demo.gif" width="900" alt="Browsing folders, switching view modes, the context menu, and changing theme and accent colour">

</div>

## Why

I wanted Windows Explorer on my Mac. Not "a file manager with Windows-ish styling", but the actual thing: the tab strip, the command bar, the breadcrumb address bar, `Ctrl+C` / `Ctrl+V` / `F2` / `Alt+Left`, and the Fluent icons.

So I built it. No Electron, no dependencies, no package manager. One `swiftc` invocation produces a 5 MB native app.

## Highlights

|  |  |
|---|---|
| **Pixel-faithful chrome** | Tab strip with Windows caption buttons drawn where the traffic lights normally go, breadcrumb address bar with sibling drop-downs, command bar, status bar (with a centred, azure AlexTech.ai link and a glint that sweeps over it every few seconds). Colours come from the WinUI 3 dark and light palettes. |
| **Redrawn Fluent icons** | Segoe Fluent Icons isn't licensed onto macOS, so every glyph is redrawn as vector geometry on Windows' own 16pt design grid, including the two-tone accent treatment on cut, copy, paste, rename, share, sort and view. |
| **Real Windows shortcuts** | Bound to both `Ctrl` (Windows) and `Cmd` (Mac reflex), and every one of them re-mappable from Settings. |
| **Eight view modes** | Icon grids with live thumbnails (images decoded by content, so a JPEG renamed `.webp` still shows; WebP, AVIF, HEIC, EXR, RAW, PDF, video, audio cover art, documents, text, code and fonts), List that flows into columns, Details with sortable resizable columns, Tiles, Content. **Group by** Name, Type, Date modified or Size, with collapsible Windows-style section headers (List, Tiles and Content ignore grouping, as Windows does). |
| **It actually does the work** | Copy, cut and move — same-volume copies are APFS clones, instant and free until modified — paste with `- Copy` naming in the same folder and the Windows "Replace or Skip Files" prompt (replace, skip, keep both) when the destination already has the names, eject for external drives, rename, ZIP, shortcuts, Recycle Bin and permanent delete, all with undo and redo. Drag and drop works inside the app, onto sidebar folders and Quick access tiles, and to and from Finder, with the drop target lighting up as you hover it. Rubber-band selection works from any empty space, additive with `Shift` or `Ctrl`. Clicking an already-selected name again turns it into an edit field, as in Explorer and Finder, while a double-click still opens. |
| **A Finder replacement** | One switch in Settings makes it the system file manager: folders opened from the Dock, the Terminal or other apps, and every *Show in Finder*, land here. Finder tags, the Services menu, AirDrop, Spotlight search inside file contents, package contents and a Recycle Bin that can restore and empty. See [Finder replacement](#power-tools). |
| **Your language** | The interface is translated into 16 languages (see [Languages](#languages)) and follows the macOS language by default. English is the fallback. |
| **Power tools** | Dual pane, a background transfer queue with progress, archive browsing, batch rename, folder compare and sync, a drop shelf, workspaces, network shares and user-defined commands. Tabs get a right-click menu (duplicate, paste-to-tab, close), and dropping a file onto a tab sends it to that tab's folder without leaving the current one. |

<div align="center">
<img src="docs/details.png" width="440" alt="Details view"> <img src="docs/icons-view.png" width="440" alt="Large icons view with thumbnails">
<img src="docs/grouping.png" width="440" alt="Details view grouped by Date modified with collapsible headers"> <img src="docs/context-menu.png" width="440" alt="Windows 11 context menu">
<img src="docs/light.png" width="440" alt="Light theme with a green accent">
</div>

## Download

Grab the latest build from [Releases](https://github.com/Swallow74/file-explorer-mac/releases/latest). Apple Silicon (arm64) only, macOS 14 or newer. Intel Macs are no longer supported from 1.4.17; 1.4.16 is the last universal build.

Since 1.3.1 the release is signed with a Developer ID and **notarized by Apple**: unzip, drag to Applications and double-click, nothing to unblock. Releases up to 1.3.0 were only ad-hoc signed; if macOS refuses one of those, use **System Settings > Privacy & Security > Open Anyway**, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/File Explorer.app"
```

If you would rather not trust a download at all, build it from source. That takes one command and produces a binary macOS trusts, because it never came from the internet.

## Power tools

Everything below is optional. Turn a feature off and the app is still the Explorer clone it started as.

<div align="center">
<img src="docs/dual-pane.png" width="440" alt="Dual pane with the shelf open"> <img src="docs/archive.png" width="440" alt="Browsing inside a zip archive">
</div>

**Dual pane** (`Ctrl+U`). Two independent panes, each with its own tabs and history. `Tab` switches, `Ctrl+Shift+U` swaps them, and the overflow menu copies or moves the selection straight to the other pane. Columns drop out as a pane narrows rather than overflowing it.

**Background transfers.** Copies and moves run on a queue with a progress bar in the status bar, a rate and time estimate, and a cancel button. Nothing blocks the window, and a move within one volume is still instant.

**Archive browsing.** Double-click a zip or a tarball and walk into it like a folder. Open a file inside and it is extracted to a scratch folder first. Extract the whole thing, or just the selection, from the command bar. Zip and the tar family are supported, through the system's own `bsdtar`. RAR and 7z are not, because macOS ships no tool for them.

**Batch rename** (`Ctrl+Shift+R`). Find and replace, prefix, suffix, numbering, case, extension, with a live preview and clash detection before anything is touched. It lands on the undo stack as one step.

**Folder compare and sync.** Compare two trees, see what is only on one side and what differs, then copy one way. Defaults to the two panes when they are open.

**Shelf** (`Ctrl+Shift+S`). A staging area that survives navigation: drop files in, go somewhere else, drop them out. Or use Copy here and Move here.

**Workspaces.** Save the tabs open in each pane, the split and the view mode under a name, and restore them later.

**Network shares** (`Ctrl+K`). Connect to SMB, AFP, NFS, FTP and WebDAV, with recent servers remembered. macOS owns the sign-in, so no password is ever typed into File Explorer. The **Network** page also lists the machines found on the local network — Bonjour announcements plus a pass on the connected subnets — each opening into its shared folders; the Mac itself is never listed, and any computer can be dismissed with right-click > *Don't show on Network*. Opening a sleeping or slow server shows a "waiting for the server" card while the listing runs in the background, so the window keeps responding. SFTP and S3 are not supported, because macOS cannot mount them without a third-party filesystem.

**Finder replacement.** *Settings > Appearance > macOS > Default file manager* makes File Explorer the system file viewer: folders opened from the Dock, the Terminal (`open .`) or any other app land in a tab here, and every app's *Show in Finder* reveals the file here with it selected. Switching it off hands both back to the Finder. Folders dropped on the Dock icon open too. Finder **tags** show as colour dots after the name and are set from right-click > *Tags*, stored exactly as the Finder stores them. The app menu carries the system **Services** menu for the selection (Quick Actions included), the context menu sends files over **AirDrop** and opens bundles with *Show package contents*, and search adds **Spotlight** results — matches inside files, not just in names — on indexed local volumes. In the Recycle Bin, *Restore* puts back whatever File Explorer deleted and *Empty Recycle Bin* clears it.

**Commands.** Your own scripts in the context menu, with the selection in the environment (`$FE_SELECTION`, `$FE_NAMES`, `$FE_FIRST`, `$FE_DIR`, `$FE_COUNT`). Managed from Settings, stored in `~/Library/Application Support/File Explorer/commands.json`. Deliberately scripts rather than loadable native code: a plugin that can crash or compromise the app is not a feature.

## Build

Requires the Swift 6 toolchain that ships with Xcode. The Command Line Tools alone are not enough: SwiftUI's `@State` and friends expand through the `SwiftUIMacros` plugin, which only ships inside a full Xcode. No Xcode project, no Node, no Homebrew.

```bash
git clone https://github.com/Swallow74/file-explorer-mac.git
cd file-explorer-mac
./build.sh
open "build/File Explorer.app"
```

`./build.sh` produces an Apple Silicon (arm64) binary, which is what the releases ship.

After changing the source, run the gate before you commit — it builds and runs the whole test suite in about 36 seconds:

```bash
./Tools/check.sh
```

A pre-push hook runs it for you on every push to `main`. Enable it once per clone with `git config core.hooksPath .githooks`.

To keep it around:

```bash
cp -R "build/File Explorer.app" /Applications/
```

To update an installed copy after pulling new commits — the installed app does not track the build folder on its own:

```bash
git pull
./build.sh
rm -rf /Applications/"File Explorer.app"
cp -R "build/File Explorer.app" /Applications/
```

> macOS asks permission the first time the app reads Desktop, Documents, Downloads or a removable volume. Until you allow it, those folders list as empty. That is macOS, not the app.

## Keyboard shortcuts

Every shortcut works with **`Ctrl`** (as on Windows) *and* **`Cmd`** (as Mac muscle memory expects). `Alt` means `Option`.

<table>
<tr><td valign="top">

**Clipboard and files**

| Shortcut | Action |
|---|---|
| `Ctrl+C` | Copy |
| `Ctrl+X` | Cut |
| `Ctrl+V` | Paste |
| `Ctrl+Shift+V` | Paste shortcut |
| `Ctrl+Shift+C` | Copy as path |
| `Ctrl+Z` / `Ctrl+Y` | Undo, redo |
| `F2` | Rename |
| Click a selected name again | Rename in place |
| Click away while renaming | Apply the new name, like Windows |
| `Delete` | Recycle Bin |
| `Shift+Delete` | Delete permanently |
| `Ctrl+Shift+N` | New folder |
| `Enter` | Open |
| `Space` | Quick Look preview (`Space`/`Esc` closes) |
| `Ctrl+Space` | Toggle the item in the selection |
| `Alt+Enter` | Properties |

</td><td valign="top">

**Navigation**

| Shortcut | Action |
|---|---|
| `Alt+Left` / `Alt+Right` | Back, forward |
| `Alt+Up` | Up one level |
| `Backspace` | Back |
| `F5` / `Ctrl+R` | Refresh |
| `Ctrl+L` / `Alt+D` / `F4` | Address bar |
| `Ctrl+F` / `F3` | Search |
| `Ctrl+D` | Show desktop (Win+D) |
| `Ctrl+Shift+D` | Go to Desktop folder |
| `Ctrl+Shift+H` | Go Home |
| `Ctrl+Shift+J` | Go to Downloads |
| Type letters | Type-ahead jump |

</td><td valign="top">

**View, tabs and windows**

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+1` to `8` | The eight view modes |
| `Ctrl+Scroll` | Cycle icon sizes |
| `Ctrl+T` / `Ctrl+W` | New tab, close tab |
| `Ctrl+Shift+T` | Reopen the last closed tab |
| `Ctrl+Tab` | Next tab |
| `Ctrl+1` to `9` | Jump to tab |
| `Ctrl+N` | New window |
| `Ctrl+A` | Select all |
| `Alt+P` / `Alt+Shift+P` | Preview, details pane |
| `Ctrl+H` | Hidden items |
| `Ctrl+U` | Dual pane |
| `Tab` | Switch pane |
| `Ctrl+Shift+U` | Swap panes |
| `Ctrl+Shift+R` | Batch rename |
| `Ctrl+Shift+S` | Shelf |
| `Ctrl+K` | Connect to server |
| `Ctrl+,` | Settings |

</td></tr>
</table>

`Ctrl+D` is Windows' `Win+D`: it hides every app so the desktop itself is showing, and puts them back when you press it again.

## Settings

<img src="docs/settings.png" width="520" align="right" alt="Settings">

The gear at the right end of the command bar, also in the `...` menu, the background right-click menu, and on `Ctrl+,`.

- **Appearance.** System, Light or Dark, **language** (follow the system or pick one; it applies at once), eight accent colours, and toggles for compact view, the three panes, item check boxes, extensions and hidden items.
- **Shortcuts.** Re-map any command. Click a shortcut, press the keys. If the combination is taken it is moved off the other command and you are told which. Per-command and global reset.
- **Quick access.** Everything pinned to the sidebar. Unpin any of it, including the six Windows defaults, restore what you unpinned, add folders.
- **Folder icons.** The folders you have customised, with a reset for each.

**Pinning.** Right-click any folder, in the list or the sidebar, then choose *Pin to Quick access*.

**Custom folder icons.** Right-click a folder and choose *Change icon*, then pick a Fluent glyph and a colour, or tint the standard folder. It applies in the file list, the sidebar and the Home tiles.

<br clear="right">

## Languages

English, Čeština, Dansk, Deutsch, Ελληνικά, Español, Français, Italiano, Nederlands, Polski, Português, Русский, Svenska, Türkçe, Українська, 日本語 and 简体中文.

- **Default: system.** The app picks the first language in the macOS preference list that it ships with (any Chinese variant maps to Simplified Chinese). If none matches, or the list is empty, it uses English.
- **Change it** in *Settings > Appearance > Language*. The window, menus and dialogs switch immediately, with no restart. Only the standard macOS panels (open and save sheets, system alerts) follow the new language at the next launch.
- **What is not translated:** file names, your own folder names, the About credits, and the keys shown in shortcuts. Menu and file-type names that Windows itself does not localise (`ZIP`, `PowerShell`) stay as they are.
- **Developers:** `WINEXP_LANG=<code>` forces a language for one run (for example `WINEXP_LANG=ja`). The self-test and the demo always run in English.

**Adding a language.** The English text is the key, so there is no table to keep in sync.

1. Create `Resources/<code>.lproj/Localizable.strings` with one `"English text" = "translation";` line per string. Copy `it.lproj` as a starting point.
2. Keep the placeholders: `%@` in order, or `%1$@`, `%2$@` when the word order changes. Plural strings hold their forms separated by `|` (one, few, many, other, as far as the language uses them).
3. Add the language to `L10n.languages` in `Sources/L10n.swift`, and its plural rule to `L10n.pluralIndex` if it needs one.
4. Rebuild. `build.sh` copies every `*.lproj` and lists them in `CFBundleLocalizations`. A string with no translation shows in English, so partial translations are fine.

Strings are wrapped in `tr("…")` and `trp(count, "one", "other")`; stored values (sort keys, grouping, settings) stay in English and only their display label is translated.

## How the icons were made

Windows draws its command bar with **Segoe Fluent Icons**, a font that ships with Windows and isn't available on macOS. Copying the font wasn't an option, so the glyphs are reconstructed instead.

Each icon is authored as a string in a small path language, on the same 16x16 grid Fluent uses:

```swift
.paste:  ("R 3.4 3.0 9.2 10.6 1.5 M6.2 3.0 V2.4 C6.2 1.9 6.5 1.6 7 1.6 H9 C9.5 1.6 9.8 1.9 9.8 2.4 V3.0", "")
.filter: ("M2.4 3.4 H13.6 L9.2 8.6 V13.4 L6.8 11.8 V8.6 Z", "")
```

`M/L/H/V/C/Q/Z` are the usual SVG commands, `O` adds a circle, `R` a rounded rect, `K` an arc. A parser of about 60 lines turns them into SwiftUI `Path`s rendered in a `Canvas`. A second, optional layer per icon carries the accent-coloured part: the blue rings on the scissors, the blue sheet inside the clipboard. That layer is what makes the command bar read as Windows rather than as generic line art.

The palette was taken from the WinUI 3 design tokens and cross-checked by sampling pixels out of a real Windows 11 screenshot.

## Architecture

```
Sources/
  Theme.swift          WinUI 3 colour system, metrics, type ramp
  Glyphs.swift         Fluent icon set: path mini-language and renderer
  FileIcons.swift      Folder and file-type artwork, Quick Look thumbnails
  Model.swift          FileItem, Windows metadata formatting, known folders
  Explorer.swift       Tabs, history, selection, clipboard, file ops, undo, search
  QuickLook.swift      Space-bar Quick Look preview panel
  Grouping.swift       The "Group by" buckets and their Windows labels
  Settings.swift       Re-mappable shortcuts, theme, language, folder icons, pinning
  L10n.swift           Languages, system-language detection, tr() and plural forms
  WindowModel.swift    One or two panes per window
  Transfers.swift      Background copy and move queue with progress
  Updater.swift        Update check against GitHub Releases and self-update
  MacIntegration.swift Default file viewer, Finder tags, Spotlight, Recycle Bin restore
  Archives.swift       Reading and extracting zip and tar archives
  BatchRename.swift    The rename rule and its dialog
  CompareSync.swift    Folder comparison and one-way sync
  NetworkView.swift    Bonjour and LAN host discovery, share browsing
  RemoteServers.swift  Network shares, mounted by macOS itself
  Workspaces.swift     Saved pane and tab layouts
  Shelf.swift          The staging area
  Marquee.swift        Rubber-band selection
  CustomCommands.swift User-defined scripts in the context menu
  Controls.swift       Win11 buttons, flyout menus, AppKit-backed text fields
  Chrome.swift         Title bar, address bar, command bar
  Sidebar.swift        Navigation pane and drop handling
  FileList.swift       Details, icons, list, tiles, content, right-click routing
  HomeView.swift       Quick access and Recent
  Panes.swift          Status bar, details pane, preview pane
  Dialogs.swift        Properties, delete confirmation, errors
  SettingsDialog.swift Settings and folder-icon dialogs
  ContextMenus.swift   Right-click menus
  ContentView.swift    Root layout, flyout and dialog hosting
  App.swift            Window setup, key bindings, menu bar
  main.swift           The executable's entry point
  SelfTest.swift       End-to-end checks
  Demo.swift           The scripted tour behind the README animation
Resources/
  <code>.lproj/        Localizable.strings per language
Tools/
  MakeIcon.swift       Draws the app icon, one render per icon-set size
  release.sh           Signs, notarizes and staples a release build
  package.sh           Zips the release with its install instructions
  check.sh             Local gate: builds and runs the self-test suite
.githooks/
  pre-push             Runs Tools/check.sh before a push to main
build.sh               Compiles and assembles the .app bundle
```

Two decisions worth calling out:

- **Right-click routing.** Context-menu targets register an invisible marker view, and a window-level monitor picks the smallest target under the pointer, falling back to the file-area background. Fighting AppKit's hit-testing instead would have swallowed the left clicks SwiftUI needs for selection and drag and drop.
- **Rubber-band selection is routed the same way.** A SwiftUI drag gesture on the list background never fires, because the enclosing ScrollView claims drags for scrolling first. A window-level monitor takes the press only when it lands on empty space inside a pane, so a drag that starts on an item still drags the item.
- **Shortcuts match on key code, not character.** `Shift+3` reports `#`, not `3`, so matching on characters silently breaks every `Ctrl+Shift+<digit>` binding.

## Tests

```bash
WINEXP_SELFTEST=1 "build/File Explorer.app/Contents/MacOS/FileExplorer"
```

Creates a scratch folder and drives the **real** key handler and file operations through copy, cut, paste, undo, rename (including the second-click rename), delete, restore, navigation, tabs, view modes, type-ahead, sorting, grouping and section folding, search, shortcut re-mapping, pinning, folder icons, right-click routing and the safety of archive extraction against crafted entry names. the language layer (every shipped language loads, keeps its placeholders and plural forms) and **171 checks** in all. The suite is deterministic: it never depends on the order background transfers land in.

The suite runs **locally**, before a commit reaches GitHub:

```bash
./Tools/check.sh          # build + self-test, exits non-zero on failure
```

A pre-push hook runs the same gate on every push to `main` (36 seconds, no queue, no network). It blocks the push if a check fails; `git push --no-verify` overrides it, `FE_SKIP_PREPUSH=1` skips the hook entirely. Install it once per clone with `git config core.hooksPath .githooks`.

GitHub Actions is kept for what it is uniquely good at: checking the **released artifact**. When a release is published, `.github/workflows/release.yml` compiles the source in a clean environment, runs the suite, then downloads the very zip the in-app updater serves and verifies its Developer ID signature, its notarization ticket and its staple, and runs the suite again **on the shipped binary**.

Development helpers: `WINEXP_START=<path>` opens at a folder, `WINEXP_LANG=<code>` forces the interface language, `WINEXP_SNAPSHOT=<file.png>` writes a screenshot of the window, `WINEXP_SIZE=1400x900` opens at a given size, `WINEXP_TEST=menu:context|dialog:settings|dialog:about|dual|dual-home|rename|archive|compare|marquee|drop` opens a particular menu, dialog or layout for inspection, and `WINEXP_DEMO=<dir>` drives the scripted tour that produces the animation at the top of this page.

## Deliberate differences

- **Extensions are shown by default.** Windows hides known ones. The toggle is in `View > Show > File name extensions`.
- **The Recycle Bin is the macOS Trash**, so deleted items land where the rest of the system expects them. *Restore* only knows the origin of items File Explorer itself deleted: the Finder keeps its own "Put Back" records private.
- **Drives.** The boot volume is labelled `Local Disk (C:)`, other locally mounted volumes appear under This PC by their own names, and network-mounted volumes appear only under Network.
- **"Account disconnected"** reports what is actually on the Mac. It reads *iCloud Drive* or *OneDrive* when either is present, and *Account disconnected* when neither is.
- Archive browsing is read-only. Dropping files into a zip is not supported.
- **Undo history is per pane.** Each pane undoes its own operations; Windows keeps one history per window.
- **A dragged selection carries the item under the pointer.** Windows drags the whole selection.

## Changes in this fork

Fork of [gmazaratti/windows-explorer-mac](https://github.com/gmazaratti/windows-explorer-mac), maintained by [Alessandro Del Rosso](https://github.com/Swallow74). Everything below was added on top of the original 1.0 code base.

**File operations**
- **Replace or Skip Files** dialog, as in Windows: replace, skip or keep both when the destination already has the names.
- **Progress dialog** modelled on the Windows 11 copy window: percentage, live speed graph, name, time left and item count.
- **APFS clones** for same-volume copies: instant at any size, free until modified. exFAT and network mounts fall back to the byte copy.
- **Eject** for external drives and network shares, from the context menu and the sidebar.
- **Delete on network shares**: volumes without a Recycle Bin (SMB/NAS) offer a permanent delete instead of failing silently.
- Safer transfers: a failed cross-volume move records its orphaned copy so undo can remove it, same-volume moves advance the bar per item, cancel no longer stalls the main thread, copy collisions always get the `- Copy` suffix.
- Undo and redo are honest: per-item failures are reported, only what really reverted is redoable, undoing *New folder* restores the same items, and every tab showing a touched folder refreshes.
- **Hostile archives refused.** A zip with a member named `-P` could write outside the extraction folder; entry names are now passed to `bsdtar` after `--`, and a folder copied into itself is rejected.

**macOS integration**
- **Thumbnails for far more formats**: images are decoded by content through ImageIO (a JPEG saved as `.webp` used to show only a generic icon, because Quick Look trusts the extension), with Quick Look as the fallback and the route for documents, text, code, audio, fonts and the rest; files nothing can draw are asked once, not on every redraw.
- **Default file manager** switch: takes over folder opening and *Show in Finder* requests system-wide (`NSFileViewer` plus the `public.folder` handler), and gives them back when turned off.
- **Finder tags**: colour dots in Details and icon views, a *Tags* submenu to set them; skipped on network volumes to keep listings fast.
- **Services menu**, **AirDrop**, *Show package contents*, **Spotlight** content search, Recycle Bin *Restore* and *Empty Recycle Bin*.

**Navigation and views**
- **Nav bar matches Windows 11**: a `⌄` history button between forward and up opens the tab's whole navigation history with the current page checked, and Refresh now sits after the address bar (before the search box) instead of beside the arrows.
- **Sidebar favourites**: drag a folder onto the navigation pane (not onto a row) to pin it, as in the Finder; right-click > *Unpin from Quick access* removes it; the sidebar updates at once.
- **Group by** is real: Name, Type, Date modified (Today, Yesterday, Earlier this week, and so on) and Size (Tiny to Gigantic), with collapsible section headers in Details, as in Explorer. Arrow keys follow the on-screen order, including folded groups.
- **Cloud drives in the sidebar**: iCloud Drive and every provider under `~/Library/CloudStorage` (OneDrive, each Google Drive account, Dropbox...) get their own entry under Gallery.
- **Navigation pane follows you**: the folder tree expands on its own down the path you are viewing, and is cached so it does not flicker or rescan.
- **User folders resolved through the system**: Desktop, Documents and the others still work when they have been moved or are symlinks.
- Home and This PC watch `/Volumes`, so an unplugged drive disappears instead of lingering.
- **Tabs**: right-click menu (duplicate, paste into tab, close), drop files onto a tab to land them in its folder, `Ctrl+Shift+T` reopens the last closed tab, a closed tab before the active one no longer changes the selection.
- `Ctrl+Scroll` zooms icons in discrete steps instead of a continuous, jumpy scale.

**Selection and input**
- **Quick Look**: `Space` previews the selected files like in the Finder (`Space` or `Esc` closes, arrows move along the selection); `Ctrl+Space` toggles the selection.
- `Shift`/`Ctrl`/`Cmd`+click uses the modifiers held **at press time**, so a quick click-and-release no longer collapses a multi-selection.
- Rubber-band selection no longer swallows clicks on open menus, and picks the right window when two Explorers are open.
- Inline rename commits on focus loss — a click anywhere outside the field (another file, empty space, the toolbar, the other pane) finishes the name without Esc, and that same click never reopens the edit; case-only renames work on case-insensitive APFS; shortcut re-mapping detects real conflicts.
- Column, pane-divider and details-pane resize track the pointer 1:1 (they used to compound).

**Network browsing**
- **Network page** with the machines the Mac finds on its own (Bonjour `_smb._tcp`/`_afpovertcp._tcp` plus an optional LAN scan), mounted shares and saved servers; tiles open into the shares, mounting through macOS without the Finder.
- **This PC keeps only local drives**; network volumes live under Network, as in Explorer.
- **Background listing**: opening a remote folder never blocks the UI; the wait card covers it until the items arrive.
- **Hide a computer**: right-click a Network tile and choose *Don't show on Network*; the link under the list (*Show hidden computers*) brings hidden ones back.

**Updates and distribution**
- **Update notification**: the app checks the GitHub Releases of the fork at launch (at most once a day) and from the app menu, and lets you skip a version.
- **One-click self-update**: it downloads the release, verifies it, replaces the installed app and reopens it. If that is not possible it opens the download page instead. A fork can point the check elsewhere with the `FEUpdateRepo` key in `Info.plist`.
- **Notarized releases** from 1.3.1: Developer ID signature, `Tools/release.sh` signs, notarizes and staples, `Tools/package.sh` builds the zip.
- `build.sh` builds arm64 for macOS 14+, checks that `swiftc` exists, and passes `FE_VERSION` to the bundle so the About panel shows the real version.
- **CI** on GitHub Actions: the release artifact is verified when a release is published — Developer ID signature, notarization ticket, staple, and the self-test suite run again on the very binary the updater serves. The push-time gate runs locally (`Tools/check.sh`, wired to a pre-push hook), so nothing waits in a runner queue.
- The README now says plainly that building needs a full Xcode, not just the Command Line Tools.

**Localisation**
- The interface is translated into 16 languages, with a language picker in Settings, automatic detection of the macOS language and an English fallback.

**Tests**
- The self-test suite grew from 49 to more than 171 checks, covering grouping, modifier capture at press time, hostile archive names, self-copy refusal and the tab and transfer paths.

Ideas and behaviours borrowed from other open-source Mac explorers (MacXplorer, MaXplorer, MacExplorer, explorer-macos) were **reimplemented from scratch**; no code from GPL projects is included.

## Credits

**Created by [Alex Degryse](https://www.linkedin.com/in/alexdegryse)**, [linkedin.com/in/alexdegryse](https://www.linkedin.com/in/alexdegryse) and [github.com/gmazaratti](https://github.com/gmazaratti)

**Fork and modifications by [Alessandro Del Rosso](https://github.com/Swallow74)**

Not affiliated with or endorsed by Microsoft. Windows, Windows 11, File Explorer, Segoe and Fluent are trademarks of Microsoft Corporation. All artwork in this project is original: the app icon is drawn from scratch by `Tools/MakeIcon.swift`, and the in-app iconography is original vector work laid out on Fluent's design grid.

## License

[Apache License 2.0](LICENSE).

- Copyright 2026 Alex Degryse (original work).
- Modifications copyright 2026 Alessandro Del Rosso (this fork, see [Changes in this fork](#changes-in-this-fork)).

You are free to use, modify and redistribute it, including commercially. In
return the licence requires that the [NOTICE](NOTICE) file travels with any copy
or derivative you distribute, which credits Alex Degryse and links back to the
original repository. If you ship it inside an app, that notice belongs in your
acknowledgements screen.
