import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The app log (STANDARDS.md "The log"): kept in memory for the drawer and
/// written to `logs\` on disk, keeping the last few runs.
class AppLog extends ChangeNotifier {
  AppLog._();
  static final AppLog I = AppLog._();

  final List<String> lines = [];
  RandomAccessFile? _file;
  String? currentFile;
  String? previousFile;
  String? logDir;

  /// Set when an error is logged, so the shell can open the drawer.
  int errorCount = 0;

  void init(String dir) {
    logDir = dir;
    try {
      final d = Directory(dir)..createSync(recursive: true);
      final old = d
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('run-'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      previousFile = old.isEmpty ? null : old.first.path;
      for (final f in old.skip(5)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      currentFile = p.join(dir, 'run-$stamp.txt');
      _file = File(currentFile!).openSync(mode: FileMode.append);
    } catch (_) {}
  }

  void info(String msg) => _add('INFO', msg);
  void warn(String msg) => _add('WARN', msg);
  void error(String msg, [Object? e, StackTrace? st]) {
    errorCount++;
    _add('ERROR', e == null ? msg : '$msg: $e');
    if (st != null) _write(st.toString());
  }

  void _add(String level, String msg) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $level  $msg';
    lines.add(line);
    if (lines.length > 3000) lines.removeRange(0, lines.length - 3000);
    _write(line);
    if (kDebugMode) stderr.writeln(line);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  void writeCrash(String what, Object error, StackTrace? st) {
    if (logDir == null) return;
    try {
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      File(p.join(logDir!, 'crash-$stamp.txt')).writeAsStringSync(
          'What was happening: $what\n\n$error\n\n${st ?? ''}');
    } catch (_) {}
  }

  /// Written straight to the file (no buffering), so the last lines survive a crash.
  void _write(String text) {
    try {
      _file?.writeStringSync('$text\n');
    } catch (_) {}
  }

  /// Only to the file: detail that would clutter the drawer.
  void fileOnly(String msg) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _write('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  INFO  $msg');
  }

  Future<void> flush() async {
    try {
      _file?.flushSync();
    } catch (_) {}
  }
}
