// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'core/archives.dart';
import 'core/db.dart';
import 'core/jobs.dart';
import 'core/library.dart';
import 'core/log.dart';
import 'core/paths.dart';
import 'core/settings.dart';
import 'ui/app.dart';
import 'ui/library_page.dart';
import 'ui/look.dart';
import 'ui/reader.dart';

const appVersion = String.fromEnvironment('SHIORI_VERSION', defaultValue: 'dev');
const _instancePort = 47613;
final GlobalKey _shotKey = GlobalKey();

Future<void> main(List<String> args) async {
  final selftest = args.contains('--selftest') || Platform.environment['SHIORI_SELFTEST'] == '1';
  WidgetsFlutterBinding.ensureInitialized();

  // One window only: a second launch brings the first one forward.
  ServerSocket? instance;
  if (!selftest && (Platform.isWindows || Platform.isLinux)) {
    try {
      instance = await ServerSocket.bind(InternetAddress.loopbackIPv4, _instancePort);
    } catch (_) {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, _instancePort, timeout: const Duration(seconds: 2));
        s.write('show');
        await s.flush();
        await s.close();
      } catch (_) {}
      exit(0);
    }
  }

  AppPaths.I = AppPaths.resolve();
  AppLog.I.init(AppPaths.I.logs);
  AppLog.I.info('Shiori $appVersion starting. Data: ${AppPaths.I.data} · Cache: ${AppPaths.I.cache}');
  _finishDataMove();

  FlutterError.onError = (d) {
    AppLog.I.error('Interface error', d.exception, d.stack);
    AppLog.I.writeCrash('drawing the interface', d.exception, d.stack);
  };
  ui.PlatformDispatcher.instance.onError = (e, st) {
    AppLog.I.error('Unexpected error', e, st);
    AppLog.I.writeCrash('running', e, st);
    return true;
  };

  Settings.I.load();
  Look.I.load();
  if (selftest) _prepareSelftest();

  // Safe mode after two unclean exits in a row.
  final marker = File(p.join(AppPaths.I.data, 'running.marker'));
  var unclean = 0;
  if (marker.existsSync()) {
    unclean = (int.tryParse(marker.readAsStringSync().trim()) ?? 0) + 1;
  }
  marker.writeAsStringSync('$unclean');
  final safeMode = unclean >= 2;
  if (unclean >= 1) _reportLastCrash();
  if (safeMode) {
    AppLog.I.warn('Shiori didn\'t close properly twice in a row, so folder watching and cover making are off for this run.');
  }

  Db.I = Db.open(AppPaths.I.db);
  Db.I.backup(AppPaths.I.backups);
  if (!AppPaths.I.ensureCache()) {
    AppLog.I.warn('The cache folder ${AppPaths.I.cache} can\'t be reached. Is its drive connected? Covers won\'t be saved until it is.');
  }
  Library.I.load();
  Thumbs.I.encoder = makeCover;
  await Thumbs.I.loadIndex().timeout(const Duration(seconds: 15), onTimeout: () {});

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    final ws = Settings.I.windowState;
    final opts = WindowOptions(
      size: Size((ws['w'] as num?)?.toDouble() ?? 1440, (ws['h'] as num?)?.toDouble() ?? 900),
      minimumSize: const Size(1100, 680),
      center: ws['x'] == null,
      title: 'Shiori',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Look.I.t.ground,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      if (ws['x'] != null) {
        await windowManager.setPosition(Offset((ws['x'] as num).toDouble(), (ws['y'] as num).toDouble()));
      }
      if (ws['max'] == true) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(_WindowKeeper(marker));
    await windowManager.setPreventClose(true);
  }

  instance?.listen((s) {
    s.listen((_) async {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    });
  });

  runApp(RepaintBoundary(key: _shotKey, child: const ShioriApp()));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (selftest) {
      await _runSelftest();
      return;
    }
    if (safeMode) Settings.I.watchFolders = false;
    // A quick rescan picks up anything added while Shiori was closed;
    // unchanged files are skipped, so this is fast.
    for (final s in Section.values) {
      if (Settings.I.of(s).folders.isNotEmpty) Library.I.scan(s);
    }
    Library.I.startWatching();
    // A heartbeat in the log file: memory and what's running, every 30 seconds.
    Timer.periodic(const Duration(seconds: 30), (_) {
      final j = Jobs.I.current;
      AppLog.I.fileOnly('Heartbeat · memory ${ProcessInfo.currentRss ~/ (1024 * 1024)} MB'
          '${j == null ? ' · idle' : ' · ${j.name} ${j.done}/${j.total ?? '?'}'}');
    });
    unawaited(trimPageCache(AppPaths.I.pageCache, 2 * 1024 * 1024 * 1024));
  });
}

class _WindowKeeper with WindowListener {
  _WindowKeeper(this.marker);
  final File marker;
  Timer? _save;

