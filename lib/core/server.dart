import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'archives.dart';
import 'db.dart';
import 'library.dart';
import 'log.dart';
import 'paths.dart';
import 'savepage.dart';
import 'settings.dart';

/// Ports the PC and phone talk on. HTTP for everything, UDP to be found.
const kServerPort = 47811;
const kDiscoveryPort = 47812;
const kDiscoverMessage = 'SHIORI_DISCOVER';

String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

/// The PC side of the phone connection: a small HTTP server on the home
/// network. It's off until switched on in Settings, and only paired phones
/// get anything from it.
class ShioriServer extends ChangeNotifier {
  ShioriServer._();
  static final ShioriServer I = ShioriServer._();

  HttpServer? _http;
  RawDatagramSocket? _udp;
  String? error;
  bool get running => _http != null;
  int get port => _http?.port ?? kServerPort;

  /// The 6-digit code shown while pairing, and when it stops working.
  String? pairCode;
  DateTime? pairUntil;

  /// Last few things phones did, for the Settings page.
  final List<String> activity = [];
  final Map<String, DateTime> _seen = {};
  List<String> get connectedNow => _seen.entries
      .where((e) => DateTime.now().difference(e.value).inSeconds < 90)
      .map((e) => e.key)
      .toList();

  // Open books, so a phone reading through a file doesn't reopen it per page.
  final Map<int, Future<Book>> _books = {};
  final List<int> _bookOrder = [];

