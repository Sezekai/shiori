import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path_provider/path_provider.dart';

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import '../ui/covers.dart';
import '../ui/look.dart';
import '../ui/widgets.dart';
import 'lock.dart';
import 'm_library.dart';
import 'mobile_app.dart';
import 'pc.dart';
import 'store.dart';

Section get _section => Section.values.byName(Settings.I.get<String>('m.section', Section.comics.name));

Widget _heading(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(children: [
        Expanded(child: Text(text, style: ts(size: 20, w: FontWeight.w800))),
        ?trailing,
      ]),
    );

// ===================================================================== history

class MHistoryScreen extends StatefulWidget {
  const MHistoryScreen({super.key});
  @override
  State<MHistoryScreen> createState() => _MHistoryScreenState();
}

class _MHistoryScreenState extends State<MHistoryScreen> {
  Section? section;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Library.I,
      builder: (context, _) {
        final list = Db.I.sessions(section: section).take(600).toList();
        final rows = <Object>[];
        String? last;
        for (final s in list) {
          final d = dateText(s.startedAt);
          if (d != last) {
            rows.add(d);
            last = d;
          }
          rows.add(s);
        }
        return Column(children: [
          _heading('History', trailing: const ConnectionPill()),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final s in <Section?>[null, ...Section.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                  child: ChoiceChip(
                    label: Text(s?.label ?? 'All'),
                    selected: s == section,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => section = s),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text('Nothing read yet.', style: ts(c: tk.sec)))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      if (r is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                          child: Text(r, style: ts(w: FontWeight.w700, c: tk.sec)),
                        );
                      }
                      final s = r as ReadingSession;
                      final t = Library.I.byId(s.titleId);
                      if (t == null) return const SizedBox();
                      return ListTile(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MTitleScreen(entry: TitleEntry(t)))),
                        leading: SizedBox(
                            width: 38, height: 54, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CoverThumb(title: t))),
                        title: Text(t.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(w: FontWeight.w600)),
                        subtitle: Text(
                          [
                            timeText(s.startedAt),
                            humanHours(s.activeSeconds),
                            'p${s.fromPage + 1}→${s.toPage + 1}',
                            s.device,
                          ].join(' · '),
                          style: ts(c: tk.sec, size: 12),
                        ),
                        trailing: s.completed ? Icon(Icons.check_circle, color: tk.ok, size: 18) : null,
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}

// ===================================================================== stats

class MStatsScreen extends StatefulWidget {
  const MStatsScreen({super.key});
  @override
  State<MStatsScreen> createState() => _MStatsScreenState();
}

class _MStatsScreenState extends State<MStatsScreen> {
  Section? section;
  int days = 0; // 0 = all time

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Library.I,
      builder: (context, _) {
        final since = days == 0 ? 0 : nowSec() - days * 86400;
        final sessions = Db.I.sessions(section: section).where((s) => s.startedAt >= since).toList();
        final completions = Db.I.completions(section: section).where((c) => c.$2 >= since).toList();
        final titles = section == null ? Section.values.expand(Library.I.titles).toList() : Library.I.titles(section!);
        final secs = sessions.fold<int>(0, (a, s) => a + s.activeSeconds);
        final pages = sessions.fold<int>(0, (a, s) => a + s.pagesSeen);
        final phoneSecs = sessions.where((s) => s.device != 'PC').fold<int>(0, (a, s) => a + s.activeSeconds);
        final byHour = List<int>.filled(24, 0);
        for (final s in sessions) {
          byHour[DateTime.fromMillisecondsSinceEpoch(s.startedAt * 1000).hour] += s.activeSeconds;
        }
        final topHour = byHour.reduce(max);
        final readTitles = completions.map((c) => c.$1).toSet().length;
        final rated = titles.where((t) => t.rating > 0).toList();
        return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          _heading('Stats'),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final s in <Section?>[null, ...Section.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                  child: ChoiceChip(
                      label: Text(s?.label ?? 'All'), selected: s == section, showCheckmark: false, onSelected: (_) => setState(() => section = s)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 7, label: Text('Week')),
                ButtonSegment(value: 30, label: Text('Month')),
                ButtonSegment(value: 365, label: Text('Year')),
                ButtonSegment(value: 0, label: Text('All')),
              ],
              selected: {days},
              onSelectionChanged: (x) => setState(() => days = x.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _tile('Time reading', humanHours(secs)),
              _tile('Titles finished', '$readTitles'),
              _tile('Pages seen', '$pages'),
              _tile('Sessions', '${sessions.length}'),
              _tile('In the library', '${titles.where((t) => !t.missing).length}'),
              _tile('Average rating', rated.isEmpty ? '–' : (rated.fold<double>(0, (a, t) => a + t.rating) / rated.length).toStringAsFixed(1)),
              _tile('On the phone', secs == 0 ? '–' : '${(phoneSecs * 100 / secs).round()}%'),
              _tile('Favourites', '${titles.where((t) => t.favourite).length}'),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text('When you read', style: ts(w: FontWeight.w700)),
          ),
          SizedBox(
            height: 120,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var h = 0; h < 24; h++)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(
                        height: topHour == 0 ? 0 : 90 * byHour[h] / topHour,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(color: lk.acc, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(height: 3),
                      Text(h % 6 == 0 ? '$h' : '', style: ts(size: 10, c: tk.faint)),
                    ]),
                  ),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _tile(String label, String value) => Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: tk.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: ts(size: 20, w: FontWeight.w800, tab: true)),
          Text(label, style: ts(c: tk.sec, size: 12)),
        ]),
      );
}

