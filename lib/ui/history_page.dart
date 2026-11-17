import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'app.dart';
import 'covers.dart';
import 'widgets.dart';

class _Item {
  _Item(this.at, this.title, {this.session, this.note});
  final int at;
  final Title title;
  final ReadingSession? session;
  final String? note;
}

/// Every reading session, newest first, grouped by day.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Section? section = Nav.I.section;
  String q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Library.I,
      builder: (context, _) {
        final items = <_Item>[];
        for (final s in Db.I.sessions(section: section)) {
          final t = Library.I.byId(s.titleId);
          if (t != null) items.add(_Item(s.startedAt, t, session: s));
        }
        for (final c in Db.I.completions(section: section)) {
          if (c.$4 == 'pc' && !c.$3) continue;
          final t = Library.I.byId(c.$1);
          if (t != null) items.add(_Item(c.$2, t, note: c.$4 == 'yacreader' ? 'Read · from YACReader' : 'Marked read by hand'));
        }
        final query = q.toLowerCase();
        final list =
            items
                .where(
                  (i) =>
                      query.isEmpty ||
                      '${i.title.displayTitle} ${i.title.displayArtist ?? ''} ${i.title.altTitle ?? ''}'.toLowerCase().contains(
                        query,
                      ),
                )
                .toList()
              ..sort((a, b) => b.at.compareTo(a.at));
        // Day headers and rows in one list, so the keyboard can walk the rows.
        final rows = <Object>[]; // String header or _Item
        String? lastDay;
        for (final it in list) {
          final day = _dayLabel(it.at);
          if (day != lastDay) {
            rows.add(day);
            lastDay = day;
          }
          rows.add(it);
        }
        _rows = rows;
        _items = list;
        return Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('History', style: ts(size: 15, w: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Every time you opened something: when, for how long, and which pages.', style: ts(c: tk.sec)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PanelBox(
                  child: Row(
                    children: [
                      Seg<Section?>(
                        value: section,
                        items: [(null, 'All sections'), for (final s in Section.values) (s, s.label)],
                        onChanged: (v) => setState(() => section = v),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Field(hint: 'Search history', icon: Icons.search, onChanged: (v) => setState(() => q = v)),
                      ),
                      const SizedBox(width: 8),
                      Btn(
                        'Clear history',
                        kind: BtnKind.dangerGhost,
                        onTap: () async {
                          final ok = await confirm(
                            context,
                            'Clear ${section == null ? 'all' : section!.label} history?',
                            'Reading sessions are removed. Read counts, ratings, favourites and tags stay, and your files aren\'t touched.',
                            confirmLabel: 'Clear history',
                            danger: true,
                          );
                          if (ok) {
                            Db.I.deleteAllHistory(section);
                            Library.I.changed();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: rows.isEmpty
                      ? const EmptyState(icon: Icons.history, text: 'Nothing read yet. What you read shows up here.')
                      : Container(
                          decoration: BoxDecoration(
                            color: tk.field,
                            borderRadius: BorderRadius.circular(lk.rPanel),
                            border: Border.all(color: tk.line),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ListenableBuilder(
                              listenable: Settings.I,
                              builder: (_, _) => SizedBox(
                                width: 16 + 54 + 90 + _cols.cols.fold<double>(0, (a, c) => a + _cols.w(c)),
                                child: Column(
                                  children: [
                                    Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _cols.header(leading: 54)),
                                    Expanded(
                                      child: ListView.builder(
                                        controller: _scroll,
                                        itemCount: rows.length,
                                        itemExtentBuilder: (i, _) => i < _rows.length && _rows[i] is String ? _headH : _rowH,
                                        itemBuilder: (_, i) {
                                          final r = rows[i];
                                          if (r is String) {
                                            return Container(
                                              padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                                              alignment: Alignment.bottomLeft,
                                              child: Text(
                                                r,
                                                style: ts(w: FontWeight.w700, c: tk.sec),
                                              ),
                                            );
                                          }
                                          final it = r as _Item;
                                          return _row(it, list.indexOf(it));
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _headH = 40.0, _rowH = 58.0;
  static const _cols = ColumnSet('history', [
    Col('title', 'Title', 380, min: 120),
    Col('time', 'Time', 130),
    Col('length', 'Length', 80),
    Col('pages', 'Pages', 170),
    Col('done', 'Finished', 76),
    Col('device', 'Device', 60),
  ]);
  final FocusNode _keys = FocusNode(debugLabel: 'history');
  final ScrollController _scroll = ScrollController();
  List<Object> _rows = [];
  List<_Item> _items = [];
  int cursor = -1;

  @override
  void dispose() {
    _keys.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || typingInField || _items.isEmpty) return KeyEventResult.ignored;
    final k = e.logicalKey;
    int? move;
    if (k == LogicalKeyboardKey.arrowDown) move = 1;
    if (k == LogicalKeyboardKey.arrowUp) move = -1;
    if (k == LogicalKeyboardKey.pageDown) move = 8;
    if (k == LogicalKeyboardKey.pageUp) move = -8;
    if (k == LogicalKeyboardKey.home) move = -_items.length;
    if (k == LogicalKeyboardKey.end) move = _items.length;
    if (move != null) {
      final i = cursor < 0 ? 0 : (cursor + move).clamp(0, _items.length - 1);
      setState(() => cursor = i);
      _reveal(i);
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && cursor >= 0) {
      openReader(context, _items[cursor].title);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _reveal(int i) {
    if (!_scroll.hasClients) return;
    final item = _items[i];
    var top = 0.0;
    for (final r in _rows) {
      if (identical(r, item)) break;
      top += r is String ? _headH : _rowH;
    }
    final pos = _scroll.position;
    if (top < pos.pixels) {
      _scroll.jumpTo((top - _headH).clamp(0, pos.maxScrollExtent));
    } else if (top + _rowH > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo((top + _rowH - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  }

  String _dayLabel(int at) {
    if (at <= 0) return 'Date unknown';
    final d = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const w = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    if (diff < 7) return w[d.weekday - 1];
    return dateText(at);
  }

  Widget _row(_Item it, int i) {
    final t = it.title;
    final s = it.session;
    return Hoverable(
      builder: (h) => GestureDetector(
        onTap: () {
          _keys.requestFocus();
          setState(() => cursor = i);
        },
        onDoubleTap: () => openReader(context, t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: rowColor(i, hover: h, cursor: cursor == i),
            border: cursor == i ? Border(left: BorderSide(color: lk.acc, width: 3)) : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 36,
                    height: 50,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CoverThumb(title: t),
                    ),
                  ),
                ),
              ),
              _cols.row([
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.displayTitle,
                      style: ts(w: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [if (section == null) t.section.label, if (t.displayArtist != null) t.displayArtist!].join(' · '),
                      style: ts(c: tk.faint, size: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                Text(
                  s == null ? (it.note ?? '') : '${timeText(s.startedAt)} → ${timeText(s.endedAt)}',
                  style: ts(c: tk.sec, tab: true),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(s == null ? '' : humanHours(s.activeSeconds), style: ts(c: tk.sec, tab: true)),
                Text(
                  s == null ? '' : 'p${s.fromPage + 1} → p${s.toPage + 1} · ${s.pagesSeen} pages',
                  style: ts(c: tk.sec, tab: true),
                  overflow: TextOverflow.ellipsis,
                ),
                s != null && s.completed
                    ? Text(
                        'Finished',
                        style: ts(c: tk.ok, w: FontWeight.w600),
                      )
                    : const SizedBox(),
                Text(s?.device ?? '', style: ts(c: tk.faint, size: 12)),
              ]),
              IconBtn(Icons.menu_book_outlined, tooltip: 'Read (Enter)', onTap: () => openReader(context, t)),
              if (s != null)
                IconBtn(
                  Icons.delete_outline,
                  tooltip: 'Remove this entry',
                  onTap: () async {
                    if (await confirm(
                      context,
                      'Remove this history entry?',
                      'Only the record of this session is removed.',
                      confirmLabel: 'Remove entry',
                    )) {
                      Db.I.deleteSession(s.id);
                      Library.I.changed();
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