  Future<void> start() async {
    if (running) return;
    error = null;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, Settings.I.get<int>('server.port', kServerPort));
      _http!.autoCompress = true;
      _http!.listen(_handle, onError: (Object e) => AppLog.I.warn('Phone server: $e'));
      AppLog.I.info('Phone server listening on port ${_http!.port}');
    } catch (e) {
      error = 'Couldn\'t start the phone server: $e';
      AppLog.I.warn(error!);
      notifyListeners();
      return;
    }
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort);
      _udp!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = _udp!.receive();
        if (d == null) return;
        if (utf8.decode(d.data, allowMalformed: true).trim() != kDiscoverMessage) return;
        final reply = jsonEncode({'app': 'shiori', 'name': Platform.localHostname, 'port': port});
        _udp!.send(utf8.encode(reply), d.address, d.port);
      });
    } catch (e) {
      AppLog.I.warn('Phone discovery is off ($e). The phone can still connect by the PC\'s address.');
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
    _udp?.close();
    _udp = null;
    for (final b in _books.values) {
      b.then((x) => x.close()).ignore();
    }
    _books.clear();
    _bookOrder.clear();
    notifyListeners();
  }

  /// Starts pairing: a new code that works for 5 minutes.
  String startPairing() {
    final r = Random.secure();
    pairCode = List.generate(6, (_) => r.nextInt(10)).join();
    pairUntil = DateTime.now().add(const Duration(minutes: 5));
    notifyListeners();
    return pairCode!;
  }

  void stopPairing() {
    pairCode = null;
    pairUntil = null;
    notifyListeners();
  }

  /// This PC's addresses on the local network, to type in by hand if needed.
  Future<List<String>> addresses() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in ifs)
          for (final a in i.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      return [];
    }
  }

  void _note(String s) {
    activity.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)}  $s');
    if (activity.length > 40) activity.removeLast();
    notifyListeners();
  }

  // ------------------------------------------------------------------ routing

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Cache-Control', 'no-store');
    try {
      final seg = req.uri.pathSegments;
      if (seg.length < 2 || seg[0] != 'api') return await _send(res, 404, {'error': 'not found'});
      final route = seg[1];

      if (route == 'hello') {
        final device = _auth(req);
        return await _send(res, 200, {
          'app': 'shiori',
          'name': Platform.localHostname,
          'version': const String.fromEnvironment('SHIORI_VERSION', defaultValue: 'dev'),
          'paired': device != null,
        });
      }
      if (route == 'pair' && req.method == 'POST') return await _pair(req);

      final device = _auth(req);
      if (device == null) return await _send(res, 401, {'error': 'This phone isn\'t paired with this PC.'});
      _seen[device] = DateTime.now();

      switch (route) {
        case 'snapshot':
          return await _snapshot(req, device);
        case 'covers':
          return await (req.method == 'POST' ? _coverPack(req) : _send(res, 200, {'covers': Thumbs.I.names.toList()}));
        case 'pages':
          return await _pages(req, int.parse(seg[2]));
        case 'page':
          return await _page(req, int.parse(seg[2]), int.parse(seg[3]));
        case 'download':
          return await _download(req, int.parse(seg[2]), device);
        case 'sync':
          return await _sync(req, device);
        case 'save':
          return await _saveNow(req, device);
      }
      return await _send(res, 404, {'error': 'not found'});
    } catch (e, st) {
      AppLog.I.error('Phone request ${req.uri.path} failed', e, st);
      try {
        await _send(res, 500, {'error': '$e'});
      } catch (_) {}
    }
  }

  String? _auth(HttpRequest req) {
    final h = req.headers.value(HttpHeaders.authorizationHeader);
    if (h == null || !h.startsWith('Bearer ')) return null;
    return Db.I.deviceForToken(hashToken(h.substring(7).trim()));
  }

  Future<void> _send(HttpResponse res, int status, Object body) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final text = await utf8.decodeStream(req);
    return text.isEmpty ? {} : (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  // ------------------------------------------------------------------ pairing

  Future<void> _pair(HttpRequest req) async {
    final b = await _body(req);
    final code = '${b['code'] ?? ''}'.trim();
    final name = '${b['device'] ?? 'Phone'}'.trim();
    if (pairCode == null || pairUntil == null || DateTime.now().isAfter(pairUntil!)) {
      return _send(req.response, 403, {'error': 'Pairing isn\'t open on the PC. Open Settings → Phone → Pair a phone.'});
    }
    if (code != pairCode) return _send(req.response, 403, {'error': 'That code doesn\'t match the one on the PC.'});
    final r = Random.secure();
    final token = List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    Db.I.addDevice(name, hashToken(token));
    stopPairing();
    _note('Paired with $name');
    AppLog.I.info('Paired with phone "$name"');
    return _send(req.response, 200, {'token': token, 'name': Platform.localHostname});
  }

  // ------------------------------------------------------------------ library

  Future<void> _snapshot(HttpRequest req, String device) async {
    final body = {
      'at': nowSec(),
      'titles': Db.I.rows('titles'),
      'sessions': Db.I.rows('sessions'),
      'completions': Db.I.rows('completions'),
      'tags': Db.I.rows('tags'),
      'title_tags': Db.I.rows('title_tags'),
      'saved': Db.I.raw
          .select('SELECT title_id, image_hash, at, pages FROM saved_pages')
          .map((r) => Map.of(r))
          .toList(),
      'settings': {
        for (final s in Section.values)
          s.name: {
            'direction': Settings.I.of(s).direction.name,
            'verticalStyle': Settings.I.of(s).verticalStyle.name,
            'split': Settings.I.of(s).split.name,
            'coverOffset': Settings.I.of(s).coverOffset,
          },
      },
    };
    _note('$device synced the library');
    return _send(req.response, 200, body);
  }

  /// Many covers in one response: for each, name length (2 bytes), name,
  /// data length (4 bytes), data.
  Future<void> _coverPack(HttpRequest req) async {
    final b = await _body(req);
    final names = (b['names'] as List).cast<String>();
    final res = req.response;
    res.headers.contentType = ContentType.binary;
    for (final n in names) {
      if (n.contains('/') || n.contains('\\') || n.contains('..')) continue;
      final f = File(p.join(AppPaths.I.thumbs, n));
      Uint8List data;
      try {
        data = await f.readAsBytes();
      } catch (_) {
        data = Uint8List(0);
      }
      final nb = utf8.encode(n);
      final head = ByteData(2)..setUint16(0, nb.length);
      final len = ByteData(4)..setUint32(0, data.length);
      res.add(head.buffer.asUint8List());
      res.add(nb);
      res.add(len.buffer.asUint8List());
      res.add(data);
    }
    await res.close();
  }

  Future<Book> _book(Title t) {
    final existing = _books[t.id];
    if (existing != null) {
      _bookOrder
        ..remove(t.id)
        ..add(t.id);
      return existing;
    }
    final f = Book.open(t.path, cacheDir: AppPaths.I.pageCache, sevenZip: Library.I.sevenZip);
    _books[t.id] = f;
    _bookOrder.add(t.id);
    f.catchError((Object _) {
      _books.remove(t.id);
      _bookOrder.remove(t.id);
      return f;
    }).ignore();
    while (_bookOrder.length > 4) {
      final old = _bookOrder.removeAt(0);
      _books.remove(old)?.then((b) => b.close()).ignore();
    }
    return f;
  }

  Future<void> _pages(HttpRequest req, int id) async {
    final t = Library.I.byId(id);
    if (t == null || t.missing) return _send(req.response, 404, {'error': 'That file isn\'t on the PC any more.'});
    final book = await _book(t);
    return _send(req.response, 200, {'names': book.pageNames});
  }

  Future<void> _page(HttpRequest req, int id, int i) async {
    final t = Library.I.byId(id);
    if (t == null || t.missing) return _send(req.response, 404, {'error': 'gone'});
    final book = await _book(t);
    if (i < 0 || i >= book.length) return _send(req.response, 404, {'error': 'no such page'});
    var bytes = await book.page(i);
    var ext = p.extension(book.pageNames[i]).toLowerCase();
    final maxW = int.tryParse(req.uri.queryParameters['w'] ?? '');
    if (maxW != null && Settings.I.get<bool>('server.shrink', false)) {
      final size = imageSize(bytes);
      if (size != null && size.$1 > maxW * 1.2) {
        final small = await Isolate.run(() => _shrink(bytes, maxW));
        if (small != null) {
          bytes = small;
          ext = '.jpg';
        }
      }
    }
    final res = req.response;
    res.headers.contentType = ContentType('image', switch (ext) {
      '.png' => 'png',
      '.webp' => 'webp',
      '.gif' => 'gif',
      '.avif' => 'avif',
      _ => 'jpeg',
    });
    res.headers.contentLength = bytes.length;
    // Images are already compressed; don't gzip them again.
    res.headers.set(HttpHeaders.contentEncodingHeader, 'identity');
    res.add(bytes);
    await res.close();
  }

  static Uint8List? _shrink(Uint8List b, int w) {
    final im = img.decodeImage(b);
    if (im == null) return null;
    return img.encodeJpg(img.copyResize(im, width: w, interpolation: img.Interpolation.average), quality: 90);
  }

  /// The whole file. CBZ files are sent as they are; CBR files are repacked
  /// as CBZ first (the images are copied untouched), so the phone never
  /// needs to open RAR files.
  Future<void> _download(HttpRequest req, int id, String device) async {
    final t = Library.I.byId(id);
    if (t == null || t.missing) return _send(req.response, 404, {'error': 'That file isn\'t on the PC any more.'});
    final res = req.response;
    res.headers.set(HttpHeaders.contentEncodingHeader, 'identity');
    res.headers.contentType = ContentType('application', 'vnd.comicbook+zip');
    String path = t.path;
    File? temp;
    if (t.kind != 'zip') {
      final dir = Directory(p.join(AppPaths.I.cache, 'repack'))..createSync(recursive: true);
      temp = File(p.join(dir.path, '${t.id}-${DateTime.now().microsecondsSinceEpoch}.cbz'));
      _note('Repacking ${t.fileName} for $device');
      final book = await Book.open(t.path, cacheDir: AppPaths.I.pageCache, sevenZip: Library.I.sevenZip);
      try {
        await writeStoredZip(temp.path, book);
      } finally {
        book.close();
      }
      path = temp.path;
    }
    final f = File(path);
    res.headers.contentLength = await f.length();
    _note('$device is downloading ${t.displayTitle}');
    try {
      await res.addStream(f.openRead());
      await res.close();
    } finally {
      if (temp != null) {
        try {
          temp.deleteSync();
        } catch (_) {}
      }
    }
  }

  // ------------------------------------------------------------------ sync

  /// Takes the phone's changes. Readings and completions are only ever
  /// added, so nothing read on the phone is lost; the rest is last-change-wins.
  Future<void> _sync(HttpRequest req, String device) async {
    final b = await _body(req);
    final changes = (b['changes'] as List? ?? []).cast<Map>();
    final applied = <String>[];
    final saves = <Map<String, Object?>>[];
    final byUid = {for (final s in Section.values) for (final t in Library.I.titles(s)) t.uid: t};
    var sessions = 0, other = 0;
    for (final c in changes) {
      final uid = c['uid'] as String;
      if (Db.I.hasChange(uid)) {
        applied.add(uid);
        continue;
      }
      final kind = c['kind'] as String;
      final pl = (c['payload'] as Map).cast<String, dynamic>();
      final t = byUid[c['title_uid']];
      if (t == null) {
        applied.add(uid); // the title went away on the PC; nothing to do
        continue;
      }
      if (kind == 'save') {
        final r = await _doSave(t, pl);
        saves.add({'uid': uid, ...r});
        if (r['result'] != 'duplicate') {
          Db.I.addChange(uid, kind, t.uid, {});
          applied.add(uid);
        }
        continue;
      }
      _apply(kind, t, pl);
      if (kind == 'session') {
        sessions++;
      } else {
        other++;
      }
      Db.I.addChange(uid, kind, t.uid, {});
      applied.add(uid);
    }
    if (sessions + other > 0) {
      Library.I.changed();
      _note('$device sent ${sessions > 0 ? '$sessions reading session${sessions == 1 ? '' : 's'}' : ''}'
          '${sessions > 0 && other > 0 ? ' and ' : ''}${other > 0 ? '$other change${other == 1 ? '' : 's'}' : ''}');
    }
    return _send(req.response, 200, {'applied': applied, 'saves': saves});
  }

  void _apply(String kind, Title t, Map<String, dynamic> pl) {
    switch (kind) {
      case 'session':
        if (Db.I.hasSession(pl['uid'] as String)) return;
        Db.I.addSession(
          titleId: t.id,
          startedAt: pl['started_at'] as int,
          endedAt: pl['ended_at'] as int,
          activeSeconds: pl['active_seconds'] as int,
          fromPage: pl['from_page'] as int,
          toPage: pl['to_page'] as int,
          pagesSeen: pl['pages_seen'] as int,
          completed: pl['completed'] == true || pl['completed'] == 1,
          device: pl['device'] as String? ?? 'Phone',
          source: 'phone',
          uid: pl['uid'] as String,
        );
        t.timeSpent += pl['active_seconds'] as int;
        Db.I.updateReading(t);
      case 'completion':
        if (Db.I.hasCompletion(pl['uid'] as String)) return;
        final at = pl['at'] as int;
        Db.I.addCompletion(t.id, at, source: 'phone', uid: pl['uid'] as String);
        t.readCount += 1;
        t.manualRead = false;
        t.firstCompletedAt = t.firstCompletedAt == 0 ? at : min(t.firstCompletedAt, at);
        t.lastCompletedAt = max(t.lastCompletedAt, at);
        Db.I.updateReading(t);
      case 'reading':
        final at = pl['lastReadAt'] as int;
        if (at >= t.lastReadAt) {
          t.lastPage = pl['lastPage'] as int;
          t.lastReadAt = at;
          Db.I.updateReading(t);
        }
      case 'rating':
        Library.I.setRating(t, (pl['rating'] as num).toDouble());
      case 'favourite':
        Library.I.toggleFavourite([t], pl['value'] as bool);
      case 'mark':
        Library.I.markRead([t], pl['read'] as bool);
      case 'tag':
        // By name first: a tag made on the phone has the phone's own id.
        final tag = Library.I.tags(t.section).where((x) => x.name == pl['name']).firstOrNull ??
            Library.I.tagById(t.section, pl['tag'] as int) ??
            (pl['add'] == true ? Library.I.createTag(t.section, pl['name'] as String) : null);
        if (tag == null) return;
        pl['add'] == true ? Library.I.addTag(tag, [t]) : Library.I.removeTag(tag, [t]);
    }
  }

  Future<void> _saveNow(HttpRequest req, String device) async {
    final b = await _body(req);
    final t = Library.I.byId(b['title'] as int);
    if (t == null) return _send(req.response, 404, {'result': 'failed', 'message': 'That title isn\'t on the PC any more.'});
    final r = await _doSave(t, b);
    if (r['result'] == 'saved') _note('Saved a page from ${t.displayTitle} for $device');
    return _send(req.response, 200, r);
  }

  /// [pl]: {parts: [{page, half}], force}. Pages come from the PC's own file,
  /// so the quality is always the original.
  Future<Map<String, Object?>> _doSave(Title t, Map<String, dynamic> pl) async {
    if (t.missing) return {'result': 'failed', 'message': 'The file isn\'t on the PC any more.'};
    try {
      final book = await _book(t);
      final parts = <PagePart>[];
      for (final x in (pl['parts'] as List).cast<Map>()) {
        final i = x['page'] as int;
        parts.add(PagePart(i, await book.page(i), p.extension(book.pageNames[i]), half: x['half'] as int? ?? 0));
      }
      final r = await PageSaver.save(title: t, parts: parts, force: pl['force'] == true);
      return switch (r) {
        Saved(:final path) => {'result': 'saved', 'file': p.basename(path)},
        AlreadySaved(:final at, :final path) => {
            'result': 'duplicate',
            'at': at,
            'file': p.basename(path),
            'moved': !File(path).existsSync(),
          },
        SaveFailed(:final message) => {'result': 'failed', 'message': message},
      };
    } catch (e) {
      return {'result': 'failed', 'message': '$e'};
    }
  }
}