  void _remember() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () async {
      final max = await windowManager.isMaximized();
      final ws = Settings.I.windowState;
      ws['max'] = max;
      if (!max && !await windowManager.isFullScreen()) {
        final b = await windowManager.getBounds();
        ws['x'] = b.left;
        ws['y'] = b.top;
        ws['w'] = b.width;
        ws['h'] = b.height;
      }
      Settings.I.save();
    });
  }

  @override
  void onWindowResized() => _remember();
  @override
  void onWindowMoved() => _remember();
  @override
  void onWindowMaximize() => _remember();
  @override
  void onWindowUnmaximize() => _remember();

  @override
  void onWindowClose() async {
    Jobs.I.stop();
    try {
      Db.I.close();
    } catch (_) {}
    try {
      marker.deleteSync();
    } catch (_) {}
    await AppLog.I.flush();
    await windowManager.destroy();
  }
}

/// Makes a cover thumbnail in a background isolate, so the window never
/// waits on it: decoded, scaled to 360 px wide and saved as JPG.
Future<Uint8List?> makeCover(Uint8List bytes) => Isolate.run(() {
      final im = img.decodeImage(bytes);
      if (im == null) return null;
      final small = im.width > 360 ? img.copyResize(im, width: 360, interpolation: img.Interpolation.average) : im;
      return img.encodeJpg(small, quality: 85);
    });

/// The last run ended without closing properly: put the end of its log and
/// Windows' crash record for Shiori.exe into this run's log.
void _reportLastCrash() {
  AppLog.I.warn('The last run of Shiori didn\'t close properly. Details follow in this log.');
  try {
    final prev = AppLog.I.previousFile;
    if (prev != null) {
      final lines = File(prev).readAsLinesSync();
      AppLog.I.fileOnly('--- last lines of the previous run (${p.basename(prev)}) ---');
      for (final l in lines.skip(lines.length > 40 ? lines.length - 40 : 0)) {
        AppLog.I.fileOnly('  $l');
      }
    }
  } catch (_) {}
  if (!Platform.isWindows) return;
  try {
    final r = Process.runSync('wevtutil', [
      'qe', 'Application', '/c:6', '/rd:true', '/f:text',
      '/q:*[System[(Provider[@Name="Application Error"] or Provider[@Name="Windows Error Reporting"] or Provider[@Name=".NET Runtime"]) and TimeCreated[timediff(@SystemTime) <= 172800000]]]',
    ]);
    final text = (r.stdout as String);
    final events = text.split(RegExp(r'Event\[\d+\]')).where((e) => e.toLowerCase().contains('shiori')).toList();
    if (events.isEmpty) {
      AppLog.I.fileOnly('Windows has no crash record for Shiori.exe from the last two days.');
    } else {
      AppLog.I.fileOnly('--- Windows crash record ---');
      for (final l in events.first.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).take(40)) {
        AppLog.I.fileOnly('  ${l.trimRight()}');
      }
      final fault = RegExp(r'Faulting module name: ([^,\r\n]+)|Exception code: (0x[0-9a-fA-F]+)').allMatches(events.first)
          .map((m) => m.group(0)).join(' · ');
      if (fault.isNotEmpty) AppLog.I.warn('Windows says: $fault');
    }
  } catch (e) {
    AppLog.I.fileOnly('Couldn\'t read Windows\' crash record: $e');
  }
}

/// After "Move…" of the data folder: the new place is in use, so the old copy goes.
void _finishDataMove() {
  try {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null) return;
    final pointer = File(AppPaths.pointerFileFor(p.join(base, 'Shiori')));
    if (!pointer.existsSync()) return;
    final m = jsonDecode(pointer.readAsStringSync()) as Map;
    final old = m['old'] as String?;
    if (old == null || old == AppPaths.I.data) return;
    if (!File(p.join(AppPaths.I.data, 'library.db')).existsSync()) return;
    for (final name in ['library.db', 'library.db-wal', 'library.db-shm', 'settings.json', 'appearance.json']) {
      final f = File(p.join(old, name));
      if (f.existsSync()) f.deleteSync();
    }
    for (final d in ['logs', 'backups']) {
      final dir = Directory(p.join(old, d));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    m.remove('old');
    pointer.writeAsStringSync(jsonEncode(m));
    AppLog.I.info('Finished moving the data folder to ${AppPaths.I.data}');
  } catch (e) {
    AppLog.I.warn('Couldn\'t tidy up after moving the data folder: $e');
  }
}

// ---------------- self-test (CI) ----------------

String get _selftestBooks => p.join(AppPaths.I.root, 'selftest-books');

void _prepareSelftest() {
  final dir = Directory(_selftestBooks)..createSync(recursive: true);
  for (final s in Section.values) {
    Settings.I.of(s).folders = s == Section.manga ? [dir.path] : [];
  }
  for (var b = 1; b <= 3; b++) {
    final arc = Archive();
    for (var i = 1; i <= 6; i++) {
      final wide = i == 4;
      final im = img.Image(width: wide ? 1200 : 600, height: 850);
      img.fill(im, color: img.ColorRgb8(30 * b + 20 * i, 90, 160));
      img.drawRect(im, x1: 0, y1: 0, x2: im.width - 1, y2: im.height - 1, color: img.ColorRgb8(255, 255, 255), thickness: 8);
      final bytes = img.encodeJpg(im, quality: 80);
      arc.addFile(ArchiveFile.bytes('page_${i.toString().padLeft(3, '0')}.jpg', bytes));
    }
    final zip = ZipEncoder().encodeBytes(arc);
    File(p.join(dir.path, '[Test Artist] Selftest Story Ch. $b [English] [_12345${b}_].cbz')).writeAsBytesSync(zip);
  }
  AppLog.I.info('Self-test: made 3 sample books in ${dir.path}');
}

