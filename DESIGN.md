# Design guideline

Version 1 (November 2026). How every new app looks. Its partner, STANDARDS.md, covers how the app behaves (files, data, progress rules, keyboard, settings). Each topic lives in only one of the two files; if anything ever seems to disagree, **STANDARDS.md wins**.

These rules are for **new apps**, and for existing apps only when the owner decides to bring one in line. Waifu2x Batch is the closest existing example and has working code for most of this page (the Appearance screen, theme engine, status bar and views), but it keeps its own design.

## Mode and scene

**Operate.** One person on their own Windows PC (a 27" 1440p monitor, sometimes the 15" 1080p laptop screen) works through folders of images, videos and files.

- **The screen is mostly the work:** lists, images, results.
- **Controls** stay small, aligned and in the same place in every app.
- **The look** is dark, compact, flat and calm. Colour is used for meaning, not decoration.

## Default look

| Part | Default |
| --- | --- |
| Background | Obsidian (neutral near-black) |
| Accent | Lime → Teal gradient (`#b6f05a` → `#2fd6b4`, 90°) |
| Font | Inter, 13 px |
| Corners | Standard: 6 px on controls, 10 px on panels |
| Density | Compact: 28 px controls, 24 px rows |
| Buttons | Flat |

Every one of these can be changed on the app's Appearance screen (see Appearance) and saved as a theme. Themes move between apps as theme files.

## Colour tokens

Every colour on screen comes from one of these tokens. Nothing else is hard-coded, except the black labels drawn over images and the category colours below.

| Token | Job | Obsidian |
| --- | --- | --- |
| `ground` | Window and title bar background | `#0a0a0b` |
| `rail` | Side rail | `#060607` |
| `panel` | Panels, status bar, drawers | `#111113` |
| `raised` | Buttons, cards, chips | `#19191c` |
| `raised2` | Hover, selected segment, progress track | `#232327` |
| `field` | Text boxes, lists, tables | `#070708` |
| `line` | Borders and dividers | `#212125` |
| `line2` | Stronger borders, checkbox edges | `#2e2e33` |
| `text` | Main text | `#ececee` |
| `sec` | Secondary text, labels | `#a0a0a7` |
| `faint` | Hints, placeholders, metadata | `#7d7d84` |
| `stage` | Behind images and videos | `#040405` |
| `ok` / `warn` / `danger` | Success, warning, danger | `#52d39a` / `#f2b64c` / `#f0616d` |
| accent stops | 1 to 4 colours and an angle | `#b6f05a`, `#2fd6b4`, 90° |

Derived values:

- **Gradient (`grad`):** drawn from the stops. With one stop, it's a solid colour.
- **Text on the accent (`on-acc`):** dark (`#0b0c0f`) or white, whichever has the better contrast against every stop. It can be pinned to dark or light.
- **Tints:** for selection and hover, the accent is mixed into the surface. About 9% for the selected row, 13% for ticked rows, 20% for active pills.
- **Contrast:** text, secondary text and faint text all stay at **4.5:1 or above** on `panel`. Every preset is checked against this.

### The accent is only for

- the main button (one per toolbar),
- progress bars,
- a comparison seam,
- checkboxes, focus rings and the selected item,
- the active rail item,
- the logo tile.

Never use the accent as decoration.

### State colours

- `ok`: done.
- `warn`: needs attention (a stall, running on the CPU, a missing drive).
- `danger`: failed, and actions that delete.

They are never used for anything else.

### Category colours (the one extra palette)

When an app lets the owner group things, each group may carry a colour: categories, playlists, folder colours, tags they create. Use this fixed palette, in order:

`#9b86ff` `#2fe0c0` `#ff6fb1` `#ffbf5a` `#5aa8ff` `#5be38a` `#ff8a5c` `#d07bff` `#7fd4ff` `#f2e05a`

- **Where they show:** as a dot, a small swatch, or the colour of a tag's text and border, never as a panel fill.
- **What they never mean:** state.

## Type