/// Writes [book]'s pages to a ZIP with no compression (the images are
/// already compressed), one page at a time so memory stays small.
Future<void> writeStoredZip(String path, Book book) async {
  final out = File(path).openSync(mode: FileMode.write);
  final central = BytesBuilder();
  var offset = 0;
  var count = 0;
  try {
    for (var i = 0; i < book.length; i++) {
      final data = await book.page(i);
      final name = utf8.encode(book.pageNames[i].replaceAll('\\', '/'));
      final crc = getCrc32(data);
      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 0x0800, Endian.little) // UTF-8 names
        ..setUint16(8, 0, Endian.little)
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, data.length, Endian.little)
        ..setUint32(22, data.length, Endian.little)
        ..setUint16(26, name.length, Endian.little);
      out.writeFromSync(local.buffer.asUint8List());
      out.writeFromSync(name);
      out.writeFromSync(data);
      final cd = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, 0x0800, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, data.length, Endian.little)
        ..setUint32(24, data.length, Endian.little)
        ..setUint16(28, name.length, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central
        ..add(cd.buffer.asUint8List())
        ..add(name);
      offset += 30 + name.length + data.length;
      count++;
    }
    final cdBytes = central.takeBytes();
    out.writeFromSync(cdBytes);
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, count, Endian.little)
      ..setUint16(10, count, Endian.little)
      ..setUint32(12, cdBytes.length, Endian.little)
      ..setUint32(16, offset, Endian.little);
    out.writeFromSync(end.buffer.asUint8List());
  } finally {
    out.closeSync();
  }
}
