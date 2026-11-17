import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import 'm_library.dart';
import 'm_more.dart';
import 'm_reader.dart';
import 'mobile_app.dart';
import 'pc.dart';
import 'store.dart';

final GlobalKey mShotKey = GlobalKey();

/// Drives the phone app against a running PC self-test (Linux, phone-sized
/// window): pair, sync, browse, read, save, download.
Future<void> mobileSelftest() async {
  final out = StringBuffer();
  var ok = true;
  void check(bool c, String what) {
    out.writeln('${c ? 'OK  ' : 'FAIL'} $what');
    if (!c) ok = false;
  }

  Future<void> idle() async {
    for (var i = 0; i < 300 && (Jobs.I.current != null || Jobs.I.queue.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> wait([int ms = 900]) => Future<void>.delayed(Duration(milliseconds: ms));
  NavigatorState nav() => mNavKey.currentState!;

  try {
    await wait(1500);
    final pcFile = Platform.environment['SHIORI_PC_FILE']!;
    final m = jsonDecode(File(pcFile).readAsStringSync()) as Map;
    // Instead of typing the code: the PC test already paired and wrote the token.
    Settings.I.extra
      ..['pc.host'] = '127.0.0.1'
      ..['pc.port'] = m['port']
      ..['pc.token'] = m['token']
      ..['pc.name'] = 'Test PC';
    Settings.I.save();
    await shot('first-run');
    if (nav().canPop()) nav().pop();
    final found = await Pc.I.discover();
    check(found.isNotEmpty, 'found the PC on the network (${found.map((f) => f.host).join(', ')})');
    check(await Pc.I.check(), 'connected to the PC');
    await wait(300);
    await idle();
    final titles = Section.values.expand(Library.I.titles).toList();
    check(titles.length == 3, 'library synced from the PC (${titles.length} titles)');
    check(Thumbs.I.names.length >= 3, 'covers came over (${Thumbs.I.names.length})');
    Settings.I.put('m.section', Section.manga.name);
    await wait();
    await shot('library');

    final group = Library.I.entries(Section.manga).first;
    unawaited(nav().push(MaterialPageRoute(builder: (_) => MTitleScreen(entry: group))));
    await wait();
    await shot('title');

    final t = group.titles.first;
    final ctx = mNavKey.currentContext!;
    unawaited(openMobileReader(ctx, t, group.titles, page: 0));
    await wait(2500);
    await shot('reader');
    final st = mNavKey.currentContext!;
    // Turn a few pages by tapping the left edge (manga reads right to left).
    final size = MediaQuery.of(st).size;
    for (var i = 0; i < 4; i++) {
      await tapAt(Offset(size.width * 0.08, size.height / 2));
      await wait(250);
    }
    await shot('reader-later');
    await tapAt(Offset(size.width / 2, size.height / 2));
    await wait(400);
    await shot('reader-controls');
    nav().pop(); // reader
    await wait(800);
    final ses = Db.I.sessions(titleId: t.id).where((s) => s.device == 'Phone').toList();
    check(ses.isNotEmpty && ses.first.pagesSeen >= 4, 'reading session recorded on the phone (${ses.firstOrNull?.pagesSeen} pages turned by tapping)');
    check(Library.I.byId(t.id)!.readCount >= 1, 'finished chapter counted');

    final r1 = await Store.I.savePage(t, [(1, 0)]);
    check(r1?['result'] == 'saved', 'saved a page on the PC (${r1?['file']})');
    final r2 = await Store.I.savePage(t, [(1, 0)]);
    check(r2?['result'] == 'duplicate', 'saving it again is caught as a duplicate');
    final r3 = await Store.I.savePage(t, [(1, 0)], force: true);
    check(r3?['result'] == 'saved' && r3?['file'] != r1?['file'], 'save anyway makes a new file (${r3?['file']})');

    Store.I.download([t]);
    await wait(300);
    await shot('downloading');
    await idle();
    check(Store.I.isDownloaded(t), 'downloaded ${t.displayTitle}');
    nav().pop(); // title
    await wait();

    // Offline: read the download.
    Pc.I.pretendOffline = true;
    await Pc.I.check();
    check(!Pc.I.online, 'shows offline when the PC is gone');
    unawaited(openMobileReader(mNavKey.currentContext!, t, group.titles, page: 2));
    await wait(1500);
    await shot('reader-offline');
    nav().pop();
    await wait(500);
    final s2 = await Store.I.savePage(t, [(3, 0)]);
    check(s2 == null && Store.I.saveQueue.length == 1, 'offline save waits in the queue');
    Pc.I.pretendOffline = false;
    await Pc.I.check();
    await idle();
    check(Store.I.saveQueue.isEmpty, 'queued save went to the PC on reconnect');
    check(Store.I.waiting == 0, 'all reading sent to the PC');

    for (final (i, name) in [(1, 'history'), (2, 'stats'), (3, 'more')]) {
      MobileShell.tab.value = i;
      await wait();
      await shot(name);
    }
    unawaited(nav().push(MaterialPageRoute(builder: (_) => const DownloadsScreen())));
    await wait();
    await shot('downloads');
    nav().pop();
    unawaited(nav().push(MaterialPageRoute(builder: (_) => const MSettingsScreen())));
    await wait();
    await shot('settings');
    nav().pop();
    unawaited(nav().push(MaterialPageRoute(builder: (_) => const ConnectScreen())));
    await wait();
    await shot('connect');
    nav().pop();
    check(AppLog.I.errorCount == 0, 'no errors logged (${AppLog.I.errorCount})');
  } catch (e, st) {
    ok = false;
    out.writeln('FAIL exception: $e\n$st');
  }
  final report = 'PHONE SELFTEST ${ok ? 'PASSED' : 'FAILED'}\n$out\n--- log ---\n${AppLog.I.lines.join('\n')}';
  File(p.join(AppPaths.I.logs, 'selftest.txt')).writeAsStringSync(report);
  stdout.writeln(report);
  final done = Platform.environment['SHIORI_PC_FILE'];
  if (done != null) File('$done.done').writeAsStringSync('1');
  await AppLog.I.flush();
  exit(ok ? 0 : 1);
}

Future<void> tapAt(Offset at) async {
  final b = WidgetsBinding.instance;
  b.handlePointerEvent(PointerDownEvent(position: at, pointer: 99));
  await Future<void>.delayed(const Duration(milliseconds: 40));
  b.handlePointerEvent(PointerUpEvent(position: at, pointer: 99));
  // Wait out the double-tap window so it counts as a single tap.
  await Future<void>.delayed(const Duration(milliseconds: 320));
}

Future<void> shot(String name) async {
  try {
    final ro = mShotKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    final im = await ro.toImage(pixelRatio: 1);
    final png = await im.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final path = p.join(AppPaths.I.logs, 'phone-$name.png');
    File(path).writeAsBytesSync(png.buffer.asUint8List());
    AppLog.I.info('Phone screenshot: $path');
  } catch (e) {
    AppLog.I.warn('Screenshot failed: $e');
  }
}
