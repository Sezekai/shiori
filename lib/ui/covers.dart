import 'dart:io';
import 'package:flutter/gestures.dart';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Title;

import '../core/archives.dart';
import '../core/db.dart';
import '../core/library.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import 'widgets.dart';

/// A cover thumbnail, made on first use and cached on disk.
///
/// Decoded at its stored size (360 px wide) whatever the tile size, so
/// resizing the grid never decodes covers again.
class CoverThumb extends StatefulWidget {
  const CoverThumb({super.key, required this.title, this.fill = false, this.natural = false, this.adjust = true});
  final Title title;
  final bool fill; // fill the box, cropping, using the title's placement and zoom
  final bool natural; // keep the image's own shape (staggered grid)
  final bool adjust;
  @override
  State<CoverThumb> createState() => _CoverThumbState();
}

class _CoverThumbState extends State<CoverThumb> {
  File? file;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverThumb old) {
    super.didUpdateWidget(old);
    if (old.title.id != widget.title.id || old.title.coverPage != widget.title.coverPage ||
        old.title.fingerprint != widget.title.fingerprint || file == null) {
      file = null;
      failed = false;
      _load();
    }
  }

  void _load() {
    final c = Thumbs.I.cached(widget.title);
    if (c != null) {
      file = c;
      return;
    }
    if (Thumbs.I.failed(widget.title)) {
      failed = true;
      return;
    }
    final id = widget.title.id;
    Thumbs.I.get(widget.title).then((f) {
      if (!mounted || widget.title.id != id) return;
      setState(() {
        file = f;
        failed = f == null && Thumbs.I.failed(widget.title);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    if (file == null) return _placeholder();
    final align = widget.adjust ? Alignment(t.coverX, t.coverY) : Alignment.center;
    final img = Image.file(
      file!,
      fit: widget.natural ? BoxFit.fitWidth : (widget.fill ? BoxFit.cover : BoxFit.contain),
      alignment: widget.fill ? align : Alignment.center,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _placeholder(),
    );
    if (widget.natural) return img;
    if (widget.fill) {
      final zoom = widget.adjust ? t.coverZoom : 1.0;
      return ClipRect(
        child: Container(
          color: tk.stage,
          child: zoom == 1
              ? SizedBox.expand(child: img)
              : Transform.scale(scale: zoom, alignment: align, child: SizedBox.expand(child: img)),
        ),
      );
    }
    return Container(color: tk.stage, alignment: Alignment.center, child: img);
  }

  Widget _placeholder() => Container(
        color: tk.stage,
        height: widget.natural ? 200 : null,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(failed ? Icons.broken_image_outlined : Icons.image_outlined, size: 20, color: tk.faint),
          if (failed && widget.title.unreadable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Can\'t be read', style: ts(size: 11, c: tk.faint)),
            ),
        ]),
      );
}