- **One family for the whole interface.** Weights: 400 for text, 600 for buttons and labels, 700 for page titles.
- **Sizes:** 13 px text, 12 px captions and column headers, 15 px page titles. The text-size setting moves all three together.
- **Monospace** (JetBrains Mono) only in the log, in paths meant to be copied, and in hex colour fields.
- **Tabular (even-width) numbers** wherever digits line up: sizes, times, counts, percentages.
- **Bundled fonts:** Latin subsets, weights 400, 600 and 700, all under the SIL Open Font License:
  - Inter, Geist, Manrope, Figtree, Onest, Rubik, Lexend, IBM Plex Sans, Atkinson Hyperlegible Next, Ubuntu, Plus Jakarta Sans
  - DM Sans, Work Sans, Public Sans, Nunito Sans, Sora, Space Grotesk, Outfit, Red Hat Text, Albert Sans, JetBrains Mono

## Sizes

- **Control height (`--ch`):** every button, text box, drop-down and segmented control (28 px compact).
- **Row height (`--rh`):** list rows are 24 px. Two-line rows with a 32 px thumbnail are `--rh` + 20 px.
- **Gaps:** 8 px between controls and between panels, 10 px inside panels, 12 px around the page.
- **Labels:** field labels in toolbars share one 88 px column, so fields line up from row to row.
- **Corners:** `--rc` on controls, `--rp` on panels. Thumbnails use the control radius minus 1 px.
- **No shadows,** except on things that float: dialogs, pop-ups, toasts and a comparison seam's grip.

## Layout

```
┌───────────────────────────────────────────────────────────────────────────┐
│ App name · Screen                       [● Upscaling 12/40]    ─  ▢  ✕  │  title bar, 32 px, ground colour
├──────┬────────────────────────────────────────────────────────────────────┤
│ rail │ Title  One-line description of what this screen does                │
│ 64px │ ┌ toolbar panel ────────────────────────────────────────────────┐ │
│      │ │ Label  [ field ……………… ] [Browse] ☐ option │  [Stop] [Main]  │ │
│ tool │ │ Label  setting ▾  setting ▾  setting ▾  ☐ option         note │ │
│ tool │ └───────────────────────────────────────────────────────────────┘ │
│ tool │ ┌ work area: list, table or image, takes all the height ───────┐ │
│      │ │ summary · filter [All|Not done|Done] · view · sort · size … │ │
│ ──── │ │                                                               │ │
│ Look │ └───────────────────────────────────────────────────────────────┘ │
│ Set. │                                                                     │
│ Keys ├─────────────────────────────────────────────────────────────────────┤
│ Log  │ Job  file · settings …… ▬▬▬▬▬▱▱ 58%  1:12 elapsed · about 0:52 left  [GPU chip] [Stop] [Log] │
└──────┴────────────────────────────────────────────────────────────────────┘
```

### Title bar (32 px), no menu bar

- **No menu:** there's no File / Edit / View menu. Anything an app needs from one lives in the app itself: a rail item, a button, or a shortcut listed in the keyboard shortcuts popup (K).
- **The strip:**
  - It's the `ground` colour with a 1 px `line` underneath, running the full width, under the window buttons too.
  - On the left: the app name in `text` (12 px, weight 600), then `·` and the current screen in `faint`.
  - The whole strip drags the window.
- **Status pills (when relevant):** apps that run background work show it on the right of the strip, before the window buttons, as small pills.
  - A pill holds a short label, a mini progress bar and a %, for example "● Upscaling 12/40 · 34%".
  - Clicking a pill opens the status bar's detail or the log.
  - This keeps work visible on every screen.
- **Window buttons:** the system's minimise, maximise and close buttons sit on the right and follow the theme (background `ground`, symbols `sec`).
  - **Electron:** `titleBarStyle: 'hidden'` plus `titleBarOverlay`, updated with `setTitleBarOverlay` whenever the theme changes. Make the overlay 31 px tall (1 px shorter than the strip), so the line underneath shows under the buttons.
  - **WPF:** `WindowChrome`.
  - **PySide6:** a frameless window with your own three buttons, which still hands the frame's behaviour to Windows (see below).
