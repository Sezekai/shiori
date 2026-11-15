import 'dart:math';

import 'package:material_ui/material_ui.dart' hide Title;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'app.dart';
import 'widgets.dart';

/// Reading stats, Mihon-style, per section or across all three.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Section? section = Nav.I.section;
  String period = 'all';

  int get since => switch (period) {
        'year' => DateTime(DateTime.now().year).millisecondsSinceEpoch ~/ 1000,
        'month' => DateTime(DateTime.now().year, DateTime.now().month).millisecondsSinceEpoch ~/ 1000,
        '30' => nowSec() - 30 * 86400,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final titles = section == null
        ? Section.values.expand((s) => Library.I.titles(s)).where((t) => !t.missing).toList()
        : Library.I.titles(section!).where((t) => !t.missing).toList();
    final sessions = Db.I.sessions(section: section).where((s) => s.startedAt >= since).toList();
    final comps = Db.I.completions(section: section).where((c) => c.$2 >= since || (since == 0)).toList();
    final completedIds = comps.map((c) => c.$1).toSet();
    final pagesRead = sessions.fold<int>(0, (a, s) => a + s.pagesSeen);
    final secs = sessions.fold<int>(0, (a, s) => a + s.activeSeconds);
    final rated = titles.where((t) => t.rating > 0).toList();
    final avgRating = rated.isEmpty ? 0.0 : rated.fold<double>(0, (a, t) => a + t.rating) / rated.length;
    final started = titles.where((t) => t.lastPage > 0 || t.isRead).length;
    final artists = titles.map((t) => t.displayArtist).whereType<String>().toSet();

    // Days with reading, for streaks and the heatmap.
    final dayPages = <int, int>{};
    int dayOf(int at) {
      final d = DateTime.fromMillisecondsSinceEpoch(at * 1000);
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
    }

    for (final s in Db.I.sessions(section: section)) {
      dayPages[dayOf(s.startedAt)] = (dayPages[dayOf(s.startedAt)] ?? 0) + s.pagesSeen;
    }
    final today = dayOf(nowSec());
    var current = 0;
    for (var d = today; dayPages.containsKey(d) || (d == today && dayPages.containsKey(d - 1)); d--) {
      if (dayPages.containsKey(d)) current++;
      if (d < today - 3650) break;
    }
    var longest = 0, run = 0;
    final days = dayPages.keys.toList()..sort();
    for (var i = 0; i < days.length; i++) {
      run = i > 0 && days[i] == days[i - 1] + 1 ? run + 1 : 1;
      longest = max(longest, run);
    }

    // Months.
    final now = DateTime.now();
    final months = List.generate(12, (i) => DateTime(now.year, now.month - 11 + i));
    final monthPages = List<double>.filled(12, 0);
    final monthHours = List<double>.filled(12, 0);
    for (final s in Db.I.sessions(section: section)) {
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt * 1000);
      final i = (d.year - months.first.year) * 12 + d.month - months.first.month;
      if (i >= 0 && i < 12) {
        monthPages[i] += s.pagesSeen;
        monthHours[i] += s.activeSeconds / 3600;
      }
    }
    final hours = List<double>.filled(24, 0);
    for (final s in sessions) {
      hours[DateTime.fromMillisecondsSinceEpoch(s.startedAt * 1000).hour] += s.activeSeconds / 60;
    }
    final ratingDist = List<double>.filled(10, 0);
    for (final t in rated) {
      ratingDist[(t.rating * 2).round().clamp(1, 10) - 1]++;
    }

    // Tops.
    final byArtist = <String, int>{};
    for (final c in comps) {
      final a = Library.I.byId(c.$1)?.displayArtist;
      if (a != null) byArtist[a] = (byArtist[a] ?? 0) + 1;
    }
    final topArtists = byArtist.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final reread = titles.where((t) => t.readCount > 1).toList()..sort((a, b) => b.readCount.compareTo(a.readCount));
    final artistRatings = <String, List<double>>{};
    for (final t in rated) {
      final a = t.displayArtist;
      if (a != null) artistRatings.putIfAbsent(a, () => []).add(t.rating);
    }
    final bestArtists = artistRatings.entries.where((e) => e.value.length >= 2).toList()
      ..sort((a, b) => (b.value.reduce((x, y) => x + y) / b.value.length).compareTo(a.value.reduce((x, y) => x + y) / a.value.length));
    final avgSession = sessions.isEmpty ? 0 : secs ~/ sessions.length;
    final pcShare = sessions.isEmpty ? 1.0 : sessions.where((s) => s.device == 'PC').length / sessions.length;

    Widget tile(String label, String value, [String? sub]) => Container(
          width: 178,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: ts(c: tk.sec, size: 12)),
            const SizedBox(height: 4),
            Text(value, style: ts(size: 22, w: FontWeight.w700, tab: true)),
            if (sub != null) Text(sub, style: ts(c: tk.faint, size: 11.5)),
          ]),
        );

    Widget card(String title, Widget child, {double width = 560}) => Container(
          width: width,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: ts(w: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ]),
        );

    const mn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Stats', style: ts(size: 15, w: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(child: Text('How much you read, when, and what.', style: ts(c: tk.sec))),
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
            Seg<String>(
              value: period,
              items: const [('all', 'All time'), ('year', 'This year'), ('month', 'This month'), ('30', 'Last 30 days')],
              onChanged: (v) => setState(() => period = v),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              tile('Completed', '${completedIds.length}', 'different titles finished'),
              tile('Total reads', '${comps.length}', 'including re-reads'),
              tile('Pages read', '$pagesRead'),
              tile('Time reading', humanHours(secs)),
              tile('Titles started', '$started', 'of ${titles.length} in the library'),
              tile('Unread', '${titles.where((t) => !t.isRead).length}'),
              tile('In progress', '${titles.where((t) => t.inProgress).length}'),
              tile('Favourites', '${titles.where((t) => t.favourite).length}'),
              tile('Average rating', avgRating == 0 ? '–' : avgRating.toStringAsFixed(2), '${rated.length} rated'),
              tile('Library size', humanSize(titles.fold<int>(0, (a, t) => a + t.size)),
                  '${titles.fold<int>(0, (a, t) => a + t.pages)} pages'),
              tile('Artists', '${artists.length}'),
              tile('Streak', '$current days', 'longest: $longest days'),
              tile('Average session', humanHours(avgSession)),
              tile('Read on PC', '${(pcShare * 100).round()}%', 'the rest on your phone'),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              card('Pages read per month', Bars(values: monthPages, labels: [for (final m in months) mn[m.month - 1]], height: 160)),
              card('Hours reading per month', Bars(values: monthHours, labels: [for (final m in months) mn[m.month - 1]], height: 160, decimals: 1)),
              card('Reading days, last 26 weeks', Heatmap(dayPages: dayPages, today: today)),
              card('When you read (minutes by hour of day)',
                  Bars(values: hours, labels: [for (var h = 0; h < 24; h++) h % 3 == 0 ? '$h' : ''], height: 140)),
              card('Ratings', Bars(values: ratingDist, labels: [for (var i = 1; i <= 10; i++) (i / 2).toString().replaceAll('.0', '')], height: 140)),
              card(
                  'Most read artists',
                  Column(children: [
                    for (final e in topArtists.take(8)) _rankRow(e.key, '${e.value} reads', e.value / max(1, topArtists.first.value)),
                    if (topArtists.isEmpty) Text('Nothing finished yet.', style: ts(c: tk.faint)),
                  ])),
              card(
                  'Most re-read',
                  Column(children: [
                    for (final t in reread.take(8)) _rankRow(t.displayTitle, '×${t.readCount}', t.readCount / max(1, reread.first.readCount)),
                    if (reread.isEmpty) Text('Nothing read twice yet.', style: ts(c: tk.faint)),
                  ])),
              card(
                  'Best rated artists (2+ rated titles)',
                  Column(children: [
                    for (final e in bestArtists.take(8))
                      _rankRow(e.key, (e.value.reduce((a, b) => a + b) / e.value.length).toStringAsFixed(2),
                          (e.value.reduce((a, b) => a + b) / e.value.length) / 5),
                    if (bestArtists.isEmpty) Text('Rate a few more titles to see this.', style: ts(c: tk.faint)),
                  ])),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _rankRow(String name, String value, double frac) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 220, child: Text(name, style: ts(), overflow: TextOverflow.ellipsis)),
          Expanded(child: Progress(value: frac, height: 6)),
          SizedBox(width: 80, child: Text(value, textAlign: TextAlign.right, style: ts(c: tk.sec, tab: true))),
        ]),
      );
}