class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.entry,
    required this.style,
    required this.width,
    required this.radius,
    required this.fill,
    required this.selected,
    required this.ticked,
    required this.anyTicked,
    required this.onTap,
    required this.onTick,
    this.onMenu,
    this.onMiddle,
    this.cursor = false,
  });
  final VoidCallback? onMiddle;
  final bool cursor;
  final Entry entry;
  final String style;
  final double width;
  final double radius;
  final bool fill;
  final bool selected;
  final bool ticked;
  final bool anyTicked;
  final VoidCallback onTap;
  final VoidCallback onTick;
  final ValueChanged<Offset>? onMenu;

  /// Text gets smaller as covers do.
  static double fontFor(double w) => (w / 180 * lk.fontSize).clamp(10.0, lk.fontSize);
  static double textHeight(double w) {
    final f = fontFor(w);
    return 6 + f * 1.25 * 2 + (f - 1.5) * 1.25 + 4;
  }

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final t = e.cover;
    final folder = e is FolderEntry;
    final progress = Library.I.entryProgress(e);
    final fav = e.titles.any((x) => x.favourite);
    final r = e is TitleEntry ? t.rating : 0.0;
    final reads = e is TitleEntry ? t.readCount : 0;
    final fs = fontFor(width);
    final small = width < 130;
    final cover = Stack(children: [
      Positioned.fill(child: CoverThumb(title: t, fill: fill)),
      if (folder) Positioned(left: 5, top: 5, child: _badge(Icons.folder_outlined, '${e.titles.length}', small)),
      if (e is GroupEntry) Positioned(left: 5, top: 5, child: _badge(null, '${e.readChapters}/${e.titles.length}', small)),
      if (fav) Positioned(right: 5, top: 5, child: _badge(Icons.favorite, null, small, color: const Color(0xFFFF6FB1))),
      if (r > 0 && style != 'cover' && !small)
        Positioned(left: 5, bottom: 7, child: _badge(Icons.star_rounded, r.toString().replaceAll('.0', ''), small)),
      if (reads > 1 && !small) Positioned(right: 5, bottom: 7, child: _badge(null, '×$reads', small)),
      if (t.missing)
        Positioned.fill(
            child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text('Not found', style: ts(c: Colors.white, w: FontWeight.w600, size: fs)))),
      if (style == 'compact')
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 18, 6, 7),
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xDD000000)])),
            child: Text(e.name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(c: Colors.white, size: fs - 0.5, w: FontWeight.w600)),
          ),
        ),
      if (Settings.I.progressLine && progress > 0)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 3,
            color: Colors.black45,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                  decoration: BoxDecoration(gradient: progress >= 1 ? null : lk.grad, color: progress >= 1 ? tk.ok : null)),
            ),
          ),
        ),
      if (!folder && (anyTicked || ticked))
        Positioned(
          right: 3,
          bottom: 6,
          child: SizedBox(width: 24, height: 24, child: Checkbox(value: ticked, onChanged: (_) => onTick())),
        ),
    ]);
    final coverBox = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: style == 'staggered'
          ? Stack(children: [CoverThumb(title: t, natural: true), Positioned.fill(child: cover)])
          : cover,
    );
    final highlight = ticked || selected;
    return Hoverable(
      builder: (h) => Listener(
        onPointerDown: onMiddle == null
            ? null
            : (ev) {
                if (ev.buttons & kMiddleMouseButton != 0) onMiddle!();
              },
        child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius + 2),
              color: highlight ? lk.tint(tk.ground, 0.17) : (h ? tk.raised : null),
              border: Border.all(
                  color: cursor ? lk.acc : (highlight ? lk.outline : Colors.transparent), width: cursor ? 2 : 1),
            ),
            padding: const EdgeInsets.all(1),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (style == 'staggered') coverBox else Expanded(child: coverBox),
              if (style == 'comfortable')
                SizedBox(
                  height: textHeight(width),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(3, 5, 3, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ts(size: fs, w: FontWeight.w600, c: t.missing ? tk.faint : tk.text)),
                      Text(
                          folder
                              ? '${e.titles.length} files'
                              : (t.displayArtist ?? (t.section == Section.comics && t.year != null ? '${t.year}' : '')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(size: fs - 1.5, c: tk.faint)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
      ),
    );
  }

  Widget _badge(IconData? icon, String? text, bool small, {Color? color}) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 3 : 5, vertical: small ? 1 : 2),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: small ? 10 : 12, color: color ?? Colors.white),
          if (icon != null && text != null) const SizedBox(width: 3),
          if (text != null) Text(text, style: ts(size: small ? 9.5 : 11, c: Colors.white, w: FontWeight.w600, tab: true)),
        ]),
      );
}

