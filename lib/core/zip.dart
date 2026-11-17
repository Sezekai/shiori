import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A small, fully asynchronous ZIP reader for CBZ files.
///
/// It reads only the central directory to list pages, then each page on
/// demand, inflating with the system's zlib. Nothing waits on the window
/// thread, so even very large art books open straight away.
class ZipEntry {
  ZipEntry(this.name, this.method, this.compSize, this.size, this.localOffset);
  final String name;
  final int method; // 0 stored, 8 deflate
  final int compSize;
  final int size;
  final int localOffset;
}

class ZipIndex {
  ZipIndex(this.entries);
  final List<ZipEntry> entries;

  static Future<ZipIndex> read(RandomAccessFile f) async {
    final len = await f.length();
    // End of central directory: in the last 64 KB + 22 bytes.
    final tailLen = len < 65557 ? len : 65557;
    await f.setPosition(len - tailLen);
    final tail = await f.read(tailLen);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 && tail[i + 1] == 0x4b && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('not a zip file (no end record)');
    final t = ByteData.sublistView(tail);
    var count = t.getUint16(eocd + 10, Endian.little);
    var cdSize = t.getUint32(eocd + 12, Endian.little);
    var cdOffset = t.getUint32(eocd + 16, Endian.little);
    if (count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      // ZIP64: a locator sits 20 bytes before the end record.
      final loc = eocd - 20;
      if (loc >= 0 && t.getUint32(loc, Endian.little) == 0x07064b50) {
        final z64 = t.getUint64(loc + 8, Endian.little);
        await f.setPosition(z64);
        final rec = ByteData.sublistView(await f.read(56));
        count = rec.getUint64(32, Endian.little);
        cdSize = rec.getUint64(40, Endian.little);
        cdOffset = rec.getUint64(48, Endian.little);
      }
    }
    await f.setPosition(cdOffset);
    final cd = await f.read(cdSize);
    final d = ByteData.sublistView(cd);
    final out = <ZipEntry>[];
    var p = 0;
    while (p + 46 <= cd.length && d.getUint32(p, Endian.little) == 0x02014b50) {
      final flags = d.getUint16(p + 8, Endian.little);
      final method = d.getUint16(p + 10, Endian.little);
      var comp = d.getUint32(p + 20, Endian.little);
      var size = d.getUint32(p + 24, Endian.little);
      final nameLen = d.getUint16(p + 28, Endian.little);
      final extraLen = d.getUint16(p + 30, Endian.little);
      final commentLen = d.getUint16(p + 32, Endian.little);
      var off = d.getUint32(p + 42, Endian.little);
      final nameBytes = cd.sublist(p + 46, p + 46 + nameLen);
      final name = (flags & 0x800) != 0 ? utf8.decode(nameBytes, allowMalformed: true) : _decodeName(nameBytes);
      // ZIP64 sizes and offset in the extra field.
      var e = p + 46 + nameLen;
      final eEnd = e + extraLen;
      while (e + 4 <= eEnd) {
        final id = d.getUint16(e, Endian.little);
        final sz = d.getUint16(e + 2, Endian.little);
        if (id == 0x0001) {
          var q = e + 4;
          if (size == 0xFFFFFFFF && q + 8 <= e + 4 + sz) {
            size = d.getUint64(q, Endian.little);
            q += 8;
          }
          if (comp == 0xFFFFFFFF && q + 8 <= e + 4 + sz) {
            comp = d.getUint64(q, Endian.little);
            q += 8;
          }
          if (off == 0xFFFFFFFF && q + 8 <= e + 4 + sz) {
            off = d.getUint64(q, Endian.little);
          }
        }
        e += 4 + sz;
      }
      if (!name.endsWith('/')) out.add(ZipEntry(name, method, comp, size, off));
      p += 46 + nameLen + extraLen + commentLen;
    }
    return ZipIndex(out);
  }

  static String _decodeName(List<int> b) {
    try {
      return utf8.decode(b);
    } catch (_) {
      return latin1.decode(b);
    }
  }
}

/// Reads entries from one open zip. Reads are queued, since a file handle
/// does one thing at a time.
class ZipReader {
  ZipReader._(this._f, this.index);
  final RandomAccessFile _f;
  final ZipIndex index;
  Future<void> _last = Future.value();
  bool _closed = false;

  static Future<ZipReader> open(String path) async {
    final f = await File(path).open();
    try {
      return ZipReader._(f, await ZipIndex.read(f));
    } catch (_) {
      await f.close();
      rethrow;
    }
  }

  Future<Uint8List> read(ZipEntry e) {
    final c = Completer<Uint8List>();
    _last = _last.then((_) async {
      try {
        if (_closed) throw StateError('closed');
        await _f.setPosition(e.localOffset);
        final h = ByteData.sublistView(await _f.read(30));
        if (h.getUint32(0, Endian.little) != 0x04034b50) throw const FormatException('bad local header');
        final nameLen = h.getUint16(26, Endian.little);
        final extraLen = h.getUint16(28, Endian.little);
        await _f.setPosition(e.localOffset + 30 + nameLen + extraLen);
        final data = await _f.read(e.compSize);
        c.complete(inflate(e.method, data));
      } catch (err, st) {
        c.completeError(err, st);
      }
    });
    return c.future;
  }

  static Uint8List inflate(int method, Uint8List data) {
    switch (method) {
      case 0:
        return data;
      case 8:
        return Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
      default:
        throw UnsupportedError('compression method $method');
    }
  }

  Future<void> close() async {
    _closed = true;
    await _last.catchError((_) {});
    await _f.close();
  }
}
