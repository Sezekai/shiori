# Shiori — product notes

## Who and what it's for

One owner, reading a large personal collection on a Windows laptop (and later an Honor Magic V3 phone). The collection is about 7,800 manga/doujinshi CBZ files, 2,200 comics (mostly CBR) and 216 art books. It combines Mihon/Tachiyomi's library, history, stats and tags with YACReader's local-folder reading.

## Constraints

- The library is **read-only**. Shiori never moves, renames, edits or deletes the owner's CBZ/CBR files. The only files it writes are its own data, caches and saved pages.
- Large libraries on a hard drive (E:) that may be disconnected.
- 16 GB of RAM: decoded pages are kept only near the current page, and loaded page data is capped at about 400 MB per open book.

## Stages

1. **Done:** the complete PC app.
2. **Done (1.3.0):** the Android companion (Flutter, same codebase): a PC server on home WiFi with discovery and pairing, streaming, offline downloads (CBR repacked as CBZ), offline browsing with every cover, two-way sync of reading data, save-page requests sent to the PC, foldable layouts, and app lock. Reading away from home (Tailscale) is out of scope for now.

## Decisions for this app (STANDARDS.md "App chooses" and "When relevant")

- **Toolkit:** Flutter, so the Android app shares the library, reader, history and stats code. DESIGN.md's tokens are rebuilt in `lib/ui/look.dart`, and theme files use the same format as the other apps.
- **Storage format:** SQLite for the library (`library.db`), JSON for settings and appearance. The database is backed up daily, keeping 7 copies.
- **Watching folders:** yes, plus a quick rescan at start-up.
- **Memory:** no cap setting yet. The reader keeps about 400 MB of page data per book and decoded images only for nearby pages. Covers are 360 px wide JPGs.
- **Covers:** made in background isolates (pure Dart decoding), so the window never waits on them. The number of workers follows the CPU (2–6).
- **CBR:** read with the bundled 7-Zip (`App\tools\7z.exe`). A CBR is unpacked once to `Cache\pages` when opened, while single pages are pulled out directly so reading can start immediately.
- **Files on disk:** the Recycle Bin, move log and undo rules don't apply, because Shiori moves and deletes none of the owner's files. Saved pages are never overwritten (" (2)" is added).
- **Sensitive content:** the owner chose **no NSFW flag**, which differs from STANDARDS.md "Sensitive content".
- **Rail:** used as normal, with three section items plus History, Stats and Saved.
- **Keys added for this app:** R random title; 1 2 3 sections; D two pages, O cover offset, C crop, P save page, V favourite, N next file, G page strip (reader).

## Differences from the standards, with reasons

- **Fonts:** only Inter (and JetBrains Mono for the log and paths) are bundled, to keep the download small. The other bundled fonts in DESIGN.md aren't included. System fonts can be picked, and "Add font…" isn't built yet.
- **Colour pickers:** each token has a hex field and a swatch picker from the presets, not a full colour wheel.
- **GPU chip:** not shown. Shiori has no GPU jobs.
- **Window snapping:** the title bar is drawn by the app (window_manager). Edge snapping and dragging work, but the snap-layout flyout on the maximise button doesn't.
- **Pause/resume:** scans and cover making can be paused. A scan that's stopped carries on from where it got to next time, because finished files are already in the database.

## Never in it

- Online sources, extensions or tracking services (AniList, MAL).
- Editing, converting or moving library files.
- The art books `Archives` folder (loose image folders, JPEG 2000 and PDFs). The owner chose to leave it out.