- **Windows behaviour stays:** the window snaps to screen edges and corners, maximises when dragged to the top, restores when a maximised window is dragged, offers snap layouts and the system menu, keeps its shadow, and resizes from every edge. A maximised window never covers the taskbar.
  - **Electron and WPF** keep this with the options above.
  - **PySide6:** keep `WS_THICKFRAME`, `WS_CAPTION` and the maximise box on the window, extend the frame into the client area (DWM margins of −1) for the shadow, answer `WM_NCCALCSIZE` so the whole window is client area (insetting by the resize border when maximised), and answer `WM_NCHITTEST` with the edges and `HTCAPTION` for the draggable part of the strip. Media Toolbox's `shell.py` does this.
- **Full screen:** hides the strip.

### Rail (64 px)

- The logo tile is first, in the accent.
- **Tools come next,** each a 19 px icon with an 11 px label under it, so every item is named.
- **At the bottom:** Look (Appearance), Settings, Keys and Log. Keys opens the keyboard shortcuts popup (it isn't a screen); Log opens the log drawer.
- The active item gets a `raised` background and an accent icon.
- A small accent dot marks an item that needs attention (for example the engine isn't installed).
- **Count badges (when relevant):** apps with queues or inboxes show a small accent badge with a number on the icon's corner ("3").
- **M hides the rail** for more room, and M brings it back. The choice is remembered.
- **Viewer-first apps:** in apps where the content itself is the point and there are few tools (a media viewer like Ginkgo), the rail may be replaced by a top bar plus a hideable folder sidebar. Say so in PRODUCT.md.

### The rest of the window

- **Header:** one line: the title, then what the screen does, cut short with "…" when narrow.
- **Toolbar panel:**
  - Row one is the main input and the main action.
  - Row two holds the settings for that action.
  - Rows wrap on narrow windows; they never scroll sideways.
- **Work area:** fills the remaining height. A summary line with the filters, views and list buttons sits on top.
- **Side panels:** when a screen needs a list and a detail view, the list is a panel on the left (default 292 px).
- **Folder tree** (default 230 px): when an app works on several folders, they're listed in a tree on the left of the work area:
  - "All folders" first, then each folder with its subfolders and counts.
  - Clicking a folder filters to it and everything under it.
  - × on a folder takes it off the list.
- **Resizable and remembered:** side panels, the folder tree and table columns can be dragged wider or narrower, and come back at that size next time. Each has a sensible minimum, so nothing collapses to nothing.
- **Status bar (36 px):** on every screen (see Status bar below).
- **Log drawer (220 px):** slides up over the bottom of the screen, with Copy, Clear and Close.
- **No sideways scrolling, anywhere.** Tables use fixed column widths; the first text column takes the spare width and cuts long text with "…".
- **Minimum window:** 1100 × 680. Every screen is checked at 1100, 1440 and 1920 wide.

## Status bar

What it must show is in STANDARDS.md ("Progress you can trust"). How it looks:

- **Left:** the job name in `text` (600), then what it's working on in `sec`, cut with "…".
- **Middle:** the progress track (`raised2`) with the gradient fill, then the % in tabular numbers.
- **Then the times:** "1:12 elapsed · about 0:52 left" in `sec`.
- **When it stalls,** this text turns `warn`.
- **Right:**
  - the hardware chip, when a GPU job runs: a 22 px round chip with a tiny load bar, then "RTX 3060 Laptop GPU · 87% · 3.1 / 6.0 GB". On the CPU it shows "On the CPU (slow)" in `warn`.
  - the job's buttons (Review, Stop).
  - Log.
- **Unknown size:** the fill becomes a sliding bar.
- **When idle:** "Ready" and "Nothing running", or the last result ("Finished: 6 made · took 2:04").

## Components

### Buttons and controls

- **Buttons:**
  - **Primary:** gradient, `on-acc` text, weight 600. One per toolbar.
  - **Default:** `raised` with a `line` border.
  - **Ghost:** no fill, `sec` text.
  - **Danger-ghost:** `danger` text with a soft danger border, for things like Reset.
  - **Danger:** solid, used only inside a confirmation dialog.
  - With the Glow button style turned on in Appearance (off by default), the primary and active buttons get a soft glow along their bottom edge in the accent. Nothing else changes.
- **Drop-downs:** the native `<select>` (or the platform's own combo box) with a 14 px chevron.
- **Checkboxes, radio buttons and sliders:** native, coloured with the accent (`accent-color`).
- **Segmented control:** a `field`-coloured track with 2 px padding. The chosen segment is `raised2`. Counts sit in `faint` after the label ("Not done 8").
- **Pills:** 24 px, round, for filters in side panels and for the title bar's status.
- **Tags:** 20 px round labels for status (`ok`, `warn`, an accent tint) and for categories (category colour).

### Views of a collection: List, Grid, Gallery

A segmented control in the work area's summary line switches between them, with a Sort drop-down, a direction button and a size slider beside it.

- **List:** a table.
  - A sticky header in `panel` at 12 px / 600 / `sec`, with a checkbox column first.
  - Every column header sorts; click again to reverse. A small accent triangle marks the sorted column.
  - Thumbnails are 18–160 px, set with the slider or Ctrl + mouse wheel; rows grow with them.
  - An option shows a larger preview when hovering a thumbnail or file name.
- **Grid:** cards.
  - A thumbnail on `stage`, contained and never cropped, then name, sizes, settings and status.
  - 110–480 px wide, with the same slider and Ctrl + wheel. The tick box sits on the thumbnail's corner.
- **Gallery:** one image, **with nothing drawn over it**.
  - A 300 px side panel on the right holds everything else: name and position ("5 of 17"), the tick, file details, settings, actions, zoom, previous / next, then the keys.
  - Zoom keeps the centre of the view still, not the mouse position.
  - H hides the panels (side panel included), leaving just the image; F is full screen.
  - Double-click in List or Grid opens the Gallery.

### Selecting, ticking and own settings

- **Selecting and ticking:**
  - A click selects an item (accent outline; its details and settings show).
  - Ctrl+click or its tick box ticks it for the action. Shift with either ticks the range from the last ticked item.
  - An option ("When you click an item") switches to click-to-tick. Ctrl+A ticks everything shown.
  - Ticked rows get a faint accent tint; the row being worked on gets the selection tint.
- **Settings per item** (when relevant): a selection bar above the list (accent-tinted, one line) edits the settings of the ticked items, or the selected one when nothing is ticked.
  - A setting that differs between them shows "Mixed".
  - Items with their own settings show them in the accent in the Settings column.
  - **Use defaults** clears them. The toolbar's settings are the defaults for everything else.

### Cards, actions and messages

- **Cards** (versions, themes, results): flat. `raised`, with a 1 px `line` border that becomes the accent when chosen. Small actions appear on hover.
- **Destructive actions:** the button is `danger` or danger-ghost. It always opens a confirmation dialog first (what happens is in STANDARDS.md, "Files on disk").
- **Diagnosis results:** a list of findings, each with:
  - an icon in `ok` / `warn` / `danger` / accent (info);
  - a bold one-line title;
  - the evidence in `sec`;
  - a **Fix:** line.

  One button applies the fix when the app can do it (Repair …). A report can be copied or opened.
- **Banners:** one line with an icon, a bold lead, a sentence and one button. Tinted from the accent (6% fill, 26% border), never brown or yellow. Use them for "needs setting up first" states.
- **Empty states:** a 28 px faint icon, one sentence on what goes here, and the button that fills it.
- **Dialogs:** in-app only (no Windows pop-ups). A title, a sentence, an optional input, and actions on the right. Enter confirms; Esc cancels. File and folder pickers stay native.
- **Toasts:** bottom right, 4–7 s, with an icon in `ok` / `danger` / accent. Used for "done" and short errors. Long errors go to the log.
- **Pop-ups** (view options, menus): `panel` with a `line2` border and a soft shadow; closed by clicking outside or Esc.

### Keyboard shortcuts popup

Every app shows its keys in a popup, not on a screen of their own, so they can be read without leaving the work.

- **Opening:** K on any screen, or Keys in the rail. It opens over whatever screen is showing.
- **Closing:** K again, Esc, or a click anywhere outside the popup. Closing leaves the screen exactly as it was.
- **Look:** a `panel` card with the dialog's corners and shadow over a dim scrim, titled "Keyboard shortcuts", with "K or Esc closes" in the caption style beside the title. Keys are shown as keycaps (mono font, `raised` fill, `line2` border, 4 px corners) with what they do beside them, grouped under small headings (Anywhere, then each kind of view, then Dialogs, then keys for this screen if it has its own).
- **Always fits the window:** it never runs past the window's edges. When the keys don't fit in one column, they flow into more columns (each about 340 px wide) before anything scrolls; a group's heading stays with its first key. Only when the window is too narrow for enough columns does the popup scroll, and then only up and down.
- **Resizing** the window while it's open reflows the columns.
- While it's open, other single-letter keys do nothing.

### Icons, focus and motion

- **Icons:** one outline set on a 24-unit grid, 1.6 stroke, round ends; 16 px in controls and 19 px in the rail. No emoji, and no mixed icon sets.
- **Focus:** a 2 px accent ring on every interactive element.
- **Motion:** 150–250 ms. Only the drawer, pop-ups, toasts and the sliding progress bars move; nothing decorative. Respect the system's reduced-motion setting.

## Appearance (every app has this screen)

The **Look** item at the bottom of the rail opens it.

### The screen

- **Themes panel (left):**
  - It lists the built-in Default and every saved theme. Each shows a swatch strip (ground, panel, raised, gradient), its name and its font.
  - Clicking a theme uses it.
  - Each saved theme has Rename, Duplicate, Export and Delete, plus Update when the current look has been edited away from it.
  - At the bottom: Save as theme…, Import… and Export….
- **Preview:** sample buttons, a select, a checkbox, a progress bar, statuses and tags, so changes can be judged without leaving the screen.

### Background

- **Presets:** Obsidian, Carbon, Graphite, Midnight, Ink blue, Slate, Aubergine, Wine, Forest, Deep teal, Mocha, **Indigo**, and the light themes Daylight and Linen.
- **Indigo** (from Nirvash):
  - `ground #0e0f17`, `rail #0a0b12`, `panel #161826`, `raised #1d2032`, `raised2 #252942`
  - `field #0b0c13`, `line #2b3050`, `line2 #3a4170`, `stage #07080d`
  - `text #e8eaf6`, `sec #8d93b5`, `faint #7c82a8`
  - States: `ok #5be38a`, `warn #ffbf5a`, `danger #ff5f73`
  - Nirvash's own faint `#5d6388` was raised to `#7c82a8` to meet 4.5:1. It pairs with the Teal → Violet accent.
- **Every colour can be changed:** a colour picker and a hex field for each of the 12 tokens and the 3 state colours.

### Accent

- **Presets:** 13 gradients and 7 solid colours.
  - Gradients: Lime → Teal, Violet → Blue, Violet → Pink, Teal → Violet, Blue → Cyan, Aqua → Lime, Mint → Sky, Amber → Pink, Coral → Orange, Sunset, Rose → Peach, Gold → Lime, Aurora.
  - Solids: Lime, Teal, Blue, Violet, Green, Orange, Pink.
- **The gradient editor:**
  - 1 to 4 colours (add or remove);
  - a direction slider;
  - text on the accent (Auto, Dark or Light), with a live contrast readout that warns below 4.5:1.

### Font

- **Bundled fonts,** each shown in its own face.
- **Fonts on this computer** (Segoe UI, Segoe UI Variable, Satoshi, Bahnschrift, Aptos, Calibri), marked installed or not installed.
- **Fonts the owner adds:** Add font… picks the font files (all weights at once), guesses the name and weights from the file names, asks for the name, and copies the files into the app's data folder.
- **Text size:** 12, 13, 14 or 15 px.

### Shape, spacing and buttons

- **Corners:** Square, Sharp, Standard, Soft or Round, plus sliders for control and panel radius.
- **Density:** Compact, Comfortable or Roomy, plus sliders for control and row height.
- **Button style:** Flat (default) or Glow (a soft accent glow on the primary and active buttons).

### Outline and highlight

- **Outline:** the line around whatever is selected or has the keyboard's focus (rows, cards, tiles, buttons, fields). Its colour is the accent unless the person picks another, and its width is 1–4 px (default 2). A selected row's outline runs unbroken around the whole row, including a tree's indent, and sits inside the row so the view's edge never cuts it.
- **Highlight:** the tint behind selected, ticked and chosen things (12% for selected, 17% for ticked). Its colour is the accent unless the person picks another.

### Behaviour

- **Reset to default** brings back Obsidian, Lime → Teal, Inter, Standard, Compact, Flat, and the accent for the outline (2 px) and highlight. Saved themes stay.
- **Live changes:** everything applies as it changes. Pickers and sliders update in place without redrawing the form.
- **Storage:**
  - The current look, the active theme and the saved themes are kept in `appearance.json` in `%LOCALAPPDATA%\<App>`, so updates keep them.
  - Added fonts are kept in `fonts\<id>\`, with a `fonts\index.json` listing each family, file, weight and style.

### Theme file (`*.theme.json`)

The same format in every app, so a theme exported from one can be imported into another.

```json
{
  "version": 1,
  "name": "My theme",
  "background": {
    "ground": "#0a0a0b", "rail": "#060607", "panel": "#111113", "raised": "#19191c", "raised2": "#232327",
    "field": "#070708", "line": "#212125", "line2": "#2e2e33", "text": "#ececee", "sec": "#a0a0a7",
    "faint": "#7d7d84", "stage": "#040405"
  },
  "states": { "ok": "#52d39a", "warn": "#f2b64c", "danger": "#f0616d" },
  "accent": { "stops": ["#b6f05a", "#2fd6b4"], "angle": 90, "onAccent": "auto" },
  "font": { "family": "Inter", "size": 13 },
  "corners": { "control": 6, "panel": 10 },
  "density": { "control": 28, "row": 24 },
  "buttons": { "style": "flat" },
  "outline": { "colour": "", "width": 2 },
  "highlight": { "colour": "" }
}
```

Reading a theme:

- Missing or invalid values fall back to the default.
- Colours are `#rgb` or `#rrggbb`.
- Accent: 1 to 4 stops, angle 0–360. `onAccent` is `auto`, `dark` or `light`.
- Limits: font size 11–16, control radius 0–16, panel radius 0–24, control height 24–44, row height 20–40.
- `buttons.style` is `flat` or `glow`. An older theme without it is `flat`.
- `outline.colour` and `highlight.colour` are a colour, or empty for the accent. `outline.width` is 1–4. An older theme without them uses the accent and 2 px.
- A font named in a theme that isn't available falls back to Inter.

**Working code:** `lib/theme.js` and `renderer/fonts` in the `Sezekai/waifu2x-batch` repo implement this theme engine: presets, contrast checks, theme files and fonts. Copy them for an Electron app. Add the Indigo preset and the button style, which that app doesn't have.

### Carrying it to other toolkits

- **Electron:** reuse `lib/theme.js` and the CSS variable names as they are.
- **PySide6:**
  - Build the QSS from the same tokens, using `qlineargradient` for the accent gradient.
  - Add custom fonts with `QFontDatabase.addApplicationFont` from the data folder.
- **WPF:**
  - Put the tokens in a `ResourceDictionary` as `SolidColorBrush`es plus one `LinearGradientBrush`, and swap the dictionary to change themes.
  - Load custom fonts with a `FontFamily` pointing at the data-folder files.

## Not in this world

- Glass, blur or glows. **One exception:** the Glow button style in Appearance, off by default.
- Drop shadows on panels.
- Coloured side borders.
- Uppercase kicker labels above headings.
- Decorative monospace.
- Gradient text.
- Colour as decoration. **One exception:** the category colours, used only for groups the owner creates.
- Windows pop-up dialogs.
- A native menu bar, or a title bar in the system colour.
- Sideways scrolling.
- Illustrations in empty states.
- More than one primary button in a toolbar.

An app may add anything from this list for itself, only when the owner asks, and records it in its own copy of this file.