Future<void> _runSelftest() async {
  var ok = true;
  final out = StringBuffer();
  void check(bool c, String what) {
    out.writeln('${c ? 'OK  ' : 'FAIL'} $what');
    if (!c) ok = false;
  }

  try {
    Nav.I.go(PageId.library, Section.manga);
    Library.I.scan(Section.manga);
    final until = DateTime.now().add(const Duration(seconds: 90));
    while ((Jobs.I.current != null || Jobs.I.queue.isNotEmpty) && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final titles = Library.I.titles(Section.manga);
    check(titles.length == 3, 'scan found 3 books (found ${titles.length})');
    check(titles.every((t) => t.pages == 6), 'every book has 6 pages');
    check(titles.every((t) => t.artist == 'Test Artist'), 'artist read from the file name');
    final groups = Library.I.seriesGroups(Section.manga);
    check(groups.length == 1 && groups.values.first.length == 3, 'chapters grouped into one series');
    final covers = titles.where((t) => Thumbs.I.cached(t) != null).length;
    check(covers == 3, 'covers made ($covers of 3)');
    await Future<void>.delayed(const Duration(seconds: 1));
    await _screenshot('library');
    LibraryPageState.active?.selectFirst();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _screenshot('library-panel');
    final ctx = navKey.currentContext;
    if (ctx != null && titles.isNotEmpty) {
      final first = Library.I.seriesGroups(Section.manga).values.first.first;
      unawaited(openReader(ctx, first, context_: Library.I.seriesGroups(Section.manga).values.first));
      await Future<void>.delayed(const Duration(seconds: 3));
      await _screenshot('reader');
      final r = ReaderControl.active;
      check(r != null, 'reader opened');
      if (r != null) {
        AppLog.I.info('Self-test: reader layout ${r.layout}');
        // 6 pages, page 4 wide: cover alone, 2+3 paired, 4 alone, 5+6 paired.
        check(r.layout.length == 4, 'two-page layout with cover offset and a wide page (${r.layout})');
        r.next();
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _screenshot('reader-spread');
        Settings.I.saveFormat = SaveFormat.jpg;
        Settings.I.of(Section.manga).saveFolder = p.join(AppPaths.I.root, 'saved');
        await r.saveCurrent(both: true);
        await r.saveCurrent(both: true); // must be skipped as already saved
        final saved = Directory(p.join(AppPaths.I.root, 'saved')).listSync().length;
        check(saved == 1, 'combined page saved once, not twice ($saved file)');
        for (var i = 0; i < 4; i++) {
          r.next();
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        await _screenshot('reader-end');
        check(first.readCount == 1, 'finishing the file records a completion (${first.readCount})');
      }
      navKey.currentState?.pop();
      await Future<void>.delayed(const Duration(seconds: 1));
      check(Db.I.sessions(titleId: first.id).isNotEmpty, 'reading session recorded');
    }
    for (final (page, name) in [
      (PageId.history, 'history'),
      (PageId.stats, 'stats'),
      (PageId.settings, 'settings'),
      (PageId.look, 'appearance'),
      (PageId.saved, 'saved'),
    ]) {
      Nav.I.go(page);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _screenshot(name);
    }
    Nav.I.go(PageId.library);
    Nav.I.toggle('keys');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _screenshot('keys');
    Nav.I.toggle('keys');
    check(AppLog.I.errorCount == 0, 'no errors logged (${AppLog.I.errorCount})');
  } catch (e, st) {
    ok = false;
    out.writeln('FAIL exception: $e\n$st');
  }
  final report = 'SELFTEST ${ok ? 'PASSED' : 'FAILED'}\n$out\n--- log ---\n${AppLog.I.lines.join('\n')}';
  File(p.join(AppPaths.I.logs, 'selftest.txt')).writeAsStringSync(report);
  stdout.writeln(report);
  await AppLog.I.flush();
  try {
    File(p.join(AppPaths.I.data, 'running.marker')).deleteSync();
  } catch (_) {}
  exit(ok ? 0 : 1);
}

Future<void> _screenshot(String name) async {
  try {
    final ro = _shotKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    final im = await ro.toImage(pixelRatio: 1);
    final png = await im.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final path = p.join(AppPaths.I.logs, 'selftest-$name.png');
    File(path).writeAsBytesSync(png.buffer.asUint8List());
    AppLog.I.info('Self-test screenshot: $path (${im.width}×${im.height})');
  } catch (e) {
    AppLog.I.warn('Self-test screenshot failed: $e');
  }
}
