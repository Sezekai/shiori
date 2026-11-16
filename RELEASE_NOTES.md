# Shiori 1.1.0

**Faster and steadier**
- Drawing the grid no longer touches the hard drive: Shiori keeps the list of covers in memory.
- The library list is worked out once and reused until something changes, so scrolling, clicking and switching sections no longer stall.
- CBR files open without freezing the window, and making a comic's cover pulls out just that page instead of unpacking the whole comic.
- Damaged files (some old CBRs have broken headers) show "Can't be read" and are no longer retried on every redraw and every scan.
- Covers are always decoded at the same size, so dragging the size slider no longer decodes every cover again (the likely cause of the crash while resizing).
- Plain .zip/.rar bundles with no pages (collections of other archives) are left out of the grid.

**Library**
- Sections are now Comics, Art Books, Manga, and Shiori opens on Comics.
- The selected section is highlighted in the sidebar again.
- Clicking a cover shows its details in a panel on the right; clicking it again opens it. The panel's expand button opens the full page.
- Covers can fill their tiles or fit inside them, with adjustable rounded corners (toolbar).
- Right-click a cover to adjust its placement and zoom, or to choose the cover page from thumbnails of every page.
- Titles use two lines when needed, and text gets smaller with smaller covers.

**Everywhere**
- The mouse's back button goes back: it closes the details panel or full page, goes up a folder, or returns to the previous screen. In the reader it closes the reader.
- Text boxes are taller with their contents centred, and the window buttons are drawn the same size.

**Reader**
- The controls hide when the mouse is still, and come back when you move it or point at them.
- Space shows or hides the controls.
