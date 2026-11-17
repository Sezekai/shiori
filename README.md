# Shiori

A library and reader for large collections of manga, comics and art books in CBZ and CBR files. It mixes the library, history and stats of Mihon/Tachiyomi with YACReader's local-folder reading.

This is stage 1: the complete Windows app. Stage 2 adds the Android companion that reads from this PC over home WiFi.

## Install and update

1. Download `Shiori-vX.Y.Z-windows.zip` from the latest [release](../../releases).
2. Unzip it to `E:\Pictures\`. You get `E:\Pictures\Shiori\App\Shiori.exe`.
3. Run `Shiori.exe`. No installer and no admin rights are needed.

**Updating:** replace the `App` folder with the new one. Your library, history, settings and covers are kept, because they live outside it.

## Where things live

| What | Where |
| --- | --- |
| The program | `E:\Pictures\Shiori\App\` (replaced by each update) |
| Cover thumbnails | `E:\Pictures\Shiori\Cache\thumbs\` |
| Unpacked CBR pages | `E:\Pictures\Shiori\Cache\pages\` (cleared down to 2 GB at start-up) |
| Library database: titles, history, ratings, tags, saved-page memory | `%LOCALAPPDATA%\Shiori\library.db` |
| Settings, appearance and themes | `%LOCALAPPDATA%\Shiori\settings.json`, `appearance.json` |
| Logs and crash logs | `%LOCALAPPDATA%\Shiori\logs\` |
| Database backups (last 7 days) | `%LOCALAPPDATA%\Shiori\backups\` |
| Saved pages | One folder per section, set in Settings (default `E:\Pictures\Shiori\Saved Pages\…`) |

Settings → Storage shows each place with its size, and can open, move or clear it.

## Features

### Library
- Three sections, **Manga**, **Comics** and **Art Books**, each with its own folders, filters, tags, history, stats and save folder.
- Default folders: `E:\Pictures\IMGs\Doujinshi`, `E:\Documents\COMICS`, and `E:\Documents\ART BOOKS & GUIDES` (skipping its `Archives` folder).
- Folders are watched, so new files appear by themselves. A quick rescan runs at start-up; unchanged files are skipped.
- History follows the file, not its path: each file is identified by its size and a fingerprint of its start and end, so moving or renaming keeps ratings, history and tags. Missing files are marked "Not found", not removed. If E: isn't connected, the library still opens.
- Grid styles: Comfortable, Compact, Cover only and Staggered, with the size set by the slider or Ctrl + mouse wheel. There's also a sortable List view.
- A progress line on each cover, plus badges for series progress, favourite, rating and times read.
- Manga chapters (`Ch. 2`, `Part 2`, trailing numbers, `Zenpen`/`Kouhen`) group into one series card. Comics can be browsed by **Folders** (in your reading order) or **Series**.
- **Title page:** cover, details, rating, favourite, tags, history, "Edit details", "Choose cover page", "Show in folder". For a series: the chapter list with ticks, "Mark previous as read", and select-and-mark read or unread.
- **Filters** (click once for the filter, again for its opposite): read, in progress, favourite, rated, series, needs a title check, rating range, pages, file size, times read, read recently, tags and artists. Active filters show as pills. Filters plus sort can be saved as **presets**.
- **Sort** by title, artist, size, pages, rating, date added, last read, first or last completed, times read, time spent, progress, or random. Every sort can be reversed.
- **Random** picks a title from what's shown (R).
- **Tags:** colours, drag to reorder, and the titles inside a tag in your own order (a queue) or any sort.
- **Artists:** every artist with title count, read count and average rating.
- **Check titles:** names where the English title might be split wrongly, for a quick fix.
- **YACReader import:** read marks, current page, ratings, favourites, and labels and reading lists (as tags). It's offered after the first scan, and is also in Settings.

### Reader
- Left to right, right to left, or top to bottom (page by page or a continuous strip). Each section has a default, and any title can override it.
- Fit screen, width, height or original size; zoom with ↑ ↓, + −, Ctrl + wheel or double-click; drag to pan.
- One page, two pages, or Auto (two when the window is wide). Cover offset (O). Wide pages can be split into halves in reading order: always, never, or only in single-page mode.
- Crop borders (C) trims plain white or black margins.
- Page number in a corner, a page strip (G), and a page slider.
- Every page of the open file loads in the background, nearest pages first.
- **Save page (P):** saved in the original format, JPG (with a quality setting) or PNG. With two pages showing, choose left, right, or both combined into one image. Shiori never overwrites a file, and never saves the same image twice, even after you move the saved images away. The Saved pages screen lists every save, with "Forget this save".
- **End of file:** a short screen with rating, favourite and tags, then **Next** (the next chapter, or the next title in the list you came from; in Comics, the folder order). An option skips chapters already read.

### History and stats
- Every session: start, end, active reading time (idle time isn't counted), pages from and to, and pages seen.
- Every completion is recorded, so read counts go up with each re-read. First and last completion dates can be sorted and filtered.
- Stats per section or across all three, for all time, this year, this month or the last 30 days. They cover totals, pages and hours per month, a reading calendar, streaks, reading by hour, ratings, most-read artists, most re-read titles and best-rated artists.

## Keys

Press **K** in the app for the full list.

| Key | Does |
| --- | --- |
| K | Keyboard shortcuts |
| /, Ctrl+F | Search |
| F, F11 | Full screen |
| H | Hide panels |
| M | Show or hide the sidebar |
| L | Log |
| S | Settings |
| 1 2 3 | Comics, Art Books, Manga |
| **Library** | |
| Arrows, PgUp PgDn | Move the highlight |
| Enter, click | Open (a series opens its page) |
| Space, middle-click | Show details on the right |
| D | Show or hide the details panel |
| Ctrl+click, Shift+click | Tick one, tick a range |
| R | Random title |
| Ctrl+A | Tick everything shown |
| **Reader** | |
| ← → | Previous / next page, following the reading direction |
| PgUp PgDn | Previous / next page |
| Space | Show or hide the controls |
| Home End | First / last page |
| ↑ ↓ | Zoom (scroll in strip mode) |
| 0, 1 | Fit; actual size |
| T, O, C | Two pages, cover offset, crop borders |
| D | Details |
| P | Save page |
| V | Favourite |
| N | Next file |
| G | Page strip |
| Esc, mouse back | Close, innermost first |
| **Dialogs** | |
| ← →, Enter, Esc | Pick a button, press it, cancel |

## For the developer

- Flutter (Dart) for Windows now and Android in stage 2, sharing one codebase.
- `lib/core/`: database (SQLite), file-name parsing, archives (CBZ via `archive`, CBR via the bundled 7-Zip), scanning, jobs and progress, saving pages, YACReader import.
- `lib/ui/`: the shell (title bar, rail, status bar, log, keys popup), library, title page, reader, history, stats, settings and appearance.
- `flutter test` runs the unit tests (file-name parsing, archives, cover queue).
- `Shiori.exe --selftest` (CI runs it on the built app) makes sample books, scans them, makes covers, opens the reader, and takes screenshots of each screen into the data folder's `logs\`. Use `SHIORI_ROOT` and `SHIORI_DATA` to point it at test folders.
- GitHub Actions builds on every push to `main`. It runs the tests, builds the app, bundles 7-Zip, runs the self-test, and publishes a release named after the version in `pubspec.yaml`. Raise the version for every release.
