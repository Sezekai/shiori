import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'look.dart';
import 'app.dart';
import 'covers.dart';
import 'library_page.dart';
import 'widgets.dart';

/// The title page: big cover, details, rating, favourite, tags, history, and
/// for a series its chapter list with select-and-mark.
class TitlePage extends StatefulWidget {
  const TitlePage({super.key, required this.entry, required this.onBack, required this.onOpenArtist});
  final Entry entry;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenArtist;
  @override
  State<TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends State<TitlePage> {
  final Set<int> ticked = {};
  int? lastTick;
  late Title current = widget.entry is GroupEntry ? _continue(widget.entry.titles) : widget.entry.cover;

  List<Title> get chapters => widget.entry.titles;
  bool get isGroup => widget.entry is GroupEntry || widget.entry is FolderEntry;

  static Title _continue(List<Title> ts_) {
    final inProg = ts_.where((t) => t.inProgress).toList()..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    if (inProg.isNotEmpty) return inProg.first;
    return ts_.firstWhere((t) => !t.isRead, orElse: () => ts_.first);
  }

  bool selectMode = false;
  int cursor = -1;
  final FocusNode _keys = FocusNode(debugLabel: 'title');
  final ScrollController _scroll = ScrollController();
  double _rowExtent = 60;
  int _cols = 1;

  bool get gridView => Settings.I.width('title.grid', 0) > 0;
  double get leftW => Settings.I.width('title.left', 320).clamp(240, 720);
  double get tile => Settings.I.width('title.tile', 150).clamp(90, 360);

  @override
  void dispose() {
    _keys.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([Library.I, Settings.I]),
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Btn.ghost('Back', icon: Icons.arrow_back, onTap: widget.onBack),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.entry.name, style: ts(size: 15, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: leftW, child: _left()),
                DragHandle(
                  width: 14,
                  onDrag: (dx) => Settings.I.setWidth('title.left', (leftW + dx).clamp(240, 720)),
                  onEnd: Settings.I.save,
                ),
                Expanded(child: isGroup ? _groupBody() : SingleChildScrollView(child: _history(current))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Cover, read buttons, and all the details, in one scrolling column.
  Widget _left() {
    final cover = isGroup ? widget.entry.cover : current;
    return ListView(children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(lk.rPanel),
            child: AspectRatio(aspectRatio: 1 / 1.42, child: CoverThumb(title: cover)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Btn.primary(_readLabel(), icon: Icons.menu_book, onTap: () => _read(current)),
      if (current.lastPage > 0 || current.isRead) ...[
        const SizedBox(height: 6),
        Btn('Start from the beginning', onTap: () => _read(current, page: 0)),
      ],
      const SizedBox(height: 10),
      if (isGroup) ...[_groupSummary(), const SizedBox(height: 10)],
      _details(current),
    ]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || typingInField) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      if (ticked.isNotEmpty || selectMode) {
        setState(() {
          ticked.clear();
          selectMode = false;
        });
      } else {
        widget.onBack();
      }
      return KeyEventResult.handled;
    }
    if (!isGroup) {
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
        _read(current);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final list = chapters;
    final across = gridView ? _cols : 1;
    int? move;
    if (k == LogicalKeyboardKey.arrowDown) move = across;
    if (k == LogicalKeyboardKey.arrowUp) move = -across;
    if (gridView && k == LogicalKeyboardKey.arrowRight) move = 1;
    if (gridView && k == LogicalKeyboardKey.arrowLeft) move = -1;
    if (k == LogicalKeyboardKey.pageDown) move = across * 6;
    if (k == LogicalKeyboardKey.pageUp) move = -across * 6;
    if (k == LogicalKeyboardKey.home) move = -list.length;
    if (k == LogicalKeyboardKey.end) move = list.length;
    if (move != null) {
      final i = cursor < 0 ? 0 : (cursor + move).clamp(0, list.length - 1);
      setState(() => cursor = i);
      _reveal(i);
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && cursor >= 0) {
      _read(list[cursor]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space && cursor >= 0) {
      if (selectMode) {
        final t = list[cursor];
        setState(() => ticked.contains(t.id) ? ticked.remove(t.id) : ticked.add(t.id));
      } else {
        setState(() => current = list[cursor]);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyA && HardwareKeyboard.instance.isControlPressed) {
      setState(() => ticked.addAll(list.map((t) => t.id)));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _reveal(int i) {
    if (!_scroll.hasClients) return;
    final row = i ~/ max(1, gridView ? _cols : 1);
    final top = row * _rowExtent, bottom = top + _rowExtent;
    final pos = _scroll.position;
    if (top < pos.pixels) {
      _scroll.jumpTo(top.clamp(0, pos.maxScrollExtent));
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo((bottom - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  }

  /// Click: open. Ctrl+click ticks one, Shift+click ticks a range, and in
  /// select mode a click ticks.
  void _tapChapter(Title t, int i) {
    _keys.requestFocus();
    final list = chapters;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (shift && lastTick != null) {
      final a = min(lastTick!, i), b = max(lastTick!, i);
      setState(() => ticked.addAll(list.sublist(a, b + 1).map((x) => x.id)));
    } else if (ctrl || selectMode) {
      setState(() => ticked.contains(t.id) ? ticked.remove(t.id) : ticked.add(t.id));
    } else {
      setState(() => cursor = i);
      _read(t);
    }
    lastTick = i;
    if (shift || ctrl || selectMode) setState(() => cursor = i);
  }

  /// Middle click: show this chapter's details on the left.
  void _showChapter(Title t, int i) => setState(() {
        cursor = i;
        current = t;
      });

  String _readLabel() {
    final t = current;
    final ch = isGroup && t.displayChapter != null ? ' chapter ${_num(t.displayChapter!)}' : '';
    if (t.inProgress) return 'Continue$ch · page ${t.lastPage + 1} of ${t.pages}';
    if (t.isRead && !isGroup) return 'Read again';
    return 'Read$ch';
  }

  static String _num(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();

  void _read(Title t, {int? page}) {
    final queue = isGroup ? chapters.sublist(chapters.indexOf(t)) : [t];
    openReader(context, t, context_: queue, startPage: page);
  }

  Widget _details(Title t) {
    final tags = Library.I.tagsOf(t).map((id) => Library.I.tagById(t.section, id)).whereType<Tag>().toList();
    Widget row(String k, String? v, {bool mono = false, VoidCallback? onTap}) => v == null || v.isEmpty
        ? const SizedBox()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 104, child: Text(k, style: ts(c: tk.faint))),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  child: MouseRegion(
                    cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                    child: SelectableText(v, style: ts(mono: mono, size: mono ? 12 : null, c: onTap == null ? tk.text : lk.acc)),
                  ),
                ),
              ),
            ]),
          );
    return PanelBox(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.displayTitle, style: ts(size: 15, w: FontWeight.w700)),
        if (t.altTitle != null) Text(t.altTitle!, style: ts(c: tk.sec)),
        const SizedBox(height: 10),
        Stars(value: t.rating, size: 22, onChanged: (v) => Library.I.setRating(t, v)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          IconBtn(t.favourite ? Icons.favorite : Icons.favorite_border,
              tooltip: t.favourite ? 'Favourite' : 'Not a favourite',
              color: t.favourite ? const Color(0xFFFF6FB1) : null,
              onTap: () => Library.I.toggleFavourite([t])),
          TagMenu(section: t.section, titles: [t]),
          Btn(t.isRead ? 'Mark unread' : 'Mark read', dense: true, icon: t.isRead ? Icons.remove_done : Icons.done_all,
              onTap: () => Library.I.markRead([t], !t.isRead)),
          Btn('Edit details', dense: true, icon: Icons.edit_outlined, onTap: () => _edit(t)),
        ]),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in tags) TagChip(g.name, Color(g.color), onRemove: () => Library.I.removeTag(g, [t])),
          ]),
        ],
        const SizedBox(height: 12),
        row('Artist', t.displayArtist, onTap: t.displayArtist == null ? null : () => widget.onOpenArtist(t.displayArtist!)),
        row('Circle', t.circle),
        row('Series', t.displaySeries != t.displayTitle ? t.displaySeries : null),
        row('Chapter', t.displayChapter == null ? null : _num(t.displayChapter!)),
        row('Volume', t.volume),
        row('Year', t.year?.toString()),
        row('Parody', t.parody),
        row('Source', t.source),
        row('Event', t.event),
        row('Language', t.language),
        row('Other', t.extras),
        row('Pages', '${t.pages}'),
        row('Size', humanSize(t.size)),
        row('Added', dateText(t.addedAt)),
        row('Times read', t.readCount > 0 ? '${t.readCount}${t.manualRead ? ' (marked by hand)' : ''}' : 'Not read yet'),
        row('First finished', t.firstCompletedAt > 0 ? dateText(t.firstCompletedAt) : null),
        row('Last finished', t.lastCompletedAt > 0 ? dateText(t.lastCompletedAt) : null),
        row('Time reading', t.timeSpent > 0 ? humanHours(t.timeSpent) : null),
        row('Progress', t.pages > 0 ? 'Page ${t.lastPage + 1} of ${t.pages}' : null),
        row('File', t.path, mono: true),
        const SizedBox(height: 8),
        Wrap(children: [
          Btn.ghost('Show in folder', icon: Icons.folder_open_outlined, onTap: () {
            if (Platform.isWindows) Process.run('explorer.exe', ['/select,', t.path]);
          }),
          Btn.ghost('Copy path', icon: Icons.copy, onTap: () {
            Clipboard.setData(ClipboardData(text: t.path));
            toast('Path copied');
          }),
          Btn.ghost('Choose cover page', icon: Icons.image_outlined, onTap: () => chooseCoverPage(context, t)),
        ]),
      ]),
    );
  }

  Future<void> _edit(Title t) async {
    final title = TextEditingController(text: t.displayTitle);
    final artist = TextEditingController(text: t.displayArtist ?? '');
    final series = TextEditingController(text: t.displaySeries);
    final chapter = TextEditingController(text: t.displayChapter == null ? '' : _num(t.displayChapter!));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AppDialog(
        title: 'Edit details',
        width: 520,
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (label, ctl) in [('Title', title), ('Artist', artist), ('Series', series), ('Chapter', chapter)])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 88, child: Text(label, style: ts(c: tk.sec))),
                Expanded(child: Field(controller: ctl)),
              ]),
            ),
          Text('Your edits are kept, and a rescan never overwrites them. Same series and artist = one series card.',
              style: ts(c: tk.faint, size: 12)),
        ]),
        actions: [
          Btn.primary('Save details', onTap: () {
            String? v(TextEditingController x, String? orig) => x.text.trim().isEmpty || x.text.trim() == orig ? null : x.text.trim();
            t.userTitle = v(title, t.title);
            t.userArtist = v(artist, t.artist);
            t.userSeries = v(series, t.seriesBase);
            final ch = double.tryParse(chapter.text.trim());
            t.userChapter = ch == t.chapter ? null : ch;
            t.needsCheck = false;
            Navigator.pop(c, true);
          }),
          Btn('Cancel', onTap: () => Navigator.pop(c, false)),
          Btn('Undo my edits', onTap: () {
            t.userTitle = null;
            t.userArtist = null;
            t.userSeries = null;
            t.userChapter = null;
            Navigator.pop(c, true);
          }),
        ],
      ),
    );
    if (ok == true) Library.I.saveEdits(t);
  }

  Widget _history(Title t) {
    final sessions = Db.I.sessions(titleId: t.id);
    final comps = Db.I.completions(titleId: t.id);
    return PanelBox(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('History', style: ts(w: FontWeight.w700)),
        const SizedBox(height: 8),
        if (sessions.isEmpty && comps.isEmpty) Text('Not opened yet.', style: ts(c: tk.faint)),
        for (final c in comps.where((c) => c.$4 == 'yacreader' || c.$3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
                '${c.$4 == 'yacreader' ? 'Read · from YACReader' : 'Marked read by hand'} · ${c.$2 > 0 ? dateText(c.$2) : 'date unknown'}',
                style: ts(c: tk.sec)),
          ),
        for (final s in sessions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 170, child: Text('${dateText(s.startedAt)}, ${timeText(s.startedAt)}', style: ts(tab: true))),
              SizedBox(width: 90, child: Text(humanHours(s.activeSeconds), style: ts(c: tk.sec, tab: true))),
              SizedBox(width: 160, child: Text('p${s.fromPage + 1} → p${s.toPage + 1} · ${s.pagesSeen} pages', style: ts(c: tk.sec, tab: true))),
              if (s.completed) Text('Finished', style: ts(c: tk.ok, w: FontWeight.w600)),
              const Spacer(),
              Text(s.device, style: ts(c: tk.faint)),
            ]),
          ),
      ]),
    );
  }

  Widget _groupSummary() {
    final list = chapters;
    final reads = list.where((t) => t.isRead).length;
    final first = list.first;
    return PanelBox(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.entry.name, style: ts(size: 15, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
            '${first.displayArtist != null ? '${first.displayArtist} · ' : ''}${list.length} ${widget.entry is FolderEntry ? 'files' : 'chapters'} · $reads read · '
            '${humanSize(list.fold<int>(0, (a, t) => a + t.size))}',
            style: ts(c: tk.sec)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Btn('Favourite all', dense: true, icon: Icons.favorite_border, onTap: () => Library.I.toggleFavourite(list)),
          TagMenu(section: first.section, titles: list),
          if (first.displayArtist != null)
            Btn.ghost('More by ${first.displayArtist}', dense: true, onTap: () => widget.onOpenArtist(first.displayArtist!)),
        ]),
      ]),
    );
  }

  static const _chCols = ColumnSet('chapters', [
    Col('no', '#', 70),
    Col('title', 'Title', 380, min: 120),
    Col('pages', 'Pages', 64, right: true),
    Col('rating', 'Rating', 90),
    Col('last', 'Last read', 110),
    Col('progress', 'Progress', 90),
    Col('read', 'Read', 44),
  ]);

  Widget _groupBody() {
    final list = chapters;
    final tickedTitles = list.where((t) => ticked.contains(t.id)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Seg<bool>(
          value: gridView,
          items: const [(false, 'List'), (true, 'Grid')],
          onChanged: (v) {
            Settings.I.setWidth('title.grid', v ? 1 : 0);
            Settings.I.save();
          },
        ),
        const SizedBox(width: 8),
        Btn(selectMode ? 'Done selecting' : 'Select',
            icon: selectMode ? Icons.check_box_outlined : Icons.check_box_outline_blank,
            dense: true,
            tooltip: 'Tick chapters. Ctrl+click ticks one, Shift+click ticks a range.',
            onTap: () => setState(() {
                  selectMode = !selectMode;
                  if (!selectMode) ticked.clear();
                })),
        const Spacer(),
        Text('Size', style: ts(c: tk.faint)),
        SizedBox(
          width: 140,
          child: Slider(
            value: tile,
            min: 90,
            max: 360,
            onChanged: (v) => Settings.I.setWidth('title.tile', v),
            onChangeEnd: (_) => Settings.I.save(),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      if (tickedTitles.isNotEmpty)
        Container(
          height: lk.hControl + 10,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: lk.tint(tk.panel, 0.12),
            borderRadius: BorderRadius.circular(lk.rPanel),
            border: Border.all(color: lk.acc.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Text('${tickedTitles.length} ticked', style: ts(w: FontWeight.w600)),
            const SizedBox(width: 10),
            Btn('Mark read', dense: true, icon: Icons.done_all, onTap: () => Library.I.markRead(tickedTitles, true)),
            const SizedBox(width: 6),
            Btn('Mark unread', dense: true, icon: Icons.remove_done, onTap: () => Library.I.markRead(tickedTitles, false)),
            const Spacer(),
            Btn.ghost('Tick all', dense: true, onTap: () => setState(() => ticked.addAll(list.map((t) => t.id)))),
            Btn.ghost('Clear ticks', dense: true, onTap: () => setState(ticked.clear)),
          ]),
        ),
      Expanded(child: gridView ? _chapterGrid() : _chapterList()),
    ]);
  }

  String _chLabel(Title t, int i) =>
      t.displayChapter != null ? 'Ch. ${_num(t.displayChapter!)}' : (t.orderPrefix != null ? '#${t.orderPrefix}' : '${i + 1}');

  Widget _chapterGrid() {
    final list = chapters;
    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final cols = max(1, ((c.maxWidth + gap) / (tile + gap)).ceil());
      final cw = (c.maxWidth - gap * (cols - 1)) / cols;
      final extent = (cw - 2) * 1.42 + 2 + CoverCard.textHeight(cw);
      _cols = cols;
      _rowExtent = extent + gap;
      return GridView.builder(
        controller: _scroll,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols, mainAxisSpacing: gap, crossAxisSpacing: gap, mainAxisExtent: extent),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final t = list[i];
          return CoverCard(
            entry: TitleEntry(t),
            style: 'comfortable',
            width: cw,
            radius: Look.I.coverRadius,
            fill: Settings.I.of(t.section).coverFill,
            selected: current.id == t.id,
            cursor: cursor == i,
            ticked: ticked.contains(t.id),
            anyTicked: selectMode,
            onTap: () => _tapChapter(t, i),
            onMiddle: () => _showChapter(t, i),
            onMenu: (pos) => _menu(t, pos),
            onTick: () => setState(() {
              ticked.contains(t.id) ? ticked.remove(t.id) : ticked.add(t.id);
              lastTick = i;
            }),
          );
        },
      );
    });
  }

  Widget _chapterList() {
    final list = chapters;
    final thumb = (tile / 4).clamp(24.0, 90.0);
    final extent = max(lk.hRow + 8, thumb * 1.42 + 8);
    final lead = (selectMode ? 30.0 : 0) + thumb + 10;
    _rowExtent = extent;
    _cols = 1;
    return Container(
      decoration: BoxDecoration(color: tk.field, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: lead + 16 + _chCols.cols.fold<double>(0, (a, c) => a + _chCols.w(c)),
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _chCols.header(leading: lead)),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemCount: list.length,
                itemExtent: extent,
                itemBuilder: (_, i) {
                  final t = list[i];
                  final isTicked = ticked.contains(t.id);
                  return Hoverable(
                    builder: (h) => Listener(
                      onPointerDown: (ev) {
                        if (ev.buttons & kMiddleMouseButton != 0) _showChapter(t, i);
                      },
                      child: GestureDetector(
                        onTap: () => _tapChapter(t, i),
                        onSecondaryTapDown: (d) => _menu(t, d.globalPosition),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: rowColor(i, hover: h, selected: isTicked || t.id == current.id, cursor: cursor == i),
                              border: cursor == i ? Border(left: BorderSide(color: lk.acc, width: 3)) : null,
                            ),
                            child: Row(children: [
                              if (selectMode)
                                SizedBox(
                                  width: 30,
                                  child: Checkbox(
                                      value: isTicked,
                                      onChanged: (_) => setState(() {
                                            isTicked ? ticked.remove(t.id) : ticked.add(t.id);
                                            lastTick = i;
                                          })),
                                ),
                              SizedBox(
                                width: thumb + 10,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: SizedBox(width: thumb, height: thumb * 1.42, child: CoverThumb(title: t)),
                                  ),
                                ),
                              ),
                              _chCols.row([
                                Text(_chLabel(t, i), style: ts(c: tk.sec, tab: true)),
                                Row(children: [
                                  Flexible(
                                    child: Text(t.displayTitle,
                                        style: ts(c: t.isRead ? tk.faint : tk.text, w: t.inProgress ? FontWeight.w600 : null),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (t.favourite)
                                    const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(Icons.favorite, size: 13, color: Color(0xFFFF6FB1))),
                                ]),
                                Text('${t.pages}', style: ts(c: tk.sec, tab: true)),
                                t.rating > 0 ? Stars(value: t.rating, size: 12) : const SizedBox(),
                                Text(t.lastReadAt > 0 ? dateText(t.lastReadAt) : '', style: ts(c: tk.sec, tab: true)),
                                Progress(value: t.progress, height: 4),
                                t.isRead ? Icon(Icons.check, size: 15, color: tk.ok) : const SizedBox(),
                              ]),
                            ]),
                          ),
                        ),
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

  void _menu(Title t, Offset at) async {
    final prev = Library.I.previousChapters(t);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        PopupMenuItem(value: 'read', child: Text('Read', style: ts())),
        PopupMenuItem(value: 'mark', child: Text(t.isRead ? 'Mark unread' : 'Mark read', style: ts())),
        if (prev.isNotEmpty)
          PopupMenuItem(value: 'prev', child: Text('Mark previous as read (${prev.length})', style: ts())),
        PopupMenuItem(value: 'fav', child: Text(t.favourite ? 'Not a favourite' : 'Favourite', style: ts())),
      ],
    );
    switch (v) {
      case 'read':
        _read(t);
      case 'mark':
        Library.I.markRead([t], !t.isRead);
      case 'prev':
        Library.I.markRead(prev, true);
        toast('Marked ${prev.length} earlier chapters as read');
      case 'fav':
        Library.I.toggleFavourite([t]);
    }
  }
}