// ===================================================================== more

class MMoreScreen extends StatelessWidget {
  const MMoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListenableBuilder(
      listenable: Listenable.merge([Store.I, Pc.I, Jobs.I]),
      builder: (context, _) {
        final saves = Store.I.saveQueue;
        return ListView(children: [
          _heading('More'),
          ListTile(
            leading: const Icon(Icons.computer),
            title: Text('Connect to PC', style: ts()),
            subtitle: Text(Pc.I.paired ? Pc.I.pcName : 'Not paired yet', style: ts(c: tk.sec, size: 12)),
            trailing: const ConnectionPill(),
            onTap: () => go(const ConnectScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.download_done),
            title: Text('Downloads', style: ts()),
            subtitle: Text(
                '${Store.I.downloads.length} title${Store.I.downloads.length == 1 ? '' : 's'}'
                '${Jobs.I.queue.isNotEmpty || Jobs.I.current != null ? ' · ${Jobs.I.queue.length + (Jobs.I.current == null ? 0 : 1)} in progress' : ''}',
                style: ts(c: tk.sec, size: 12)),
            onTap: () => go(const DownloadsScreen()),
          ),
          ListTile(
            leading: Badge(isLabelVisible: saves.isNotEmpty, label: Text('${saves.length}'), child: const Icon(Icons.bookmark_add_outlined)),
            title: Text('Waiting to save', style: ts()),
            subtitle: Text(saves.isEmpty ? 'Nothing waiting' : '${saves.length} page${saves.length == 1 ? '' : 's'} to save on the PC',
                style: ts(c: tk.sec, size: 12)),
            onTap: () => go(const SaveQueueScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text('Storage', style: ts()),
            subtitle: Text('Covers, downloads and library data', style: ts(c: tk.sec, size: 12)),
            onTap: () => go(const StorageScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text('Settings', style: ts()),
            subtitle: Text('Reader, app lock, downloads', style: ts(c: tk.sec, size: 12)),
            onTap: () => go(const MSettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text('Log', style: ts()),
            onTap: () => go(const MLogScreen()),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Shiori $mobileVersion · ${Store.I.waiting} change${Store.I.waiting == 1 ? '' : 's'} waiting to sync',
                style: ts(c: tk.faint, size: 12)),
          ),
        ]);
      },
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Downloads', style: ts(size: 17, w: FontWeight.w700))),
      body: ListenableBuilder(
        listenable: Listenable.merge([Store.I, Jobs.I]),
        builder: (context, _) {
          final rows = Db.I.raw.select('SELECT * FROM downloads ORDER BY at DESC');
          final total = rows.fold<int>(0, (a, r) => a + (r['size'] as int));
          return ListView(children: [
            if (Jobs.I.current != null) JobProgress(job: Jobs.I.current!, queued: Jobs.I.queue.length),
            for (final j in Jobs.I.queue)
              ListTile(
                dense: true,
                leading: Icon(Icons.schedule, color: tk.sec),
                title: Text(j.name, style: ts(c: tk.sec)),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Jobs.I.cancel(j)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('${rows.length} downloaded · ${humanSize(total)}', style: ts(c: tk.sec)),
            ),
            for (final r in rows)
              if (Library.I.byId(r['title_id'] as int? ?? -1) case final t?)
                ListTile(
                  leading: SizedBox(
                      width: 38, height: 54, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CoverThumb(title: t))),
                  title: Text(t.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts()),
                  subtitle: Text('${humanSize(r['size'] as int)} · ${dateText(r['at'] as int)}${t.isRead ? ' · read' : ''}',
                      style: ts(c: tk.sec, size: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove from the phone',
                    onPressed: () => Store.I.removeDownload([t]),
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MTitleScreen(entry: TitleEntry(t)))),
                ),
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () async {
                    final read = [
                      for (final r in rows)
                        if (Library.I.byId(r['title_id'] as int? ?? -1) case final t? when t.isRead) t,
                    ];
                    if (read.isEmpty) {
                      mToast('No downloaded titles are read yet');
                      return;
                    }
                    if (await mConfirm(context, 'Remove ${read.length} read download${read.length == 1 ? '' : 's'}?',
                        'Only the phone\'s copies go. The files on the PC stay.', 'Remove')) {
                      Store.I.removeDownload(read);
                    }
                  },
                  child: const Text('Remove downloads already read'),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class SaveQueueScreen extends StatelessWidget {
  const SaveQueueScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Waiting to save', style: ts(size: 17, w: FontWeight.w700))),
      body: ListenableBuilder(
        listenable: Listenable.merge([Store.I, Pc.I]),
        builder: (context, _) {
          final q = Store.I.saveQueue;
          if (q.isEmpty) {
            return Center(child: Text('Nothing waiting. Pages saved while offline show here.', style: ts(c: tk.sec)));
          }
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  Pc.I.online
                      ? 'These go to the PC on the next sync.'
                      : 'The PC saves these from its own files (full quality) when you\'re connected again.',
                  style: ts(c: tk.sec)),
            ),
            if (Pc.I.online)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton(onPressed: Sync.queue, child: const Text('Save them now')),
              ),
            for (final c in q)
              Builder(builder: (context) {
                final pl = (c['payload'] as Map).cast<String, dynamic>();
                final dup = pl['status'] == 'duplicate';
                return ListTile(
                  title: Text(pl['title'] as String? ?? '', style: ts()),
                  subtitle: Text(
                      dup
                          ? 'Already saved from this chapter on ${dateText(pl['dupAt'] as int? ?? 0)}. Save another copy?'
                          : '${pl['label']} · asked ${dateText(c['at'] as int)}',
                      style: ts(c: dup ? tk.warn : tk.sec, size: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (dup) TextButton(onPressed: () => Store.I.forceSave(c['uid'] as String), child: const Text('Save anyway')),
                    IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Cancel',
                        onPressed: () => Store.I.cancelSave(c['uid'] as String)),
                  ]),
                );
              }),
          ]);
        },
      ),
    );
  }
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  final Map<String, int?> sizes = {};
  String? downloads;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    downloads = await Store.I.downloadsDir();
    final places = {
      'covers': AppPaths.I.thumbs,
      'downloads': downloads!,
      'stream': Store.I.streamCache,
      'data': AppPaths.I.data,
    };
    for (final e in places.entries) {
      int n;
      if (e.key == 'data') {
        n = 0;
        for (final f in [AppPaths.I.db, '${AppPaths.I.db}-wal', AppPaths.I.settingsFile]) {
          try {
            n += File(f).lengthSync();
          } catch (_) {}
        }
      } else {
        n = await Store.dirSize(e.value);
      }
      if (!mounted) return;
      setState(() => sizes[e.key] = n);
    }
  }

  String _s(String k) => sizes[k] == null ? 'measuring…' : humanSize(sizes[k]!);

  @override
  Widget build(BuildContext context) {
    final covers = Thumbs.I.names.length;
    return Scaffold(
      appBar: AppBar(title: Text('Storage', style: ts(size: 17, w: FontWeight.w700))),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: Text('Covers', style: ts()),
          subtitle: Text('$covers covers · ${_s('covers')}. Always kept, so the library works offline.', style: ts(c: tk.sec, size: 12)),
        ),
        ListTile(
          leading: const Icon(Icons.download_done),
          title: Text('Downloads', style: ts()),
          subtitle: Text('${Store.I.downloads.length} titles · ${_s('downloads')}\n$downloads', style: ts(c: tk.sec, size: 12)),
          isThreeLine: true,
        ),
        ListTile(
          leading: const Icon(Icons.history_toggle_off),
          title: Text('Recently read pages', style: ts()),
          subtitle: Text('The last ${6} files read from the PC · ${_s('stream')}', style: ts(c: tk.sec, size: 12)),
          trailing: TextButton(
            onPressed: () async {
              try {
                Directory(Store.I.streamCache).deleteSync(recursive: true);
              } catch (_) {}
              await _measure();
            },
            child: const Text('Clear'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text('Library data and history', style: ts()),
          subtitle: Text(_s('data'), style: ts(c: tk.sec, size: 12)),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
              'Removing a download only removes the phone\'s copy. Nothing here ever changes the files on the PC.',
              style: ts(c: tk.faint, size: 12)),
        ),
      ]),
    );
  }
}

