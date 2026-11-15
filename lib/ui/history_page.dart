import 'package:material_ui/material_ui.dart' hide Title;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'app.dart';
import 'library_page.dart';
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
        final list = items
            .where((i) => query.isEmpty ||
                '${i.title.displayTitle} ${i.title.displayArtist ?? ''} ${i.title.altTitle ?? ''}'.toLowerCase().contains(query))
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        final rows = <Widget>[];
        String? lastDay;
        for (final it in list) {
          final day = _dayLabel(it.at);
          if (day != lastDay) {
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text(day, style: ts(w: FontWeight.w700, c: tk.sec)),
            ));
            lastDay = day;
          }
          rows.add(_row(it));
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('History', style: ts(size: 15, w: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(child: Text('Every time you opened something: when, for how long, and which pages.', style: ts(c: tk.sec))),
            ]),
            const SizedBox(height: 8),
            PanelBox(
              child: Row(children: [
                Seg<Section?>(
                  value: section,
                  items: [(null, 'All sections'), for (final s in Section.values) (s, s.label)],
                  onChanged: (v) => setState(() => section = v),
                ),
                const SizedBox(width: 8),
                Expanded(child: Field(hint: 'Search history', icon: Icons.search, onChanged: (v) => setState(() => q = v))),
                const SizedBox(width: 8),
                Btn('Clear history', kind: BtnKind.dangerGhost, onTap: () async {
                  final ok = await confirm(
                      context,
                      'Clear ${section == null ? 'all' : section!.label} history?',
                      'Reading sessions are removed. Read counts, ratings, favourites and tags stay, and your files aren\'t touched.',
                      confirmLabel: 'Clear history',
                      danger: true);
                  if (ok) {
                    Db.I.deleteAllHistory(section);
                    Library.I.changed();
                  }
                }),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(icon: Icons.history, text: 'Nothing read yet. What you read shows up here.')
                  : ListView(children: rows),
            ),
          ]),
        );
      },
    );
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

  Widget _row(_Item it) {
    final t = it.title;
    final s = it.session;
    return Hoverable(
      builder: (h) => Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: h ? tk.raised : null, borderRadius: BorderRadius.circular(lk.rControl)),
        child: Row(children: [
          SizedBox(width: 42, height: 60, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CoverThumb(title: t, width: 42))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.displayTitle, style: ts(w: FontWeight.w600), overflow: TextOverflow.ellipsis),
              Text(
                  [
                    if (section == null) t.section.label,
                    if (t.displayArtist != null) t.displayArtist!,
                  ].join(' · '),
                  style: ts(c: tk.faint, size: 12),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (s != null) ...[
            SizedBox(width: 130, child: Text('${timeText(s.startedAt)} → ${timeText(s.endedAt)}', style: ts(c: tk.sec, tab: true))),
            SizedBox(width: 80, child: Text(humanHours(s.activeSeconds), style: ts(c: tk.sec, tab: true))),
            SizedBox(
                width: 170,
                child: Text('p${s.fromPage + 1} → p${s.toPage + 1} · ${s.pagesSeen} pages', style: ts(c: tk.sec, tab: true))),
            SizedBox(width: 70, child: s.completed ? Text('Finished', style: ts(c: tk.ok, w: FontWeight.w600)) : const SizedBox()),
            SizedBox(width: 40, child: Text(s.device, style: ts(c: tk.faint, size: 12))),
          ] else
            SizedBox(width: 490, child: Text(it.note ?? '', style: ts(c: tk.sec))),
          IconBtn(Icons.menu_book_outlined, tooltip: 'Read', onTap: () => openReader(context, t)),
          if (s != null)
            IconBtn(Icons.delete_outline, tooltip: 'Remove this entry', onTap: () async {
              if (await confirm(context, 'Remove this history entry?', 'Only the record of this session is removed.',
                  confirmLabel: 'Remove entry')) {
                Db.I.deleteSession(s.id);
                Library.I.changed();
              }
            }),
        ]),
      ),
    );
  }
}
