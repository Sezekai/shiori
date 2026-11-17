import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/archives.dart';
import '../core/db.dart';
import '../core/log.dart';
import 'pc.dart';
import 'store.dart';

/// A file read from the PC. All its pages start loading in the background
/// straight away, nearest to the current page first, into a small cache so
/// the last few files reopen instantly.
class RemoteBook extends Book {
  RemoteBook._(this.t, this._names, this.dir, this.maxWidth);

  final Title t;
  final List<String> _names;
  final String dir;
  final int maxWidth;
  final Map<int, Completer<Uint8List>> _wanted = {};
  final Set<int> _have = {};
  final Set<int> _busy = {};
  final ValueNotifier<int> loaded = ValueNotifier(0);
  int focus = 0;
  bool _closed = false;
  int _workers = 0;
  String? error;

  @override
  List<String> get pageNames => _names;

  static const keepFiles = 6;

  static Future<RemoteBook> open(Title t, {int maxWidth = 2400}) async {
    final dir = p.join(Store.I.streamCache, t.uid);
    Directory(dir).createSync(recursive: true);
    List<String> names;
    final list = File(p.join(dir, 'pages.txt'));
    try {
      names = ((await Pc.I.getJson('/api/pages/${t.id}', timeout: const Duration(seconds: 60)))['names'] as List).cast<String>();
      await list.writeAsString(names.join('\n'));
    } catch (e) {
      // Offline, but this file was read recently: use what's cached.
      if (!list.existsSync()) rethrow;
      names = (await list.readAsString()).split('\n');
    }
    final b = RemoteBook._(t, names, dir, maxWidth);
    for (var i = 0; i < names.length; i++) {
      if (File(b._file(i)).existsSync()) b._have.add(i);
    }
    b.loaded.value = b._have.length;
    _trim(t.uid);
    // Touch the folder so it counts as recently used.
    try {
      File(p.join(dir, 'used')).writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {}
    return b;
  }

  static void _trim(String keep) {
    try {
      final dirs = Directory(Store.I.streamCache).listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final d in dirs.skip(keepFiles)) {
        if (p.basename(d.path) != keep) d.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  String _file(int i) => p.join(dir, '$i${p.extension(_names[i]).toLowerCase()}');

  bool has(int i) => _have.contains(i);

  /// Starts loading every page, nearest to [from] first.
  void preloadAll(int from) {
    focus = from;
    while (_workers < 3) {
      _workers++;
      _work();
    }
  }

  Future<void> _work() async {
    try {
      while (!_closed) {
        final i = _nextIndex();
        if (i == null) break;
        await _fetch(i);
      }
    } finally {
      _workers--;
    }
  }

  /// The nearest page not loaded yet, looking ahead before looking back.
  int? _nextIndex() {
    for (var d = 0; d < _names.length; d++) {
      for (final i in [focus + d, focus - d]) {
        if (i < 0 || i >= _names.length) continue;
        if (!_have.contains(i) && !_busy.contains(i)) return i;
      }
    }
    return null;
  }

  Future<void> _fetch(int i) async {
    if (_busy.contains(i) || _have.contains(i)) return;
    _busy.add(i);
    try {
      final bytes = await Pc.I.getBytes('/api/page/${t.id}/$i?w=$maxWidth');
      await File(_file(i)).writeAsBytes(bytes, flush: false);
      _have.add(i);
      loaded.value = _have.length;
      _wanted.remove(i)?.complete(bytes);
    } catch (e) {
      error = '$e';
      final w = _wanted.remove(i);
      if (w != null && !w.isCompleted) w.completeError(e);
      if (!Pc.I.online) {
        _closed = true; // stop trying until the reader is opened again
        AppLog.I.warn('Stopped loading ${t.displayTitle}: $e');
      }
    } finally {
      _busy.remove(i);
    }
  }

  @override
  Future<Uint8List> page(int i) async {
    if (_have.contains(i)) return File(_file(i)).readAsBytes();
    final c = _wanted.putIfAbsent(i, () => Completer<Uint8List>());
    if (!_busy.contains(i)) {
      if (_closed) {
        _wanted.remove(i);
        throw PcError('This page isn\'t on the phone and the PC can\'t be reached.');
      }
      unawaited(_fetch(i));
    }
    return c.future;
  }

  @override
  void close() {
    _closed = true;
    for (final c in _wanted.values) {
      if (!c.isCompleted) c.completeError(StateError('closed'));
    }
    _wanted.clear();
  }
}
