# App standards

Version 1 (November 2026). How every new app behaves, stores its data, is built and is released. Its partner, DESIGN.md, says how the app looks. Each topic lives in only one of the two files; if anything ever seems to disagree, **this file wins**.

These standards are for **new apps**, and for existing apps only when the owner decides to bring one in line. Never change an existing app to match these files unless the owner asks for that app.

Words used here:

- **Default:** every new app does it.
- **When relevant:** do it whenever the app has the thing described (videos, a queue, files it moves…). If unsure, ask the owner.
- **App chooses:** no rule; pick what suits the app and say why in its PRODUCT.md.

An app may break a Default only for a clear reason, written in its own copy of this file (see "Docs in each app's repo").

---

## 1. Who and what these apps are for

- **One owner** uses these apps on their own Windows laptop: a Lenovo IdeaPad Gaming 3 (Ryzen 5 5600H, 16 GB RAM, about 14 GB usable). It has two GPUs: an AMD integrated GPU and an **NVIDIA RTX 3060 Laptop GPU with 6 GB of video memory**. Only the NVIDIA GPU can run CUDA.
- **Screens:** mostly a 27" 1440p monitor, sometimes the 15" 1080p laptop screen.
- **Drives:** the laptop drive (C:) is small. Large things live on the **hard drive, E:** (`E:\Pictures\…`). E: is sometimes not connected, so apps must cope.
- **The work:** large personal collections of anime art, images, videos and music, organised in folders.
- **The owner doesn't build or install anything by hand.** Apps arrive ready to run from GitHub.

## 2. Files on disk: safety first

These rules have no exceptions.

### Nothing is permanently deleted (Default)

- Every removal goes to the **Recycle Bin**: `shell.trashItem` in Electron, `Send2Trash` in Python, `FileSystem.DeleteFile(…, RecycleOption.SendToRecycleBin)` in .NET.
- Before removing anything, show an in-app dialog that **names the file** and says what happens to everything related ("Its 2 other versions also go to the Recycle Bin").
- If the Recycle Bin can't take a file (for example on some network drives), stop and say so. Never fall back to a permanent delete.
- The app's own temporary files (staging folders, partial downloads) may be deleted normally.

### Nothing is overwritten (Default)

- New files go beside the original with a descriptive suffix (`name__artwork_medium_2x.png`).
- If a name is taken, add " (2)", " (3)"…
- Renames and moves never replace an existing file.
- Original files are never edited in place unless that's the whole point of the action and the owner confirmed it.

### Every move is logged and can be undone (Default)

- Any action that moves, renames or sorts files writes a **move log**: when, what, from where, to where.
- The log is visible in the app, and every entry has **Undo**. **Ctrl+Z** undoes the last move.
- Undo explains itself when it can't work ("That file was moved outside the app, so it can't be undone").
- The log is kept in the app's data (see section 3), so it survives restarts and updates.

### Remember "done" and "skip" (Default)

- In apps that process folders repeatedly, finished or rejected items **never come back** on a rescan.
- Examples: a kept upscale, a song deleted with "skip its videos in future", a sorted image.
- **Settings → Reset** has an entry that forgets these, after asking.

### Review before moving (When relevant)

- In apps that sort or move many files, nothing moves until the owner has seen the plan (source → destination) and approved it, with the option to change single items.

### Keep best, bin the rest (When relevant)

- In apps that make or find several versions of one file, the owner picks the best version.
- The best version moves into a named subfolder beside the original. The folder name is chosen per app, for example `Upscaled Images`.
- Keeping the original as well is an option: it moves to its own subfolder, for example `Upscaled Images - Originals`.
- Everything else goes to the Recycle Bin.
- The item then leaves the list for good, and those subfolders are never scanned again.

### Sorted folders with NSFW and Very (Default for apps that sort art)

- Any sort destination can have an **NSFW** subfolder, and inside it a **Very** subfolder (for explicit art): `Folder\NSFW\Very`.
- Sorting offers NSFW and Very toggles for each file.

### Default names you can change (Default for apps that create files)

- Every output gets a sensible automatic name (source name + what was done).
- The owner can type a different name before saving.

## 3. Where things live

### The folder layout (Default)

```
E:\Pictures\<App>\            <- the app's root folder on the hard drive
    App\<App>.exe            <- the program; replaced by each update
    Models\                  <- AI models and engines
    Cache\                   <- thumbnails, previews, waveforms (safe to delete)
    Library\                 <- big files the app keeps (or a clearly named folder, e.g. Songs)
%LOCALAPPDATA%\<App>\         <- small files: settings, databases, logs, theme, move log
```

- **Small things go in `%LOCALAPPDATA%\<App>`:** settings, databases, indexes, logs, the move log, the appearance file, added fonts, window positions.
  - These must survive updates and stay on the fast drive.
