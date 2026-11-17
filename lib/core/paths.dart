import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Where Shiori keeps things (STANDARDS.md section 3).
///
/// - Root (large things): the folder above `App` when the program sits in a
///   folder called `App`, otherwise the program's own folder.
/// - Data (small things): `%LOCALAPPDATA%\Shiori`, unless a pointer file there
///   says it was moved.
/// - `SHIORI_ROOT` and `SHIORI_DATA` override both, for tests and CI.
class AppPaths {
  AppPaths._(this.root, this.data, this.cache);

  final String root;
  final String data;
  String cache;

  static late AppPaths I;

  String get db => p.join(data, 'library.db');
  String get settingsFile => p.join(data, 'settings.json');
  String get appearanceFile => p.join(data, 'appearance.json');
  String get logs => p.join(data, 'logs');
  String get backups => p.join(data, 'backups');
  String get thumbs => p.join(cache, 'thumbs');
  String get pageCache => p.join(cache, 'pages');

  /// The phone: everything inside the app's own storage.
  static AppPaths at({required String data, required String cache}) {
    final paths = AppPaths._(data, data, cache);
    for (final d in [data, paths.logs, paths.backups, cache, paths.thumbs, paths.pageCache]) {
      try {
        Directory(d).createSync(recursive: true);
      } catch (_) {}
    }
    return paths;
  }

  static String pointerFileFor(String defaultData) =>
      p.join(defaultData, 'location.json');

  static AppPaths resolve() {
    final env = Platform.environment;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    String root;
    if (env['SHIORI_ROOT'] != null && env['SHIORI_ROOT']!.isNotEmpty) {
      root = env['SHIORI_ROOT']!;
    } else if (p.basename(exeDir).toLowerCase() == 'app') {
      root = p.dirname(exeDir);
    } else if (Platform.resolvedExecutable.contains('flutter_tester') ||
        exeDir.contains('${p.separator}build${p.separator}')) {
      root = p.join(Directory.current.path, 'dev-root');
    } else {
      root = exeDir;
    }

    String data;
    if (env['SHIORI_DATA'] != null && env['SHIORI_DATA']!.isNotEmpty) {
      data = env['SHIORI_DATA']!;
    } else {
      final base = env['LOCALAPPDATA'] ??
          p.join(env['HOME'] ?? Directory.current.path, '.local', 'share');
      final defaultData = p.join(base, 'Shiori');
      data = defaultData;
      final pointer = File(pointerFileFor(defaultData));
      if (pointer.existsSync()) {
        try {
          final m = jsonDecode(pointer.readAsStringSync()) as Map;
          if (m['data'] is String && (m['data'] as String).isNotEmpty) {
            data = m['data'] as String;
          }
        } catch (_) {}
      }
    }

    var cache = p.join(root, 'Cache');
    final cachePointer = File(p.join(data, 'cache_location.json'));
    if (cachePointer.existsSync()) {
      try {
        final m = jsonDecode(cachePointer.readAsStringSync()) as Map;
        if (m['cache'] is String) cache = m['cache'] as String;
      } catch (_) {}
    }

    final paths = AppPaths._(root, data, cache);
    for (final d in [data, paths.logs, paths.backups]) {
      try {
        Directory(d).createSync(recursive: true);
      } catch (_) {}
    }
    return paths;
  }

  /// Creates cache folders. Returns false when the cache drive is missing,
  /// so the caller can say so instead of quietly creating it elsewhere.
  bool ensureCache() {
    final driveRoot = p.rootPrefix(cache);
    if (driveRoot.isNotEmpty && !Directory(driveRoot).existsSync()) {
      return false;
    }
    try {
      Directory(thumbs).createSync(recursive: true);
      Directory(pageCache).createSync(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Writes a file safely: a temporary file first, then a rename over the old
/// one, so a crash never leaves a half-written file.
Future<void> writeFileSafely(String path, List<int> bytes) async {
  final tmp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  await tmp.parent.create(recursive: true);
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(path);
}

void writeStringSafelySync(String path, String text) {
  final tmp = File('$path.tmp');
  tmp.parent.createSync(recursive: true);
  tmp.writeAsStringSync(text, flush: true);
  tmp.renameSync(path);
}

/// A file name that doesn't overwrite anything: adds " (2)", " (3)"…
String uniquePath(String path) {
  if (!File(path).existsSync()) return path;
  final dir = p.dirname(path);
  final base = p.basenameWithoutExtension(path);
  final ext = p.extension(path);
  for (var i = 2;; i++) {
    final candidate = p.join(dir, '$base ($i)$ext');
    if (!File(candidate).existsSync()) return candidate;
  }
}

String safeFileName(String s) {
  var out = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (out.length > 150) out = out.substring(0, 150).trim();
  return out.isEmpty ? 'page' : out;
}
