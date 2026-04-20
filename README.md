# SafariIcons

A native macOS app that lets you fully customize the icons on Safari's Start Page and Favorites bar — drop in your own artwork, switch between the built-in icon styles, and lock the cache so Safari stops overwriting your changes.

Built with SwiftUI for macOS 26 (Tahoe).

## Features

- **Live favorites list** — reads `~/Library/Safari/Bookmarks.plist` and displays every bookmark on your Bookmarks Bar.
- **Custom icons via drag & drop** — drop any PNG / JPEG / ICO / SVG onto a site to replace its icon. Images are automatically downsampled, square-cropped and re-encoded to Safari-compatible PNG.
- **Three icon styles** — switch each site between `Glass · Small`, `Glass · Large` and `Transparent · Large`, matching Safari's native rendering modes (`transparency_analysis_result` codes `0` / `3` / `1`).
- **Lock / unlock the icon folder** — `chflags uchg` on `Touch Icons Cache/Images/` so Safari can't regenerate your custom icons. Toggle from the menu bar (`⇧⌘L` / `⇧⌘U`).
- **One-click Safari restart** — apply changes immediately with the rocket button (`⌘R`).
- **Reset to defaults** — wipe custom styles and let Safari rebuild icons from scratch (`⌥⌘D`).
- **Style code diagnostics** — inspect the raw `cache_settings` codes for every visible bookmark (`⇧⌘I`).
- **File-system watchers** — auto-refresh when Safari rewrites `Bookmarks.plist` or `TouchIconCacheSettings.db`.

## Screenshots

_Add screenshots or a short demo GIF here._

## Requirements

- macOS 26.0 (Tahoe) or later
- Xcode 16.2 or later (Swift 5.9+, SwiftUI Observation)
- Safari (the system Safari, not a standalone install)

## Installation

### Option 1 — Download the DMG

Grab the latest `SafariIcons.dmg` from the [Releases](../../releases) page, open it and drag **SafariIcons** into **Applications**.

Because the app is not notarized, macOS Gatekeeper may block the first launch. To open it anyway:

1. Right-click `SafariIcons.app` in `/Applications` → **Open** → **Open**, or
2. Run: `xattr -dr com.apple.quarantine /Applications/SafariIcons.app`

### Option 2 — Build from source

```bash
git clone https://github.com/<your-username>/SafariIcons.git
cd SafariIcons
open SafariIcons.xcodeproj
```

Select the `SafariIcons` scheme and press `⌘R`.

## Usage

1. **Launch** SafariIcons. On first run, click **Grant Access…** and select `~/Library/Safari/` in the open panel. This gives the app permission to read `Bookmarks.plist` and write to `Touch Icons Cache/`.
2. **Pick a site** from the grid — it shows every bookmark on your Bookmarks Bar.
3. **Drop an image** onto the site tile, or click the tile to open the detail sheet and choose a style / upload an image.
4. Hit the **rocket button** (top-right, `⌘R`) to restart Safari and see your new icons.
5. Once you're happy, **Lock Icons Folder** (`⇧⌘L`) so Safari doesn't overwrite your work on the next favicon refresh.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘R` | Restart Safari to apply changes |
| `⌥⌘D` | Reset to default icons (clears all custom styles) |
| `⇧⌘I` | Inspect style codes for the current list |
| `⇧⌘L` | Lock the icons folder |
| `⇧⌘U` | Unlock the icons folder |

## How it works

SafariIcons talks directly to Safari's on-disk icon cache — no private APIs, no injection:

- **Bookmarks** — parses `~/Library/Safari/Bookmarks.plist` (a standard property list) and walks the `BookmarksBar` folder.
- **Icon images** — each favicon is stored as `Touch Icons Cache/Images/<MD5(host)>.png`. SafariIcons writes your custom image to that exact path.
- **Icon style** — the `cache_settings` table inside `TouchIconCacheSettings.db` (SQLite) stores a `transparency_analysis_result` integer per host. SafariIcons updates that row with a direct `UPDATE`.
- **Lock flag** — `chflags uchg` is applied to the `Images/` directory to prevent Safari from rewriting your files.
- **Live updates** — `DispatchSource` file-system watchers on `Bookmarks.plist` and `TouchIconCacheSettings.db` keep the UI in sync.

## Permissions & privacy

- SafariIcons reads and writes **only** inside `~/Library/Safari/`. It never touches browsing history, passwords or cookies.
- No network calls. No analytics. No third-party dependencies.
- Access is granted once via `NSOpenPanel`. You can revoke it at any time in **System Settings → Privacy & Security → Files and Folders**.

## Packaging a release DMG

```bash
# 1. Archive a Release build
xcodebuild -project SafariIcons.xcodeproj \
           -scheme SafariIcons \
           -configuration Release \
           -archivePath build/SafariIcons.xcarchive \
           archive

# 2. Export the .app (uses exportOptions.plist — see Releases for a sample)
xcodebuild -exportArchive \
           -archivePath build/SafariIcons.xcarchive \
           -exportPath build/export \
           -exportOptionsPlist exportOptions.plist

# 3. Bundle into a DMG (requires: brew install create-dmg)
create-dmg \
  --volname "SafariIcons" \
  --window-size 540 380 \
  --icon "SafariIcons.app" 140 180 \
  --app-drop-link 400 180 \
  --hdiutil-quiet \
  "SafariIcons.dmg" \
  "build/export/SafariIcons.app"
```

## Contributing

Issues and pull requests are welcome. Please keep changes focused and add context in the PR description.

## License

Released under the [MIT License](LICENSE).

## Disclaimer

SafariIcons is not affiliated with or endorsed by Apple Inc. "Safari" is a trademark of Apple Inc. This project simply reads and writes files in a user-owned directory; use at your own risk and back up your `~/Library/Safari/` folder before experimenting.
