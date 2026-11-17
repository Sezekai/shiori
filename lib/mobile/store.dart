import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import 'pc.dart';

/// Phone-side records: what's downloaded, what's waiting to go to the PC,
/// and how much space everything takes.
class Store extends ChangeNotifier {
  Store._();
  static final Store I = Store._();

  /// title uid → downloaded file
  final Map<String, String> downloads = {};

  void init() {
    Library.I.onChange = (kind, t, payload) => queueChange(kind, t, payload);
    _loadDownloads();
  }

  void _loadDownloads() {
    downloads.clear();
    for (final r in Db.I.raw.select('SELECT title_uid, path FROM downloads')) {
      final path = r['path'] as String;
      if (File(path).existsSync()) {
        downloads[r['title_uid'] as String] = path;
      } else {
        Db.I.raw.execute('DELETE FROM downloads WHERE title_uid=?', [r['title_uid']]);
      }
    }
    notifyListeners();
  }

  bool isDownloaded(Title t) => downloads.containsKey(t.uid);
  String? downloadOf(Title t) => downloads[t.uid];

  /// A change made on the phone, kept until the PC has it.
  void queueChange(String kind, Title t, Map<String, Object?> payload) {
    Db.I.addChange(newUid(), kind, t.uid, payload);
    // Later, not now: this can run while a screen is closing.
    Future.microtask(notifyListeners);
    _soon();
  }

  Timer? _push;
  void _soon() {
    _push?.cancel();
    _push = Timer(const Duration(seconds: 3), () async {
      if (!Pc.I.online) return;
      try {
        await Sync.pushChanges();
        notifyListeners();
      } catch (_) {}
    });
  }

  int get waiting => Db.I.raw.select("SELECT COUNT(*) AS n FROM changes WHERE kind != 'save'").first['n'] as int;
  List<Map<String, Object?>> get saveQueue => Db.I.pendingChanges(kind: 'save');

  // ---------------------------------------------------------------- reading

  void recordSession(Title t,
      {required int startedAt, required int activeSeconds, required int fromPage, required int toPage, required int pagesSeen, required bool completed}) {
    final ended = nowSec();
    final uid = Db.I.addSession(
      titleId: t.id,
      startedAt: startedAt,
      endedAt: ended,
      activeSeconds: activeSeconds,
      fromPage: fromPage,
      toPage: toPage,
      pagesSeen: pagesSeen,
      completed: completed,
      device: 'Phone',
      source: 'phone',
    );
    queueChange('session', t, {
      'uid': uid,
      'started_at': startedAt,
      'ended_at': ended,
      'active_seconds': activeSeconds,
      'from_page': fromPage,
      'to_page': toPage,
      'pages_seen': pagesSeen,
      'completed': completed,
      'device': 'Phone',
    });
  }

  void recordCompletion(Title t, int at) {
    final uid = Db.I.addCompletion(t.id, at, source: 'phone');
    queueChange('completion', t, {'uid': uid, 'at': at});
  }

  void recordPosition(Title t) {
    // Only the newest position matters, so replace any older one still waiting.
    Db.I.raw.execute("DELETE FROM changes WHERE kind='reading' AND title_uid=?", [t.uid]);
    queueChange('reading', t, {'lastPage': t.lastPage, 'lastReadAt': t.lastReadAt});
  }

  // ---------------------------------------------------------------- saving pages

  /// Saves on the PC now, or queues it. Returns the PC's answer when it was
  /// reachable ({result: saved | duplicate | failed}), or null when queued.
  Future<Map<String, dynamic>?> savePage(Title t, List<(int page, int half)> parts, {bool force = false}) async {
    final body = {
      'title': t.id,
      'parts': [for (final x in parts) {'page': x.$1, 'half': x.$2}],
      'force': force,
    };
    if (Pc.I.online) {
      try {
        return await Pc.I.postJson('/api/save', body, timeout: const Duration(seconds: 40));
      } catch (_) {}
    }
    queueChange('save', t, {
      'parts': body['parts'],
      'force': force,
      'title': t.displayTitle,
      'label': parts.map((x) => 'p${x.$1 + 1}${x.$2 == 1 ? ' left' : x.$2 == 2 ? ' right' : ''}').join(' + '),
    });
    return null;
  }

