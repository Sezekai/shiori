import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'parse.dart';

const imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif', '.jxl', '.jp2'};

bool isPageName(String name) {
  final n = name.replaceAll('\\', '/');
  if (n.startsWith('__MACOSX/') || n.contains('/__MACOSX/')) return false;
  final base = p.posix.basename(n);
  if (base.startsWith('.')) return false;
  return imageExts.contains(p.posix.extension(base).toLowerCase());
}

List<String> sortPages(Iterable<String> names) =>
    names.where(isPageName).toList()..sort(naturalCompare);

/// What the scanner learns about one file. Runs in a background isolate.
class FileInfo {
  final String path;
  final int size;
  final int mtime;
  final String fingerprint;
  final String kind;
  final int pages;
  final String? error;
  FileInfo(this.path, this.size, this.mtime, this.fingerprint, this.kind, this.pages, [this.error]);
}

/// Size plus a hash of the first and last 64 KB: cheap, and it survives moves
/// and renames, so history follows the file.
String fingerprintOf(RandomAccessFile f, int size) {
  const chunk = 65536;
  final b = BytesBuilder(copy: false);
  b.add(utf8.encode('$size|'));
  f.setPositionSync(0);
  b.add(f.readSync(size < chunk ? size : chunk));
  if (size > chunk * 2) {
    f.setPositionSync(size - chunk);
    b.add(f.readSync(chunk));
  }
  return sha1.convert(b.takeBytes()).toString();
}

String detectKind(RandomAccessFile f) {
  f.setPositionSync(0);
  final head = f.readSync(8);
  if (head.length >= 2 && head[0] == 0x50 && head[1] == 0x4b) return 'zip';
  if (head.length >= 4 && head[0] == 0x52 && head[1] == 0x61 && head[2] == 0x72 && head[3] == 0x21) {
    return 'rar';
  }
  if (head.length >= 2 && head[0] == 0x37 && head[1] == 0x7a) return 'rar'; // 7z, also via 7-Zip
  return 'zip';
}

FileInfo inspectFile(String path, String? sevenZip) {
  final file = File(path);
  try {
    final st = file.statSync();
    final raf = file.openSync();
    String fp;
    String kind;
    try {
      fp = fingerprintOf(raf, st.size);
      kind = detectKind(raf);
    } finally {
      raf.closeSync();
    }
    var pages = 0;
    if (kind == 'zip') {
      final input = InputFileStream(path);
      try {
        final arc = ZipDecoder().decodeStream(input);
        pages = arc.files.where((f) => f.isFile && isPageName(f.name)).length;
      } finally {
        input.closeSync();
      }
    } else {
      if (sevenZip == null) {
        return FileInfo(path, st.size, st.modified.millisecondsSinceEpoch ~/ 1000, fp, kind, 0,
            '7-Zip is missing, so RAR files can\'t be opened');
      }
      pages = listWith7z(sevenZip, path).length;
    }
    return FileInfo(path, st.size, st.modified.millisecondsSinceEpoch ~/ 1000, fp, kind, pages);
  } catch (e) {
    int size = 0, mtime = 0;
    try {
      final st = file.statSync();
      size = st.size;
      mtime = st.modified.millisecondsSinceEpoch ~/ 1000;
    } catch (_) {}
    return FileInfo(path, size, mtime, 'err:$path', 'zip', 0, '$e');
  }
}