class Bars extends StatelessWidget {
  const Bars({super.key, required this.values, required this.labels, this.height = 150, this.decimals = 0});
  final List<double> values;
  final List<String> labels;
  final double height;
  final int decimals;
  @override
  Widget build(BuildContext context) {
    final top = values.isEmpty ? 1.0 : max(1.0, values.reduce(max));
    return SizedBox(
      height: height + 34,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Tooltip(
              message: '${labels[i].isEmpty ? i : labels[i]}: ${values[i].toStringAsFixed(decimals)}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (values[i] > 0 && values.length <= 12)
                  Text(values[i].toStringAsFixed(decimals), style: ts(size: 10.5, c: tk.faint, tab: true)),
                Container(
                  height: max(values[i] > 0 ? 2.0 : 0.0, values[i] / top * height),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(gradient: lk.grad, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: ts(size: 10.5, c: tk.faint)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class Heatmap extends StatelessWidget {
  const Heatmap({super.key, required this.dayPages, required this.today});
  final Map<int, int> dayPages;
  final int today;
  @override
  Widget build(BuildContext context) {
    const weeks = 26;
    final top = dayPages.values.isEmpty ? 1 : max(1, dayPages.values.reduce(max));
    final todayDate = DateTime.fromMillisecondsSinceEpoch(today * 86400000);
    final endOfWeek = today + (7 - todayDate.weekday);
    return SizedBox(
      height: 7 * 16.0,
      child: Row(children: [
        for (var w = weeks - 1; w >= 0; w--)
          Column(children: [
            for (var d = 6; d >= 0; d--)
              () {
                final day = endOfWeek - w * 7 - d;
                final v = dayPages[day] ?? 0;
                return Tooltip(
                  message: '${dateText(day * 86400)}: $v pages',
                  child: Container(
                    width: 13,
                    height: 13,
                    margin: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: day > today ? Colors.transparent : (v == 0 ? tk.raised2 : Color.lerp(tk.raised2, lk.acc, 0.3 + 0.7 * v / top)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }(),
          ]),
      ]),
    );
  }
}