  void cancelSave(String uid) {
    Db.I.dropChanges([uid]);
    notifyListeners();
  }

  /// A queued save the PC said was a duplicate: save it anyway next time.
  void forceSave(String uid) {
    final c = Db.I.pendingChanges(kind: 'save').firstWhere((x) => x['uid'] == uid);
    final pl = Map<String, dynamic>.from(c['payload'] as Map)
      ..remove('status')
      ..['force'] = true;
    Db.I.raw.execute('UPDATE changes SET payload=? WHERE uid=?', [jsonEncode(pl), uid]);
    notifyListeners();
    _soon();
  }

  // ---------------------------------------------------------------- downloads

  Future<String> downloadsDir() async {
    final where = Settings.I.get<String>('m.downloadsAt', 'internal');
    if (where == 'sd' && Platform.isAndroid) {
      final ext = await getExternalStorageDirectories();
      if (ext != null && ext.length > 1) return p.join(ext[1].path, 'downloads');
    }
    return p.join(AppPaths.I.data, 'downloads');
  }

  String jobNameFor(Title t) => 'Downloading ${t.displayTitle}';

  void download(Iterable<Title> ts) {
    for (final t in ts) {
      if (isDownloaded(t) || t.missing || Jobs.I.isQueued(jobNameFor(t))) continue;
      Jobs.I.add(Job(jobNameFor(t), (job) => _download(job, t)));
    }
  }

  Future<String?> _download(Job job, Title t) async {
    final dir = await downloadsDir();
    Directory(dir).createSync(recursive: true);
    final target = p.join(dir, '${t.uid}.cbz');
    final part = File('$target.part');
    final res = await Pc.I.stream('GET', '/api/download/${t.id}');
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw PcError('The PC couldn\'t send ${t.displayTitle} (${res.statusCode})');
    }
    final total = res.contentLength > 0 ? res.contentLength : t.size;
    job.progress(0, total: total, detail: '0 of ${humanSize(total)}');
    final sink = part.openWrite();
    var got = 0;
    final sw = Stopwatch()..start();
    try {
      await for (final c in res) {
        if (job.cancelled) break;
        sink.add(c);
        got += c.length;
        final speed = sw.elapsedMilliseconds > 500 ? got * 1000 ~/ sw.elapsedMilliseconds : 0;
        job.progress(got, detail: '${humanSize(got)} of ${humanSize(total)}${speed > 0 ? ' · ${humanSize(speed)}/s' : ''}');
      }
    } finally {
      await sink.close();
    }
    if (job.cancelled) {
      try {
        part.deleteSync();
      } catch (_) {}
      return null;
    }
    await part.rename(target);
    Db.I.raw.execute('INSERT OR REPLACE INTO downloads(title_uid,title_id,path,size,at) VALUES(?,?,?,?,?)',
        [t.uid, t.id, target, got, nowSec()]);
    downloads[t.uid] = target;
    notifyListeners();
    return 'Downloaded ${t.displayTitle} (${humanSize(got)})';
  }

  /// Only the phone's copy goes; the file on the PC is never touched.
  void removeDownload(Iterable<Title> ts) {
    for (final t in ts) {
      final path = downloads.remove(t.uid);
      if (path == null) continue;
      try {
        File(path).deleteSync();
      } catch (e) {
        AppLog.I.warn('Couldn\'t remove $path: $e');
      }
      Db.I.raw.execute('DELETE FROM downloads WHERE title_uid=?', [t.uid]);
    }
    notifyListeners();
  }

  /// "Remove downloads once read", if switched on.
  void afterFinished(Title t) {
    if (Settings.I.get<bool>('m.removeWhenRead', false) && isDownloaded(t)) removeDownload([t]);
  }

  // ---------------------------------------------------------------- storage

  static Future<int> dirSize(String path) async {
    final d = Directory(path);
    if (!await d.exists()) return 0;
    var n = 0;
    try {
      await for (final f in d.list(recursive: true, followLinks: false)) {
        if (f is File) n += await f.length();
      }
    } catch (_) {}
    return n;
  }

  String get streamCache => p.join(AppPaths.I.cache, 'stream');
}