- **Large things go on the hard drive,** in folders beside the program: AI models, engines, caches and libraries.
  - "Large" means anything that can grow past about 100 MB.
- **Finding the root:** if the program sits in a folder called `App`, the root is the folder above it. Otherwise the root is the program's own folder.
  - When run from source, use a `dev-root` folder inside the repo, never the real E: folders.
- **Overrides for tests:** `<APP>_ROOT` and `<APP>_DATA` environment variables replace the root and the data folder, so tests and CI never touch real data.
- **Fast cache plus bulk cache (When relevant, ask first):** for huge libraries (100k+ files), small thumbnails may go on the fast drive with everything else on E:. Ask the owner before putting anything big on C:.

### Settings → Storage (Default)

Every app's Settings screen has a **Storage** section listing every place the app keeps anything. For each one it shows:

- **What it holds** ("AI models", "Thumbnail cache", "Settings and library database").
- **The path.**
- **The size,** worked out in the background and shown as "Working out…" until then.
- **Open folder.**
- **Move…:**
  1. Pick a new place.
  2. The app copies everything there, with the full progress display (bar, %, elapsed, time left, MB/s).
  3. It checks the copy (file count and sizes).
  4. It switches to the new place.
  5. Only then does it delete the old copy. This is the app's own data, not the owner's files, so a normal delete is fine.

  Moving is refused while a job is running. When the small-data folder moves, a pointer file in `%LOCALAPPDATA%\<App>` remembers where it went.
- **Clear** (caches only), after asking, saying how much space comes back.

If a folder's drive isn't connected:

- The app says which folder and drive are missing.
- It keeps working with what it can reach.
- It offers **Retry** and **Choose a new place**.
- It never quietly creates an empty folder somewhere else.

### Reuse what other apps already have (Default)

- Before downloading a model, key or tool, check whether another of the owner's apps already has it, and offer to use that copy.
  - Example: Nirvash reads CLIP from Collection Sorter's `%LOCALAPPDATA%\Collection Sorter\models\clip`.
- Only download it if it isn't there, and say where it will go.

### Storage formats (App chooses)

- Settings are a JSON file.
- For libraries and indexes, choose what suits the app: JSON for a few hundred records, SQLite for thousands or more.
- Write files safely: write a temporary file, then rename it over the old one, so a crash never leaves a half-written file.

## 4. Building and releasing

### GitHub (Default)

- Every app is a **private GitHub repository** under the account `Sezekai`, named after the app.
- **GitHub Actions** builds on `windows-latest` on **every push to `main`**. The owner never builds anything.
- The workflow does, in order:
  1. Install dependencies.
  2. Run the tests.
  3. Fetch the bundled tools.
  4. Build.
  5. Run the self-test of the packaged app.
  6. Publish the release.
- If any step fails, nothing is published.

### Releases (Default)

- Each build is published as a **GitHub Release named after its version** (`v1.4.0`). The version comes from one place in the code (`package.json`, `__init__.py`, the `.csproj`).
- Raise the version for every change the owner should download, so older versions stay available.
- **No Actions artifacts:** they used up the storage quota before.
- The workflow creates the tag itself (tag pushes from build sessions are blocked).
- The release notes say what changed in plain words.

### Package (Default)