/// Finds 7-Zip: bundled in `tools\` beside the program, else an installed copy.
String? findSevenZip() {
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final candidates = <String>[
    p.join(exeDir, 'tools', '7z.exe'),
    p.join(exeDir, 'tools', '7zz'),
    r'C:\Program Files\7-Zip\7z.exe',
    r'C:\Program Files (x86)\7-Zip\7z.exe',
    '/usr/bin/7z',
    '/usr/bin/7zz',
    '/usr/local/bin/7zz',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

List<String> listWith7z(String sevenZip, String archive) {
  final r = Process.runSync(sevenZip, ['l', '-slt', '-ba', '-sccUTF-8', archive],
      stdoutEncoding: utf8, stderrEncoding: utf8);
  if (r.exitCode != 0) {
    throw Exception('7-Zip couldn\'t read the file (${(r.stderr as String).trim()})');
  }
  final names = <String>[];
  String? current;
  var isDir = false;
  for (final line in const LineSplitter().convert(r.stdout as String)) {
    if (line.startsWith('Path = ')) {
      if (current != null && !isDir) names.add(current);
      current = line.substring(7);
      isDir = false;
    } else if (line.startsWith('Folder = +') || (line.startsWith('Attributes = ') && line.contains('D'))) {
      isDir = true;
    }
  }
  if (current != null && !isDir) names.add(current);
  return sortPages(names);
}

/// Pages of one open book. CBZ pages are read straight from the zip; CBR
/// pages are unpacked to the page cache once, with single pages pulled out
/// directly while that runs.
abstract class Book {
  List<String> get pageNames;
  int get length => pageNames.length;
  Future<Uint8List> page(int i);
  void close();

  static Future<Book> open(String path, {required String cacheDir, String? sevenZip}) async {
    final raf = File(path).openSync();
    String kind;
    try {
      kind = detectKind(raf);
    } finally {
      raf.closeSync();
    }
    if (kind == 'zip') {
      try {
        return ZipBook(path);
      } catch (_) {
        if (sevenZip == null) rethrow;
      }
    }
    if (sevenZip == null) {
      throw Exception('7-Zip is missing, so this RAR file can\'t be opened.');
    }
    return RarBook.open(path, cacheDir, sevenZip);
  }
}

class ZipBook extends Book {
  ZipBook(String path) : _input = InputFileStream(path) {
    _archive = ZipDecoder().decodeStream(_input);
    final files = {for (final f in _archive.files) if (f.isFile) f.name: f};
    _names = sortPages(files.keys);
    _files = files;
  }
  final InputFileStream _input;
  late final Archive _archive;
  late final Map<String, ArchiveFile> _files;
  late final List<String> _names;

  @override
  List<String> get pageNames => _names;

  @override
  Future<Uint8List> page(int i) async {
    final f = _files[_names[i]]!;
    final bytes = f.readBytes();
    f.clear();
    return bytes ?? Uint8List(0);
  }

  @override
  void close() {
    try {
      _input.closeSync();
    } catch (_) {}
  }
}

class RarBook extends Book {
  RarBook._(this.path, this.dir, this.sevenZip, this._names);
  final String path;
  final String dir;
  final String sevenZip;
  final List<String> _names;
  Process? _extract;
  final Completer<bool> _done = Completer<bool>();

  static Future<RarBook> open(String path, String cacheRoot, String sevenZip) async {
    final st = await File(path).stat();
    final key = sha1.convert(utf8.encode('$path|${st.size}|${st.modified.millisecondsSinceEpoch}')).toString();
    final dir = p.join(cacheRoot, key);
    final names = listWith7z(sevenZip, path);
    final book = RarBook._(path, dir, sevenZip, names);
    final marker = File(p.join(dir, '.complete'));
    if (marker.existsSync()) {
      book._done.complete(true);
      try {
        File(p.join(dir, '.complete')).setLastModifiedSync(DateTime.now());
      } catch (_) {}
    } else {
      book._start();
    }
    return book;
  }

  void _start() async {
    try {
      await Directory(dir).create(recursive: true);
      _extract = await Process.start(sevenZip, ['x', '-y', '-sccUTF-8', '-o$dir', path]);
      _extract!.stdout.drain<void>();
      _extract!.stderr.drain<void>();
      final code = await _extract!.exitCode;
      if (code == 0) {
        await File(p.join(dir, '.complete')).writeAsString('ok');
      }
      if (!_done.isCompleted) _done.complete(code == 0);
    } catch (_) {
      if (!_done.isCompleted) _done.complete(false);
    }
  }

  @override
  List<String> get pageNames => _names;

  bool get extracted => _done.isCompleted;

  @override
  Future<Uint8List> page(int i) async {
    final name = _names[i];
    final f = File(p.join(dir, name));
    if (_done.isCompleted && await _done.future && await f.exists()) {
      return f.readAsBytes();
    }
    // Pull this one page out directly while the full unpack runs.
    final r = await Process.run(sevenZip, ['e', '-so', '-sccUTF-8', path, name],
        stdoutEncoding: null);
    if (r.exitCode == 0 && (r.stdout as List<int>).isNotEmpty) {
      return Uint8List.fromList(r.stdout as List<int>);
    }
    await _done.future;
    return f.readAsBytes();
  }

  @override
  void close() {}
}

/// Clears the oldest unpacked books so the page cache stays under [maxBytes].
Future<void> trimPageCache(String cacheRoot, int maxBytes) async {
  final root = Directory(cacheRoot);
  if (!await root.exists()) return;
  final dirs = <(Directory, DateTime, int)>[];
  var total = 0;
  await for (final e in root.list()) {
    if (e is! Directory) continue;
    var size = 0;
    await for (final f in e.list(recursive: true)) {
      if (f is File) size += await f.length();
    }
    total += size;
    final marker = File(p.join(e.path, '.complete'));
    final used = await marker.exists() ? (await marker.stat()).modified : (await e.stat()).modified;
    dirs.add((e, used, size));
  }
  dirs.sort((a, b) => a.$2.compareTo(b.$2));
  for (final d in dirs) {
    if (total <= maxBytes) break;
    try {
      await d.$1.delete(recursive: true);
      total -= d.$3;
    } catch (_) {}
  }
}

/// Reads width and height from an image header without decoding it.
(int, int)? imageSize(Uint8List b) {
  try {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
      final d = ByteData.sublistView(b);
      return (d.getUint32(16), d.getUint32(20));
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        final len = (b[i + 2] << 8) + b[i + 3];
        if ((marker >= 0xC0 && marker <= 0xC3) || (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) || (marker >= 0xCD && marker <= 0xCF)) {
          final h = (b[i + 5] << 8) + b[i + 6];
          final w = (b[i + 7] << 8) + b[i + 8];
          return (w, h);
        }
        i += 2 + len;
      }
    }
    if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49) {
      return (b[6] | (b[7] << 8), b[8] | (b[9] << 8));
    }
    if (b.length > 30 && b[0] == 0x52 && b[8] == 0x57 && b[9] == 0x45) {
      final d = ByteData.sublistView(b);
      final fourcc = String.fromCharCodes(b.sublist(12, 16));
      if (fourcc == 'VP8X') {
        final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
        final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
        return (w, h);
      } else if (fourcc == 'VP8 ') {
        return (d.getUint16(26, Endian.little) & 0x3fff, d.getUint16(28, Endian.little) & 0x3fff);
      } else if (fourcc == 'VP8L') {
        final bits = d.getUint32(21, Endian.little);
        return ((bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1);
      }
    }
    if (b.length > 26 && b[0] == 0x42 && b[1] == 0x4D) {
      final d = ByteData.sublistView(b);
      return (d.getInt32(18, Endian.little), d.getInt32(22, Endian.little).abs());
    }
  } catch (_) {}
  return null;
}