class MSettingsScreen extends StatefulWidget {
  const MSettingsScreen({super.key});
  @override
  State<MSettingsScreen> createState() => _MSettingsScreenState();
}

class _MSettingsScreenState extends State<MSettingsScreen> {
  bool? canLock;
  bool hasSd = false;

  @override
  void initState() {
    super.initState();
    AppLock.available().then((v) => mounted ? setState(() => canLock = v) : null);
    _sd();
  }

  Future<void> _sd() async {
    if (!Platform.isAndroid) return;
    try {
      final dirs = await getExternalStorageDirectories();
      if (mounted) setState(() => hasSd = (dirs?.length ?? 0) > 1);
    } catch (_) {}
  }

  Widget _switch(String title, String key, bool fallback, {String? sub, ValueChanged<bool>? after}) => SwitchListTile(
        title: Text(title, style: ts()),
        subtitle: sub == null ? null : Text(sub, style: ts(c: tk.sec, size: 12)),
        value: Settings.I.get<bool>(key, fallback),
        onChanged: (v) {
          Settings.I.put(key, v);
          after?.call(v);
          setState(() {});
        },
      );

  Widget _choice<T>(String title, String key, T fallback, List<(T, String)> items) => ListTile(
        title: Text(title, style: ts()),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [for (final (v, l) in items) ButtonSegment(value: v, label: Text(l))],
            selected: {Settings.I.get<T>(key, fallback)},
            onSelectionChanged: (x) {
              Settings.I.put(key, x.first);
              setState(() {});
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _section;
    final ss = Settings.I.of(s);
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: ts(size: 17, w: FontWeight.w700))),
      body: ListView(children: [
        _group('Reader'),
        ListTile(
          title: Text('${s.label}: reading direction', style: ts()),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SegmentedButton<ReadDirection>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ReadDirection.ltr, label: Text('L → R')),
                ButtonSegment(value: ReadDirection.rtl, label: Text('R → L')),
                ButtonSegment(value: ReadDirection.ttb, label: Text('Down')),
              ],
              selected: {ss.direction},
              onSelectionChanged: (x) {
                ss.direction = x.first;
                Settings.I.extra['m.ownReader'] = true;
                Settings.I.save();
                setState(() {});
              },
            ),
          ),
        ),
        _switch('Follow the PC\'s reading settings', 'm.followPc', true,
            sub: 'Direction, cover offset and splitting come from the PC on each sync, until you change them here.',
            after: (v) => Settings.I.put('m.ownReader', !v)),
        _choice<String>('Two pages side by side', 'm.twoPages', 'auto', const [('auto', 'Unfolded'), ('always', 'Always'), ('never', 'Never')]),
        _choice<String>('Tap zones', 'm.tapZones', 'follow',
            const [('follow', 'Follow direction'), ('fixed', 'Left = back'), ('off', 'Off')]),
        _switch('Volume keys turn pages', 'm.volumeKeys', true),
        _switch('Skip chapters already read', 'm.skipRead', false, after: (v) {
          Settings.I.skipRead = v;
          Settings.I.save();
        }),
        _group('Downloads'),
        if (hasSd)
          _choice<String>('Keep downloads on', 'm.downloadsAt', 'internal', const [('internal', 'Phone storage'), ('sd', 'SD card')]),
        _switch('Remove downloads once read', 'm.removeWhenRead', false, sub: 'Only the phone\'s copy; never the PC file.'),
        _group('Privacy'),
        _switch('App lock', 'm.lock', false,
            sub: canLock == false
                ? 'This phone has no screen lock set up, so the app lock can\'t be used.'
                : 'Fingerprint, face or PIN, using the phone\'s own lock.', after: (v) async {
          if (v && !await AppLock.check('Turn on the app lock')) {
            Settings.I.put('m.lock', false);
            if (mounted) setState(() {});
          }
        }),
        if (Settings.I.get<bool>('m.lock', false))
          _choice<int>('Lock again after', 'm.lockAfter', 0, const [(0, 'Straight away'), (60, '1 min'), (300, '5 min'), (900, '15 min')]),
        _switch('Hide Shiori in recent apps', 'm.hideRecents', false,
            sub: 'Also stops screenshots inside the app.', after: Native.setSecure),
        _group('Looks'),
        ListTile(
          title: Text('Text size', style: ts()),
          subtitle: Slider(
            value: lk.fontSize.clamp(12, 18),
            min: 12,
            max: 18,
            divisions: 12,
            onChanged: (v) {
              Look.I.fontSize = v;
              Look.I.changed();
            },
            onChangeEnd: (_) => Look.I.save(),
          ),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  Widget _group(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(t, style: ts(c: lk.acc, w: FontWeight.w700)),
      );
}

class MLogScreen extends StatelessWidget {
  const MLogScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lines = AppLog.I.lines.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text('Log', style: ts(size: 17, w: FontWeight.w700))),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: lines.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${lines[i]}', style: ts(mono: true, size: 11, c: tk.sec)),
        ),
      ),
    );
  }
}