- **One portable `.exe`** (Electron: electron-builder `portable`; Python: PyInstaller `--onefile`; .NET: single-file self-contained).
- **A zipped folder** only when big native libraries or start-up speed need it (for example mpv, LibVLC or ONNX). It unpacks to `<App>\App\`.
- No installer, no admin rights, nothing written to Program Files or the registry.
- **Updating = replacing the `App` folder (or the .exe).** Nothing else is touched.

### Bundled tools (Default)

- The build downloads the tools the app needs (FFmpeg, mpv, fpcalc…) and ships them inside the package, with their licence files.
- Copyleft engines that can't be bundled (for example AGPL ones) are downloaded at run time, after asking, into `Models` or the root. Never put them in the repo.

### Testing (Default)

- **Unit tests** cover parsing, file rules (never overwrite, Recycle Bin, undo), settings and anything with maths.
- **Self-test of the packaged app:** CI starts the real built app in a test mode (`--selftest` or an environment variable).
  - It checks that the page or window comes up with no errors.
  - It saves screenshots and a log to the job output.
  - If it fails, nothing is published.
- **Real-window checks during development:** before handing over, run the app's actual UI (not only a browser preview) and look at screenshots at the minimum window size and at 1440 and 1920 wide.

## 5. While the app runs

### One window only (Default)

Opening the app again brings the running window forward instead of starting a second copy.

### The window never freezes (Default)

Scans, conversions, downloads, lookups and AI work run in the background. The window stays responsive, and every job can be stopped.

### Progress you can trust (Default: the owner's rule)

Every download and every task, of any length, shows:

- **A progress bar.**
- **A percentage.**
- **Time elapsed.**
- **Time left.** While the rate is unknown, show "working out time left…".

Details:

- **Downloads** also show bytes and speed: "1.21 GB of 3.01 GB · 11.8 MB/s".
- **Proof it's running:** there must always be visible proof, not just a label. If a step can't report a size, use a sliding bar and say "size not known yet" while elapsed time keeps counting.
- **Stalls:** after 20 seconds with no new progress, the status turns to a warning colour and says how long it's been, and that the log shows what is running.
- **Cap at 99%** until the task has truly finished.
- **Steps and items:** where a task has steps or items, each shows its own state: Done, current, Queued, Failed.
- **Finishing:** the status says what happened ("Finished: 6 made, 0 failed · took 2:04") and offers the next step. It never silently clears.

### A queue, not "busy" (Default)

- Starting work while something runs **adds it to a queue**. Buttons never go disabled just because a job is running; they say "Add … to the queue".
- One progress bar covers everything queued ("12 of 40 · 8 more queued").
- **Stop** stops the current item and empties the queue. Finished work is kept.

### Pause and resume long jobs (Default)

- Long scans can be paused and resumed.
- Progress is saved at least every minute, so Stop or a crash keeps the work done so far, and the next run carries on.

### Nothing downloaded without asking (Default)

- Big downloads (models, engines) wait for a button.
- The button says what it is, how big it is and where it goes.
- Then the full progress display runs.

### The log (Default)

- **In the app:** everything the app does is written to a log the owner can open (L, or the Log button). It opens by itself on an error.
- **On disk:** the log is also saved in `%LOCALAPPDATA%\<App>\logs\`, keeping the last few runs.
- **Long jobs** (installs, big scans) get their own log file, named in the app.

### Crash safety (Default)

- **Crash log:** unhandled errors and native crashes are written to `logs\crash-<date>.txt` with what was happening.
- **Safe mode:** after **two unclean exits in a row**, the app starts with its risky features off (for example the GPU renderer or hardware decoding). It says why and offers to turn them back on.

### Diagnose and repair (Default for apps that depend on drivers or engines)

When something the app depends on doesn't work (the GPU, an engine, a model), the app can find out why:

- **Diagnose** runs real checks and lists findings in plain words. Each finding has what was found, the evidence, and a **Fix:** line.
- **Repair** applies the fix when the app can do it itself (for example reinstalling a matching PyTorch build).
- **Copy report** puts a full text report on the clipboard, and it's also saved in the logs folder.

### GPU (Default for apps that use it)

- Use the NVIDIA GPU when it works, and **fall back to the CPU** (or a slower path) when it doesn't, without failing.
- **Always show which is in use.** While a GPU job runs, a status chip shows the GPU, its load and memory, updated every 2 seconds ("RTX 3060 Laptop GPU · 87% · 3.1 / 6.0 GB"). On the CPU it says "On the CPU (slow)" in the warning colour.
- **Match CUDA builds to the driver:** for example CUDA 13 needs driver 580 or newer, so pick a build the driver supports, and say which.
- Settings has **Use: Auto / GPU / CPU**.
- The AMD integrated GPU can't do CUDA. Don't present it as a choice for CUDA work.

### Memory (App chooses)

- How much memory to use is up to the app.
- **Memory caps (Default for memory-hungry apps):** an app that can use a lot of memory or video memory (caches, previews, GPU textures) has a setting for the most it may use, plus "Automatic" (use what's free, leaving a reserve for other programs).

### Watching folders (App chooses)

Choose per app:

- **Watching folders** (lists update by themselves) suits apps that stay open on a library.
- **Rescanning when asked** suits apps that process a folder once.

### Sensitive content (Default)

- **NSFW and Very filters always start off** when the app opens. They're never saved, so the app never opens showing them.

### Videos (Default for apps that show videos)

- **Only one video plays at a time.** Starting one pauses the other.
- **Volume is remembered** between videos and between runs.
- **Hover previews:** resting the mouse on a video tile plays a short silent preview.
- **Videos start from the beginning.** Positions are not remembered.
- No paused or watched outlines on tiles.

### Keyboard (Default)

Every new app uses these meanings. Keys an app needs for itself use letters that aren't in this table. Every app lists its keys in its keyboard shortcuts popup (K), described in DESIGN.md under "Keyboard shortcuts popup".

| Key | Does |
| --- | --- |
| K | Open or close the keyboard shortcuts popup, on any screen |
| / | Search. In an app whose main box is for sorting or filtering, it jumps to that box instead. Ctrl+F does the same. |
| F, F11 | Full screen |
| H | Hide the panels, so only the content shows (press again, or Esc, to bring them back) |
| L | Open or close the log |
| M | Show or hide the sidebar / menu |
| S | Settings |
| Space | Play / pause; in a comparison view, hold to see the original |
| ← →, PgUp PgDn | Previous / next |
| Home, End | First / last |
| ↑ ↓ | Zoom in an image viewer; volume in a video player |
| + −, Ctrl + mouse wheel | Make whatever is in view bigger or smaller (zoom, thumbnail size) |
| 0, 1 | Fit; actual size (100%) |
| Ctrl+Z | Undo the last move |
| Esc | Close or leave, innermost first (the shortcuts popup or a dialog, then full view, then full screen, then the log) |
| Ctrl+Shift+I | Developer tools (for bug reports) |

Notes:

- **/ is the key on its own** (no Shift); ? isn't used.
- **Letters do nothing while typing** in a text box.
- **Clicking an item selects it;** Ctrl+click or its tick box ticks it; Shift with either ticks a range (see DESIGN.md, "Selecting and ticking").

## 6. Settings

### The Settings screen (Default)

- Opened with **S** or the Settings item in the rail.
- **Grouped sections**, each with a one-line explanation:
  - the app's own options;
  - **Storage** (section 3);
  - GPU or engine, when used;
  - **Reset**.
- Changes apply straight away. There's no Save button.

### Reset, one part at a time (Default)

The Reset section has a separate button for each kind of data, and **each asks first**, saying exactly what is cleared and what stays. Typical parts:

- **Settings:** back to defaults.
- **Library / index:** the app forgets its list, but the files stay on disk.
- **Skips and "done" memory:** the things from "Remember done and skip".
- **Move log.**
- **Cache:** the same as Storage → Clear.

Resetting never deletes the owner's files, themes or installed engines unless that part says so.

### Appearance (Default)

Every app has the full Appearance screen (themes, colours, gradients, fonts, corners, density, theme files) described in DESIGN.md.

## 7. Working with collections

### Folder tree with counts (Default for apps that work across folders)

- Folders are added (as many as wanted), not chosen one at a time.
- A tree lists them with subfolders and counts; clicking a folder filters to it and everything under it. Ticks are kept when the filter changes.
- Removing a folder from the list never touches the disk.

### Filters with opposites (Default for apps with libraries)

- Every filter has its opposite (Favourite / Not favourite, Played / Not played), and filters combine.
- The active filters are always visible and easy to clear.

### List, Grid and Gallery (Default for apps that show images)

- The same items can be seen as a list, a grid or a one-at-a-time gallery.
- Thumbnail size has a slider plus **Ctrl + mouse wheel**.
- Every column sorts.

How each view looks is in DESIGN.md.

### Own settings per item (When relevant)

- In batch apps, chosen items can have their own settings, overriding the defaults.
- **Use defaults** clears them.
- The list shows which items have their own settings.

### Count badges and title-bar status (When relevant)

- **Count badges:** apps with queues or inboxes show small counts on rail icons ("3 waiting").
- **Status pills in the title bar:** apps that run background work show it there, so it's visible on every screen (see DESIGN.md).

### Import into the app's own folders (App chooses)

Whether processed files move into folders the app owns is decided per app.

## 8. Words

- **Plain English** everywhere: labels, buttons, errors, logs meant for the owner.
  - Say what happened and what to do next ("The GPU ran out of memory. Choose a smaller tile size.").
  - No jargon, no error codes on their own, no "Oops".
- **Buttons say what they do** ("Upscale 12 images", "Send to Recycle Bin"), not "OK".
- **Sizes and times are human:** "1.2 GB", "about 3 min left".

## 9. Docs in each app's repo

Every app's repo has:

- **README.md:** what the app does, how to install and update it, where things live (the folder table), every feature, the keys, and how the developer builds and tests it.
- **PRODUCT.md:** who it's for, its purpose, constraints, what's never in it, and anything decided for this app that differs from these standards (with the reason).
- **Its own copies of DESIGN.md and STANDARDS.md,** copied from this repo when the app is created. Changes specific to that app are made in its copies; don't link back here.
  - When the shared versions improve later, the owner decides whether to copy the changes into an existing app.

## 10. Starting a new app: checklist

1. Plan the app with the owner before building; settle anything in these files marked "When relevant" or "App chooses".
2. Create the private repo `Sezekai/<app>`. Copy in DESIGN.md and STANDARDS.md, and write README.md and PRODUCT.md.
3. Set up the folder layout (section 3), with the root and data overrides for tests.
4. Build the window shell from DESIGN.md: title bar, rail, status bar, log drawer, keyboard shortcuts popup, Settings (with Storage and Reset), and Appearance.
5. Put in the file rules (section 2) and the progress display (section 5) before any feature uses them.
6. Write the GitHub Actions workflow: tests → build → packaged self-test → numbered release.
7. Before handing over, check it in the real app at 1100, 1440 and 1920 wide, and give the owner the release download link.
