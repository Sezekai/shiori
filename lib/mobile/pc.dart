import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/server.dart' show kServerPort, kDiscoveryPort, kDiscoverMessage;
import '../core/settings.dart';

enum PcState { unpaired, offline, connecting, online }

class FoundPc {
  FoundPc(this.name, this.host, this.port);
  final String name;
  final String host;
  final int port;
}

class PcError implements Exception {
  PcError(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// The phone's link to the PC: finding it, pairing, requests, and syncing.
class Pc extends ChangeNotifier {
  Pc._();
  static final Pc I = Pc._();

  PcState state = PcState.unpaired;
  String? get host => Settings.I.get<String?>('pc.host', null);
  int get port => Settings.I.get<int>('pc.port', kServerPort);
  String? get token => Settings.I.get<String?>('pc.token', null);
  String get pcName => Settings.I.get<String>('pc.name', 'your PC');
  bool get paired => token != null && host != null;
  bool get online => state == PcState.online;
  int get lastSync => Settings.I.get<int>('pc.lastSync', 0);
  String? lastError;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    ..idleTimeout = const Duration(seconds: 20);
  Timer? _timer;
  bool _checking = false;

  /// Saves, reading and covers queued while offline go as soon as we're back.
  void start() {
    state = paired ? PcState.offline : PcState.unpaired;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => check());
    check();
  }

  void _set(PcState s) {
    if (s == state) return;
    final wasOnline = state == PcState.online;
    state = s;
    notifyListeners();
    if (s == PcState.online && !wasOnline) Sync.queue(quiet: true);
  }

  /// Is the PC there? Tries the remembered address, then looks on the WiFi
  /// in case the PC's address changed.
  /// For the self-test: act as if the PC were switched off.
  bool pretendOffline = false;

  Future<bool> check() async {
    if (pretendOffline) {
      _set(PcState.offline);
      return false;
    }
    if (!paired || _checking) return online;
    _checking = true;
    if (state != PcState.online) _set(PcState.connecting);
    try {
      if (await _hello(host!, port)) {
        _set(PcState.online);
        return true;
      }
      for (final f in await discover(wait: const Duration(milliseconds: 1200))) {
        if (await _hello(f.host, f.port)) {
          Settings.I.extra['pc.host'] = f.host;
          Settings.I.extra['pc.port'] = f.port;
          Settings.I.save();
          _set(PcState.online);
          return true;
        }
      }
      _set(PcState.offline);
      return false;
    } finally {
      _checking = false;
    }
  }

  Future<bool> _hello(String h, int pt) async {
    try {
      final m = await _json('GET', '/api/hello', host: h, port: pt, timeout: const Duration(seconds: 4));
      if (m['paired'] == true) return true;
      if (m['app'] == 'shiori' && h == host) {
        lastError = 'The PC doesn\'t know this phone any more. Pair again.';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the WiFi for Shiori PCs.
  Future<List<FoundPc>> discover({Duration wait = const Duration(seconds: 2)}) async {
    final found = <String, FoundPc>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      sock.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = sock!.receive();
        if (d == null) return;
        try {
          final m = jsonDecode(utf8.decode(d.data)) as Map;
          if (m['app'] != 'shiori') return;
          found[d.address.address] = FoundPc(m['name'] as String? ?? d.address.address, d.address.address, m['port'] as int);
        } catch (_) {}
      });
      final msg = utf8.encode(kDiscoverMessage);
      for (var i = 0; i < 3; i++) {
        sock.send(msg, InternetAddress('255.255.255.255'), kDiscoveryPort);
        await Future<void>.delayed(wait ~/ 3);
      }
    } catch (e) {
      AppLog.I.warn('Looking for the PC on the WiFi failed: $e');
    } finally {
      sock?.close();
    }
    return found.values.toList();
  }

  /// Returns an error message, or null when paired.
  Future<String?> pair(String h, int pt, String code, String deviceName) async {
    try {
      final m = await _json('POST', '/api/pair', host: h, port: pt, body: {'code': code, 'device': deviceName}, auth: false);
      Settings.I.extra['pc.host'] = h;
      Settings.I.extra['pc.port'] = pt;
      Settings.I.extra['pc.token'] = m['token'];
      Settings.I.extra['pc.name'] = m['name'];
      Settings.I.save();
      lastError = null;
      _set(PcState.online);
      return null;
    } on PcError catch (e) {
      return e.message;
    } catch (e) {
      return 'Couldn\'t reach the PC at $h:$pt. Is Shiori open there with the phone connection on?';
    }
  }

  void forget() {
    for (final k in ['pc.host', 'pc.port', 'pc.token', 'pc.name']) {
      Settings.I.extra.remove(k);
    }
    Settings.I.save();
    _set(PcState.unpaired);
  }

  // ------------------------------------------------------------ requests

  Uri _uri(String path, {String? host, int? port}) => Uri.parse('http://${host ?? this.host}:${port ?? this.port}$path');

  Future<HttpClientResponse> _open(String method, String path,
      {Object? body, String? host, int? port, bool auth = true, Duration? timeout}) async {
    final req = await _http.openUrl(method, _uri(path, host: host, port: port)).timeout(timeout ?? const Duration(seconds: 8));
    if (auth && token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(timeout ?? const Duration(seconds: 60));
    if (res.statusCode == 401 && auth) {
      lastError = 'The PC doesn\'t know this phone any more. Pair again.';
      _set(PcState.offline);
    }
    return res;
  }

  Future<Map<String, dynamic>> _json(String method, String path,
      {Object? body, String? host, int? port, bool auth = true, Duration? timeout}) async {
    final res = await _open(method, path, body: body, host: host, port: port, auth: auth, timeout: timeout);
    final text = await utf8.decodeStream(res);
    final m = text.isEmpty ? <String, dynamic>{} : (jsonDecode(text) as Map).cast<String, dynamic>();
    if (res.statusCode >= 400) throw PcError(m['error'] as String? ?? 'The PC said ${res.statusCode}', status: res.statusCode);
    return m;
  }

  Future<Map<String, dynamic>> getJson(String path, {Duration? timeout}) =>
      _guard(() => _json('GET', path, timeout: timeout));
  Future<Map<String, dynamic>> postJson(String path, Object body, {Duration? timeout}) =>
      _guard(() => _json('POST', path, body: body, timeout: timeout));

  Future<Uint8List> getBytes(String path) => _guard(() async {
        final res = await _open('GET', path);
        if (res.statusCode >= 400) {
          await res.drain<void>();
          throw PcError('The PC said ${res.statusCode}', status: res.statusCode);
        }
        final b = BytesBuilder(copy: false);
        await for (final c in res) {
          b.add(c);
        }
        return b.takeBytes();
      });

  /// A streamed response, for downloads.
  Future<HttpClientResponse> stream(String method, String path, {Object? body}) =>
      _guard(() => _open(method, path, body: body, timeout: const Duration(minutes: 10)));

  Future<T> _guard<T>(Future<T> Function() f) async {
    if (!paired) throw PcError('Not connected to a PC yet.');
    try {
      return await f();
    } on PcError {
      rethrow;
    } on SocketException {
      _set(PcState.offline);
      throw PcError('Can\'t reach $pcName right now.');
    } on TimeoutException {
      _set(PcState.offline);
      throw PcError('$pcName didn\'t answer in time.');
    } on HttpException {
      _set(PcState.offline);
      throw PcError('The connection to $pcName dropped.');
    }
  }
}

/// Swapping records with the PC: the phone's changes go first, then the
/// PC's library comes back, then any covers the phone hasn't got.
class Sync {
  static const jobName = 'Syncing with the PC';
  static final ValueNotifier<List<Map<String, dynamic>>> saveResults = ValueNotifier([]);

  static void queue({bool quiet = false}) {
    if (!Pc.I.online || Jobs.I.isQueued(jobName)) return;
    Jobs.I.add(Job(jobName, _run));
  }

  static Future<String?> _run(Job job) async {
    job.progress(0, total: 4, detail: 'sending this phone\'s changes');
    final sent = await pushChanges();
    if (!await job.checkpoint()) return null;

    job.progress(1, detail: 'getting the library');
    final snap = await Pc.I.getJson('/api/snapshot', timeout: const Duration(minutes: 3));
    if (!await job.checkpoint()) return null;
    job.progress(2, detail: 'updating the library on this phone');
    importSnapshot(snap);

    job.progress(3, detail: 'checking covers');
    final got = await _covers(job);
    Settings.I.put('pc.lastSync', nowSec());
    job.progress(4);
    final bits = <String>[
      if (sent > 0) '$sent change${sent == 1 ? '' : 's'} sent',
      '${Library.I.titles(Section.comics).length + Library.I.titles(Section.artbooks).length + Library.I.titles(Section.manga).length} titles',
      if (got > 0) '$got covers',
    ];
    return 'Synced: ${bits.join(' · ')}';
  }

  /// Sends everything waiting. Returns how many changes the PC took.
  static Future<int> pushChanges() async {
    final pending = Db.I.pendingChanges().where((c) => (c['payload'] as Map)['status'] != 'duplicate').toList();
    if (pending.isEmpty) return 0;
    final r = await Pc.I.postJson('/api/sync', {
      'changes': [
        for (final c in pending) {'uid': c['uid'], 'kind': c['kind'], 'title_uid': c['title_uid'], 'payload': c['payload']},
      ],
    }, timeout: const Duration(minutes: 5));
    final applied = (r['applied'] as List).cast<String>();
    Db.I.dropChanges(applied);
    final saves = (r['saves'] as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    for (final s in saves) {
      if (s['result'] == 'duplicate') {
        final c = pending.firstWhere((x) => x['uid'] == s['uid']);
        final pl = Map<String, dynamic>.from(c['payload'] as Map)
          ..['status'] = 'duplicate'
          ..['dupAt'] = s['at']
          ..['dupFile'] = s['file'];
        Db.I.raw.execute('UPDATE changes SET payload=? WHERE uid=?', [jsonEncode(pl), s['uid']]);
      }
    }
    if (saves.isNotEmpty) saveResults.value = saves;
    return applied.length;
  }

  /// Replaces the phone's copy of the library with the PC's. Anything made on
  /// the phone was sent first, so nothing is lost.
  static void importSnapshot(Map<String, dynamic> m) {
    List<Map<String, Object?>> rows(String k) =>
        (m[k] as List).map((r) => (r as Map).cast<String, Object?>()).toList();
    final db = Db.I;
    db.raw.execute('PRAGMA foreign_keys = OFF');
    db.raw.execute('BEGIN');
    try {
      db.replaceRows('title_tags', []);
      db.replaceRows('sessions', []);
      db.replaceRows('completions', []);
      db.replaceRows('titles', rows('titles'));
      db.replaceRows('sessions', rows('sessions'));
      db.replaceRows('completions', rows('completions'));
      db.replaceRows('tags', rows('tags'));
      db.replaceRows('title_tags', rows('title_tags'));
      db.raw.execute('COMMIT');
    } catch (e) {
      db.raw.execute('ROLLBACK');
      rethrow;
    } finally {
      db.raw.execute('PRAGMA foreign_keys = ON');
    }
    // Downloads point at titles by uid; keep their ids current.
    db.raw.execute('UPDATE downloads SET title_id = (SELECT id FROM titles WHERE titles.uid = downloads.title_uid)');
    // Reading defaults follow the PC unless they were changed on the phone.
    final st = (m['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    if (!Settings.I.get<bool>('m.ownReader', false)) {
      for (final s in Section.values) {
        final x = (st[s.name] as Map?)?.cast<String, dynamic>();
        if (x == null) continue;
        final ss = Settings.I.of(s);
        ss.direction = ReadDirection.values.firstWhere((e) => e.name == x['direction'], orElse: () => ss.direction);
        ss.verticalStyle = VerticalStyle.values.firstWhere((e) => e.name == x['verticalStyle'], orElse: () => ss.verticalStyle);
        ss.split = SplitMode.values.firstWhere((e) => e.name == x['split'], orElse: () => ss.split);
        ss.coverOffset = x['coverOffset'] as bool? ?? ss.coverOffset;
      }
      Settings.I.save();
    }
    Library.I.load();
  }

  static Future<int> _covers(Job job) async {
    final want = ((await Pc.I.getJson('/api/covers'))['covers'] as List).cast<String>();
    final dir = AppPaths.I.thumbs;
    Directory(dir).createSync(recursive: true);
    final have = <String>{};
    await for (final f in Directory(dir).list()) {
      have.add(p.basename(f.path));
    }
    final missing = want.where((n) => !have.contains(n)).toList();
    if (missing.isEmpty) return 0;
    job.progress(0, total: missing.length, detail: 'covers');
    var got = 0;
    const pack = 150;
    for (var i = 0; i < missing.length; i += pack) {
      if (!await job.checkpoint()) break;
      final names = missing.sublist(i, i + pack > missing.length ? missing.length : i + pack);
      final res = await Pc.I.stream('POST', '/api/covers', body: {'names': names});
      final b = BytesBuilder(copy: false);
      await for (final c in res) {
        b.add(c);
      }
      final data = b.takeBytes();
      final bd = ByteData.sublistView(data);
      var o = 0;
      while (o + 6 <= data.length) {
        final nl = bd.getUint16(o);
        final name = utf8.decode(data.sublist(o + 2, o + 2 + nl));
        final len = bd.getUint32(o + 2 + nl);
        final start = o + 6 + nl;
        if (len > 0) {
          await File(p.join(dir, name)).writeAsBytes(Uint8List.sublistView(data, start, start + len));
          Thumbs.I.added(name);
          got++;
        }
        o = start + len;
      }
      job.progress(i + names.length, detail: '${i + names.length} of ${missing.length} covers');
    }
    Thumbs.I.refresh();
    return got;
  }
}
