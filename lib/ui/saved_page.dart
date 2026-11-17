import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'app.dart';
import 'widgets.dart';

/// Everything saved from the reader, as a masonry grid of the saved images or
/// a list. Shiori remembers saves even after the files are moved.
class SavedPagesPage extends StatefulWidget {
  const SavedPagesPage({super.key});
  @override
  State<SavedPagesPage> createState() => _SavedPagesPageState();
}

class _SavedPagesPageState extends State<SavedPagesPage> {
  Section section = Nav.I.section;
  int cursor = -1;
  int _cols = 1;
  double _rowExtent = 40;
  final ScrollController _scroll = ScrollController();
  final FocusNode _keys = FocusNode(debugLabel: 'saved');
  List<SavedPage> list = [];

  bool get grid => Settings.I.width('saved.grid', 1) > 0;
  double get tile => Settings.I.width('saved.tile', 200).clamp(100, 480);

  static const _cols_ = ColumnSet('saved', [
    Col('date', 'Saved', 110),
    Col('title', 'Title', 360, min: 120),
    Col('pages', 'Pages', 70),
    Col('file', 'File', 320, min: 80),
  ]);

  @override
  void dispose() {
    _scroll.dispose();
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    list = Db.I.savedPages(section);
    final folder = Settings.I.of(section).saveFolder;
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: Settings.I,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Saved pages', style: ts(size: 15, w: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      'Pages you saved. Shiori remembers them even after you move the files, and asks before saving the same page from the same chapter again.',
                      style: ts(c: tk.sec),
                      overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            PanelBox(
              child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Seg<Section>(
                  value: section,
                  items: [for (final s in Section.values) (s, s.label)],
                  onChanged: (v) => setState(() {
                    section = v;
                    cursor = -1;
                  }),
                ),
                Seg<bool>(
                  value: grid,
                  items: const [(true, 'Grid'), (false, 'List')],
                  onChanged: (v) {
                    Settings.I.setWidth('saved.grid', v ? 1 : 0);
                    Settings.I.save();
                  },
                ),
                if (grid)
                  SizedBox(
                    width: 160,
                    child: Slider(
                      value: tile,
                      min: 100,
                      max: 480,
                      onChanged: (v) => Settings.I.setWidth('saved.tile', v),
                      onChangeEnd: (_) => Settings.I.save(),
                    ),
                  ),
                Text('${list.length} saved · saves to', style: ts(c: tk.sec)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(folder, style: ts(mono: true, size: 12), overflow: TextOverflow.ellipsis),
                ),
                Btn('Open folder', icon: Icons.folder_open_outlined, dense: true, onTap: () {
                  if (Platform.isWindows && Directory(folder).existsSync()) Process.run('explorer.exe', [folder]);
                }),
                Btn.ghost('Change in Settings', dense: true, onTap: () => Nav.I.go(PageId.settings)),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(icon: Icons.bookmark_border, text: 'No saved pages yet. Press P in the reader to save a page.')
                  : Listener(
                      onPointerSignal: (e) {
                        if (grid && e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
                          Settings.I.setWidth('saved.tile', (tile - e.scrollDelta.dy / 4).clamp(100, 480));
                          Settings.I.save();
                        }
                      },
                      child: grid ? _grid() : _list(),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || typingInField || list.isEmpty) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final across = grid ? _cols : 1;
    int? move;
    if (k == LogicalKeyboardKey.arrowDown) move = across;
    if (k == LogicalKeyboardKey.arrowUp) move = -across;
    if (grid && k == LogicalKeyboardKey.arrowRight) move = 1;
    if (grid && k == LogicalKeyboardKey.arrowLeft) move = -1;
    if (k == LogicalKeyboardKey.pageDown) move = across * 5;
    if (k == LogicalKeyboardKey.pageUp) move = -across * 5;
    if (k == LogicalKeyboardKey.home) move = -list.length;
    if (k == LogicalKeyboardKey.end) move = list.length;
    if (move != null) {
      final i = cursor < 0 ? 0 : (cursor + move).clamp(0, list.length - 1);
      setState(() => cursor = i);
      if (!grid) _reveal(i);
      return KeyEventResult.handled;
    }
    if (cursor < 0) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _openChapter(list[cursor]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space) {
      _preview(list[cursor]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      _forget(list[cursor]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _reveal(int i) {
    if (!_scroll.hasClients) return;
    final top = (i ~/ max(1, _cols)) * _rowExtent, bottom = top + _rowExtent;
    final pos = _scroll.position;
    if (top < pos.pixels) {
      _scroll.jumpTo(top.clamp(0, pos.maxScrollExtent));
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo((bottom - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  }

  void _tap(int i) {
    _keys.requestFocus();
    setState(() => cursor = i);
    _preview(list[i]);
  }

  /// Opens the chapter at the saved page.
  void _openChapter(SavedPage sp) {
    final t = Library.I.byId(sp.titleId);
    if (t == null) {
      toast('That title isn\'t in the library any more', ToastKind.info);
      return;
    }
    final first = int.tryParse(sp.pages.split('-').first) ?? 1;
    openReader(context, t, context_: [t], startPage: first - 1);
  }

  Future<void> _preview(SavedPage sp) async {
    final f = File(sp.path);
    if (!f.existsSync()) {
      toast('The saved file was moved or deleted. The save is still remembered.', ToastKind.info);
      return;
    }
    final t = Library.I.byId(sp.titleId);
    await showDialog<void>(
      context: context,
      builder: (c) => AppDialog(
        title: p.basename(sp.path),
        width: 900,
        body: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: Image.file(f, fit: BoxFit.contain),
        ),
        actions: [
          Btn.primary('Close', onTap: () => Navigator.pop(c)),
          if (t != null)
            Btn('Open the chapter here', onTap: () {
              Navigator.pop(c);
              _openChapter(sp);
            }),
          Btn('Show in folder', onTap: () {
            if (Platform.isWindows) Process.run('explorer.exe', ['/select,', sp.path]);
          }),
        ],
      ),
    );
  }

  Future<void> _forget(SavedPage sp) async {
    if (await confirm(context, 'Forget this save?',
        'Shiori will stop warning you about saving this page again. The saved image itself isn\'t touched.',
        confirmLabel: 'Forget save')) {
      Db.I.forgetSaved(sp.id);
      setState(() => cursor = min(cursor, list.length - 2));
    }
  }

  Future<void> _menu(SavedPage sp, Offset at) async {
    final exists = File(sp.path).existsSync();
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        if (exists) PopupMenuItem(value: 'view', child: Text('View', style: ts())),
        PopupMenuItem(value: 'open', child: Text('Open the chapter at this page', style: ts())),
        if (exists) PopupMenuItem(value: 'folder', child: Text('Show in folder', style: ts())),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'forget', child: Text('Forget this save', style: ts())),
      ],
    );
    switch (v) {
      case 'view':
        _preview(sp);
      case 'open':
        _openChapter(sp);
      case 'folder':
        if (Platform.isWindows) Process.run('explorer.exe', ['/select,', sp.path]);
      case 'forget':
        _forget(sp);
    }
  }

  Widget _grid() {
    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final cols = max(1, ((c.maxWidth + gap) / (tile + gap)).ceil());
      final cw = (c.maxWidth - gap * (cols - 1)) / cols;
      _cols = cols;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      return MasonryGridView.count(
        controller: _scroll,
        crossAxisCount: cols,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
        itemCount: list.length,
        itemBuilder: (_, i) {
          final sp = list[i];
          final f = File(sp.path);
          final exists = f.existsSync();
          final t = Library.I.byId(sp.titleId);
          return Hoverable(
            builder: (h) => GestureDetector(
              onTap: () => _tap(i),
              onSecondaryTapDown: (d) => _menu(sp, d.globalPosition),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(lk.rPanel),
                    color: h ? tk.raised : tk.field,
                    border: Border.all(color: cursor == i ? lk.acc : tk.line, width: cursor == i ? 2 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    exists
                        ? Image.file(
                            f,
                            width: cw,
                            fit: BoxFit.fitWidth,
                            cacheWidth: (cw * dpr).round().clamp(64, 1400),
                            errorBuilder: (_, _, _) => _missing(cw, 'Can\'t show this image'),
                          )
                        : _missing(cw, 'Moved or deleted'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t?.displayTitle ?? 'Removed title',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(size: 12, w: FontWeight.w600)),
                        Text('p${sp.pages} · ${dateText(sp.at)}', style: ts(size: 11, c: tk.faint, tab: true)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _missing(double w, String text) => Container(
        width: w,
        height: w * 0.6,
        color: tk.panel,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.image_not_supported_outlined, color: tk.faint),
          const SizedBox(height: 4),
          Text(text, style: ts(size: 12, c: tk.faint)),
        ]),
      );

  Widget _list() {
    final extent = lk.hRow + 8;
    _rowExtent = extent;
    _cols = 1;
    return Container(
      decoration: BoxDecoration(color: tk.field, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 16 + 140 + _cols_.cols.fold<double>(0, (a, c) => a + _cols_.w(c)),
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _cols_.header()),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemCount: list.length,
                itemExtent: extent,
                itemBuilder: (_, i) {
                  final sp = list[i];
                  final t = Library.I.byId(sp.titleId);
                  final exists = File(sp.path).existsSync();
                  return Hoverable(
                    builder: (h) => GestureDetector(
                      onTap: () => _tap(i),
                      onSecondaryTapDown: (d) => _menu(sp, d.globalPosition),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: rowColor(i, hover: h, cursor: cursor == i),
                          border: cursor == i ? Border(left: BorderSide(color: lk.acc, width: 3)) : null,
                        ),
                        child: Row(children: [
                          _cols_.row([
                            Text(dateText(sp.at), style: ts(c: tk.sec, tab: true)),
                            Text(t?.displayTitle ?? 'Removed title', style: ts(), overflow: TextOverflow.ellipsis),
                            Text('p${sp.pages}', style: ts(c: tk.sec, tab: true)),
                            Text(exists ? p.basename(sp.path) : '${p.basename(sp.path)} (moved)',
                                style: ts(c: exists ? tk.sec : tk.faint, size: 12, mono: true), overflow: TextOverflow.ellipsis),
                          ]),
                          Btn.ghost('Forget', dense: true, onTap: () => _forget(sp)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
