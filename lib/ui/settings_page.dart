import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import '../core/yacreader.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Section section = Section.manga;
  final Map<String, int?> sizes = {};

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final places = _places();
    for (final pl in places) {
      sizes[pl.$2] = null;
    }
    if (mounted) setState(() {});
    for (final pl in places) {
      final n = await _dirSize(pl.$2);
      if (!mounted) return;
      setState(() => sizes[pl.$2] = n);
    }
  }

  static Future<int> _dirSize(String path) async {
    final d = Directory(path);
    if (!await d.exists()) return 0;
    var total = 0;
    try {
      await for (final f in d.list(recursive: true, followLinks: false)) {
        if (f is File) total += await f.length();
      }
    } catch (_) {}
    return total;
  }

  List<(String, String, bool canMove, bool canClear)> _places() => [
        ('Settings, library database and appearance', AppPaths.I.data, true, false),
        ('Log files', AppPaths.I.logs, false, false),
        ('Database backups', AppPaths.I.backups, false, false),
        ('Cover cache', AppPaths.I.thumbs, true, true),
        ('Unpacked CBR pages (cache)', AppPaths.I.pageCache, true, true),
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.I,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Settings', style: ts(size: 15, w: FontWeight.w700)),
            const SizedBox(width: 10),
            Text('Changes apply straight away.', style: ts(c: tk.sec)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              _group('Library sections', 'Folders, save folders and reading defaults for each section.', [
                Seg<Section>(
                  value: section,
                  items: [for (final s in Section.values) (s, s.label)],
                  onChanged: (v) => setState(() => section = v),
                ),
                const SizedBox(height: 10),
                ..._sectionSettings(section),
              ]),
              _group('Reader', 'How pages are shown and saved.', [
                _check('Show the page number in a corner', Settings.I.pageNumbers, (v) => Settings.I.pageNumbers = v),
                _check('Skip chapters already read when moving to the next file', Settings.I.skipRead, (v) => Settings.I.skipRead = v),
                _row('Saved pages', Seg<SaveFormat>(
                  value: Settings.I.saveFormat,
                  items: const [(SaveFormat.original, 'Original file'), (SaveFormat.jpg, 'JPG'), (SaveFormat.png, 'PNG')],
                  onChanged: (v) {
                    Settings.I.saveFormat = v;
                    Settings.I.save();
                  },
                )),
                _row('JPG quality', Row(children: [
                  SizedBox(
                    width: 220,
                    child: Slider(
                      value: Settings.I.jpgQuality.toDouble(),
                      min: 40,
                      max: 100,
                      divisions: 60,
                      onChanged: (v) {
                        Settings.I.jpgQuality = v.round();
                        Settings.I.changedQuiet();
                      },
                      onChangeEnd: (_) => Settings.I.save(),
                    ),
                  ),
                  Text('${Settings.I.jpgQuality}', style: ts(tab: true)),
                  const SizedBox(width: 10),
                  Text('Also used for combined two-page saves.', style: ts(c: tk.faint, size: 12)),
                ])),
                _row('Idle after', Row(children: [
                  Drop<int>(
                    value: Settings.I.idleMinutes,
                    items: const [(1, '1 minute'), (2, '2 minutes'), (5, '5 minutes'), (10, '10 minutes'), (30, '30 minutes')],
                    onChanged: (v) {
                      Settings.I.idleMinutes = v;
                      Settings.I.save();
                    },
                  ),
                  const SizedBox(width: 10),
                  Text('Time with no page turns isn\'t counted as reading.', style: ts(c: tk.faint, size: 12)),
                ])),
              ]),
              _group('Library', 'How the library behaves.', [
                _check('Show a reading progress line on covers', Settings.I.progressLine, (v) => Settings.I.progressLine = v),
                _check('Watch the folders and add new files by themselves', Settings.I.watchFolders, (v) {
                  Settings.I.watchFolders = v;
                  Library.I.startWatching();
                }),
                _row('When you click a cover', Seg<String>(
                  value: Settings.I.clickAction,
                  items: const [('select', 'Open its page'), ('tick', 'Tick it')],
                  onChanged: (v) {
                    Settings.I.clickAction = v;
                    Settings.I.save();
                  },
                )),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Btn('Import from YACReader', icon: Icons.download_outlined, onTap: () {
                    if (YacImport.findLibraries().isEmpty) {
                      toast('No YACReader libraries found in your folders', ToastKind.info);
                    } else {
                      YacImport.queue();
                    }
                  }),
                  Btn('Re-read all file names', icon: Icons.text_fields, tooltip: 'Applies the title rules again. Your edits are kept.',
                      onTap: () {
                    for (final s in Section.values) {
                      Library.I.reparse(s);
                    }
                    toast('File names read again');
                  }),
                  Btn('Make missing covers', icon: Icons.image_outlined, onTap: () {
                    for (final s in Section.values) {
                      Thumbs.I.queueMissing(s);
                    }
                  }),
                ]),
                const SizedBox(height: 4),
                Text(Library.I.sevenZip == null ? '7-Zip wasn\'t found, so CBR files can\'t be opened.' : '7-Zip: ${Library.I.sevenZip}',
                    style: ts(c: Library.I.sevenZip == null ? tk.warn : tk.faint, size: 12)),
              ]),
              _group('Storage', 'Everywhere Shiori keeps things, and how much space each uses.', [
                for (final pl in _places()) _storageRow(pl),
              ]),
              _group('Reset', 'Each part asks first and says exactly what is cleared. Your files are never deleted.', [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _reset('Settings', 'All settings go back to their defaults. Your library, history and themes stay.', () {
                    Settings.I.resetToDefaults();
                  }),
                  _reset('Library', 'Shiori forgets every title, with its ratings, favourites, tags and history. Your files stay on disk.', () {
                    Db.I.resetLibrary();
                    Library.I.load();
                  }),
                  _reset('History', 'All reading sessions, read counts and progress are cleared. Titles, ratings, favourites and tags stay.', () {
                    Db.I.resetHistory();
                    Library.I.load();
                  }),
                  _reset('Saved-page memory', 'Shiori forgets which pages were saved, so they can be saved again. The images stay.', () {
                    Db.I.resetSaved();
                  }),
                  _reset('Cover cache', 'Covers are made again when needed.', () async {
                    await _clear(AppPaths.I.thumbs);
                  }),
                  _reset('Page cache', 'Unpacked CBR pages are removed; they\'re unpacked again when opened.', () async {
                    await _clear(AppPaths.I.pageCache);
                  }),
                ]),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _group(String title, String desc, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: ts(w: FontWeight.w700)),
          Text(desc, style: ts(c: tk.sec, size: 12)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _row(String label, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 160, child: Text(label, style: ts(c: tk.sec))),
          Flexible(child: child),
        ]),
      );

  Widget _check(String label, bool v, ValueChanged<bool> on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Checkbox(value: v, onChanged: (x) {
            on(x ?? false);
            Settings.I.save();
          }),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: ts())),
        ]),
      );

  List<Widget> _sectionSettings(Section s) {
    final ss = Settings.I.of(s);
    final excluded = TextEditingController(text: ss.excluded.join(', '));
    return [
      _row('Folders', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final f in ss.folders)
          Row(children: [
            Icon(Directory(f).existsSync() ? Icons.folder_outlined : Icons.folder_off_outlined, size: 16,
                color: Directory(f).existsSync() ? tk.sec : tk.warn),
            const SizedBox(width: 6),
            Flexible(child: Text(f, style: ts(mono: true, size: 12), overflow: TextOverflow.ellipsis)),
            if (!Directory(f).existsSync()) Text('  can\'t be reached', style: ts(c: tk.warn, size: 12)),
            IconBtn(Icons.close, tooltip: 'Take this folder off the list (nothing on disk is touched)', onTap: () {
              ss.folders.remove(f);
              Settings.I.save();
              Library.I.startWatching();
            }),
          ]),
        const SizedBox(height: 4),
        Btn('Add folder…', icon: Icons.create_new_folder_outlined, onTap: () async {
          final d = await FilePicker.getDirectoryPath(dialogTitle: 'Add a ${s.label} folder');
          if (d == null) return;
          if (!ss.folders.contains(d)) ss.folders.add(d);
          Settings.I.save();
          Library.I.startWatching();
          Library.I.scan(s);
        }),
      ])),
      _row('Skip folders named', Field(
        controller: excluded,
        hint: 'Comma-separated, e.g. Archives',
        onSubmitted: (v) {
          ss.excluded = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          Settings.I.save();
        },
      )),
      _row('Save pages to', Row(children: [
        Flexible(child: Text(ss.saveFolder, style: ts(mono: true, size: 12), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Btn('Change…', onTap: () async {
          final d = await FilePicker.getDirectoryPath(dialogTitle: 'Where should ${s.label} pages be saved?');
          if (d == null) return;
          ss.saveFolder = d;
          Settings.I.save();
        }),
      ])),
      _row('Reading direction', Seg<ReadDirection>(
        value: ss.direction,
        items: const [(ReadDirection.ltr, 'Left to right'), (ReadDirection.rtl, 'Right to left'), (ReadDirection.ttb, 'Top to bottom')],
        onChanged: (v) {
          ss.direction = v;
          Settings.I.save();
        },
      )),
      _row('Top to bottom style', Seg<VerticalStyle>(
        value: ss.verticalStyle,
        items: const [(VerticalStyle.paged, 'Page by page'), (VerticalStyle.strip, 'Continuous strip')],
        onChanged: (v) {
          ss.verticalStyle = v;
          Settings.I.save();
        },
      )),
      _row('Pages at once', Seg<PageLayout>(
        value: ss.layout,
        items: const [(PageLayout.single, 'One'), (PageLayout.double, 'Two'), (PageLayout.auto, 'Auto (two when the window is wide)')],
        onChanged: (v) {
          ss.layout = v;
          Settings.I.save();
        },
      )),
      _row('Fit', Seg<FitMode>(
        value: ss.fit,
        items: const [(FitMode.screen, 'Screen'), (FitMode.width, 'Width'), (FitMode.height, 'Height'), (FitMode.original, 'Original')],
        onChanged: (v) {
          ss.fit = v;
          Settings.I.save();
        },
      )),
      _row('Wide pages', Seg<SplitMode>(
        value: ss.split,
        items: const [(SplitMode.off, 'Show whole'), (SplitMode.split, 'Split'), (SplitMode.singleOnly, 'Split in single-page mode')],
        onChanged: (v) {
          ss.split = v;
          Settings.I.save();
        },
      )),
      _check('Show the cover on its own in two-page mode', ss.coverOffset, (v) => ss.coverOffset = v),
      _check('Crop plain white or black borders', ss.crop, (v) => ss.crop = v),
    ];
  }

  Widget _storageRow((String, String, bool, bool) pl) {
    final size = sizes[pl.$2];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tk.line))),
      child: Row(children: [
        SizedBox(width: 280, child: Text(pl.$1, style: ts())),
        Expanded(child: Text(pl.$2, style: ts(mono: true, size: 12, c: tk.sec), overflow: TextOverflow.ellipsis)),
        SizedBox(width: 100, child: Text(size == null ? 'Working out…' : humanSize(size), style: ts(c: tk.sec, tab: true))),
        Btn.ghost('Open folder', dense: true, onTap: () {
          if (Platform.isWindows) Process.run('explorer.exe', [pl.$2]);
        }),
        if (pl.$3) Btn.ghost('Move…', dense: true, onTap: () => _move(pl.$1, pl.$2)),
        if (pl.$4)
          Btn.ghost('Clear', dense: true, onTap: () async {
            if (await confirm(context, 'Clear ${pl.$1.toLowerCase()}?',
                'This frees ${size == null ? 'some space' : humanSize(size)}. It\'s made again when needed.', confirmLabel: 'Clear')) {
              await _clear(pl.$2);
              _measure();
            }
          }),
      ]),
    );
  }

  Widget _reset(String part, String what, FutureOr<void> Function() run) {
    return Btn('Reset ${part.toLowerCase()}', kind: BtnKind.dangerGhost, onTap: () async {
      if (await confirm(context, 'Reset ${part.toLowerCase()}?', what, confirmLabel: 'Reset ${part.toLowerCase()}', danger: true)) {
        await run();
        toast('$part reset');
        _measure();
      }
    });
  }

  Future<void> _clear(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return;
    await for (final e in d.list()) {
      try {
        await e.delete(recursive: true);
      } catch (_) {}
    }
    if (dir == AppPaths.I.thumbs) Thumbs.I.forgetAll();
    Library.I.changed();
  }

  /// Copies everything with progress, checks the copy, switches, then removes the old copy.
  Future<void> _move(String what, String from) async {
    if (Jobs.I.current != null) {
      toast('Moving waits until nothing else is running', ToastKind.info);
      return;
    }
    final to = await FilePicker.getDirectoryPath(dialogTitle: 'Move $what to…');
    if (to == null) return;
    final dest = p.join(to, p.basename(from) == 'thumbs' || p.basename(from) == 'pages' ? 'Cache' : 'Shiori');
    final isData = from == AppPaths.I.data;
    final isCache = from == AppPaths.I.thumbs || from == AppPaths.I.pageCache;
    final src = isCache ? AppPaths.I.cache : from;
    Jobs.I.add(Job('Moving $what', (job) async {
      final files = await Directory(src).list(recursive: true).where((e) => e is File).cast<File>().toList();
      final total = await Future.wait(files.map((f) => f.length())).then((l) => l.fold<int>(0, (a, b) => a + b));
      job.unit = 'bytes';
      job.progress(0, total: total, detail: 'Copying to $dest');
      var done = 0;
      for (final f in files) {
        if (!await job.checkpoint()) return null;
        final rel = p.relative(f.path, from: src);
        final out = File(p.join(dest, rel));
        await out.parent.create(recursive: true);
        await f.copy(out.path);
        done += await f.length();
        job.progress(done, detail: '${humanSize(done)} of ${humanSize(total)}');
      }
      job.setDetail('Checking the copy');
      for (final f in files) {
        final out = File(p.join(dest, p.relative(f.path, from: src)));
        if (!await out.exists() || await out.length() != await f.length()) {
          throw Exception('The copy of ${p.basename(f.path)} doesn\'t match, so nothing was switched.');
        }
      }
      if (isCache) {
        writeStringSafelySync(p.join(AppPaths.I.data, 'cache_location.json'), jsonEncode({'cache': dest}));
        final old = AppPaths.I.cache;
        AppPaths.I.cache = dest;
        AppPaths.I.ensureCache();
        try {
          await Directory(old).delete(recursive: true);
        } catch (_) {}
        Thumbs.I.version++;
        return '$what moved to $dest';
      }
      if (isData) {
        final base = Platform.environment['LOCALAPPDATA'] ?? from;
        writeStringSafelySync(AppPaths.pointerFileFor(p.join(base, 'Shiori')), jsonEncode({'data': dest, 'old': from}));
        AppLog.I.info('Data copied to $dest. It switches over next time Shiori starts.');
        return '$what copied. Restart Shiori to finish the move.';
      }
      return null;
    }, canPause: true));
    setState(() {});
  }
}