/// Drag the cover to place it in the tile, and zoom in. Used when covers fill their tiles.
Future<void> adjustCover(BuildContext context, Title t, double radius) async {
  var x = t.coverX, y = t.coverY, zoom = t.coverZoom;
  const w = 240.0, h = w * 1.42;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final preview = Title(
          id: t.id, uid: t.uid, section: t.section, path: t.path, root: t.root, relDir: t.relDir,
          fileName: t.fileName, size: t.size, mtime: t.mtime, fingerprint: t.fingerprint, kind: t.kind,
          pages: t.pages, title: t.title, seriesKey: t.seriesKey, seriesBase: t.seriesBase, addedAt: t.addedAt,
          coverPage: t.coverPage, coverX: x, coverY: y, coverZoom: zoom,
        );
        return AppDialog(
          title: 'Adjust the cover',
          width: 420,
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Drag to move it. Use the slider or the mouse wheel to zoom.', style: ts(c: tk.sec)),
            const SizedBox(height: 12),
            Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) set(() => zoom = (zoom * (e.scrollDelta.dy < 0 ? 1.08 : 1 / 1.08)).clamp(1.0, 4.0));
              },
              child: GestureDetector(
                onPanUpdate: (d) => set(() {
                  // Moving right shows more of the left side.
                  x = (x - d.delta.dx / (w / 2) / zoom).clamp(-1.0, 1.0);
                  y = (y - d.delta.dy / (h / 2) / zoom).clamp(-1.0, 1.0);
                }),
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: SizedBox(width: w, height: h, child: CoverThumb(key: ValueKey('$x$y$zoom'), title: preview, fill: true)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Text('Zoom', style: ts(c: tk.sec)),
              Expanded(child: Slider(value: zoom, min: 1, max: 4, onChanged: (v) => set(() => zoom = v))),
              Text('${zoom.toStringAsFixed(1)}×', style: ts(tab: true)),
            ]),
            if (!Settings.I.of(t.section).coverFill)
              Text('Covers are set to fit inside their tiles. Switch to Fill in the toolbar to see this placement.',
                  style: ts(c: tk.warn, size: 12)),
          ]),
          actions: [
            Btn.primary('Save', onTap: () => Navigator.pop(c, true)),
            Btn('Cancel', onTap: () => Navigator.pop(c, false)),
            Btn('Reset', onTap: () => set(() {
                  x = 0;
                  y = 0;
                  zoom = 1;
                })),
          ],
        );
      },
    ),
  );
  if (ok == true) {
    t.coverX = x;
    t.coverY = y;
    t.coverZoom = zoom;
    Library.I.saveEdits(t);
  }
}

/// Shows every page as a thumbnail; the one picked becomes the cover.
Future<void> chooseCoverPage(BuildContext context, Title t) async {
  Book book;
  try {
    book = await Book.open(t.path, cacheDir: AppPaths.I.pageCache, sevenZip: Library.I.sevenZip);
  } catch (e) {
    toast('This file couldn\'t be opened: $e', ToastKind.error);
    return;
  }
  if (!context.mounted) {
    book.close();
    return;
  }
  final cache = <int, Future<Uint8List>>{};
  final picked = await showDialog<int>(
    context: context,
    builder: (c) => AppDialog(
      title: 'Choose the cover page',
      width: 860,
      body: SizedBox(
        width: 820,
        height: 520,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 130 / 205),
          itemCount: book.length,
          itemBuilder: (_, i) => Hoverable(
            builder: (h) => GestureDetector(
              onTap: () => Navigator.pop(c, i),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: h ? tk.raised2 : null,
                    border: Border.all(color: i == t.coverPage ? lk.outline : tk.line, width: i == t.coverPage ? 2 : 1),
                  ),
                  child: Column(children: [
                    Expanded(
                      child: FutureBuilder<Uint8List>(
                        future: cache.putIfAbsent(i, () => book.page(i)),
                        builder: (_, snap) => snap.hasData
                            ? Image.memory(snap.data!, cacheWidth: 240, fit: BoxFit.contain, gaplessPlayback: true,
                                errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: tk.faint))
                            : Center(child: SizedBox(width: 60, child: Progress(value: null, height: 3))),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('${i + 1}${i == t.coverPage ? ' · cover' : ''}', style: ts(size: 11.5, c: tk.sec, tab: true)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [Btn('Cancel', onTap: () => Navigator.pop(c))],
    ),
  );
  book.close();
  if (picked != null && picked != t.coverPage) {
    t.coverPage = picked;
    Library.I.saveEdits(t);
    await Thumbs.I.get(t);
    Library.I.changed();
  }
}
