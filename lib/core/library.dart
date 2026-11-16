import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'archives.dart';
import 'db.dart';
import 'jobs.dart';
import 'log.dart';
import 'parse.dart';
import 'paths.dart';
import 'settings.dart';

enum Tri { any, yes, no }

Tri nextTri(Tri t) => Tri.values[(t.index + 1) % 3];

/// Filters for one section's library. Every filter has its opposite (Tri.no).
class LibFilter {
  String search = '';
  Tri read = Tri.any;
  Tri inProgress = Tri.any;
  Tri favourite = Tri.any;
  Tri rated = Tri.any;
  Tri series = Tri.any;
  Tri needsCheck = Tri.any;
  Set<String> artists = {};
  Set<String> excludeArtists = {};
  Set<int> tags = {};
  Set<int> excludeTags = {};
  Tri ratingRange = Tri.any;
  double minRating = 0.5;
  double maxRating = 5;
  Tri readCount = Tri.any;
  int readCountMin = 2;
  Tri pageRange = Tri.any;
  int minPages = 0;
  int maxPages = 100;
  Tri sizeRange = Tri.any;
  int minSizeMb = 0;
  int maxSizeMb = 100;
  Tri readIn = Tri.any;
  int readInDays = 30;

  bool get isEmpty =>
      search.isEmpty &&
      read == Tri.any &&
      inProgress == Tri.any &&
      favourite == Tri.any &&
      rated == Tri.any &&
      series == Tri.any &&
      needsCheck == Tri.any &&
      artists.isEmpty &&
      excludeArtists.isEmpty &&
      tags.isEmpty &&
      excludeTags.isEmpty &&
      ratingRange == Tri.any &&
      readCount == Tri.any &&
      pageRange == Tri.any &&
      sizeRange == Tri.any &&
      readIn == Tri.any;

  Map<String, dynamic> toJson() => {
        'search': search,
        'read': read.index,
        'inProgress': inProgress.index,
        'favourite': favourite.index,
        'rated': rated.index,
        'series': series.index,
        'needsCheck': needsCheck.index,
        'artists': artists.toList(),
        'excludeArtists': excludeArtists.toList(),
        'tags': tags.toList(),
        'excludeTags': excludeTags.toList(),
        'ratingRange': ratingRange.index,
        'minRating': minRating,
        'maxRating': maxRating,
        'readCount': readCount.index,
        'readCountMin': readCountMin,
        'pageRange': pageRange.index,
        'minPages': minPages,
        'maxPages': maxPages,
        'sizeRange': sizeRange.index,
        'minSizeMb': minSizeMb,
        'maxSizeMb': maxSizeMb,
        'readIn': readIn.index,
        'readInDays': readInDays,
      };

  static LibFilter fromJson(Map m) {
    Tri t(String k) => Tri.values[(m[k] as int?) ?? 0];
    return LibFilter()
      ..search = m['search'] as String? ?? ''
      ..read = t('read')
      ..inProgress = t('inProgress')
      ..favourite = t('favourite')
      ..rated = t('rated')
      ..series = t('series')
      ..needsCheck = t('needsCheck')
      ..artists = ((m['artists'] as List?) ?? []).cast<String>().toSet()
      ..excludeArtists = ((m['excludeArtists'] as List?) ?? []).cast<String>().toSet()
      ..tags = ((m['tags'] as List?) ?? []).cast<int>().toSet()
      ..excludeTags = ((m['excludeTags'] as List?) ?? []).cast<int>().toSet()
      ..ratingRange = t('ratingRange')
      ..minRating = (m['minRating'] as num?)?.toDouble() ?? 0.5
      ..maxRating = (m['maxRating'] as num?)?.toDouble() ?? 5
      ..readCount = t('readCount')
      ..readCountMin = m['readCountMin'] as int? ?? 2
      ..pageRange = t('pageRange')
      ..minPages = m['minPages'] as int? ?? 0
      ..maxPages = m['maxPages'] as int? ?? 100
      ..sizeRange = t('sizeRange')
      ..minSizeMb = m['minSizeMb'] as int? ?? 0
      ..maxSizeMb = m['maxSizeMb'] as int? ?? 100
      ..readIn = t('readIn')
      ..readInDays = m['readInDays'] as int? ?? 30;
  }

  LibFilter copy() => fromJson(toJson());
}

const sortKeys = {
  'title': 'Title A–Z',
  'artist': 'Artist',
  'size': 'File size',
  'pages': 'Page count',
  'rating': 'Rating',
  'added': 'Date added',
  'lastRead': 'Last read',
  'firstCompleted': 'First completed',
  'lastCompleted': 'Last completed',
  'readCount': 'Times read',
  'timeSpent': 'Time spent reading',
  'progress': 'Progress',
  'random': 'Random',
};

/// What the grid shows: a single title, a series, or (comics) a folder.
sealed class Entry {
  String get id;
  String get name;
  List<Title> get titles;
  Title get cover => titles.first;
}

class TitleEntry extends Entry {
  TitleEntry(this.t);
  final Title t;
  @override
  String get id => 't${t.id}';
  @override
  String get name => t.displayTitle;
  @override
  List<Title> get titles => [t];
}

class GroupEntry extends Entry {
  GroupEntry(this.key, this.titles, this.label);
  final String key;
  @override
  final List<Title> titles; // in chapter order
  final String label;
  @override
  String get id => 'g$key';
  @override
  String get name => label;
  int get readChapters => titles.where((t) => t.isRead).length;
}

class FolderEntry extends Entry {
  FolderEntry(this.relPath, this.titles);
  final String relPath;
  @override
  final List<Title> titles;
  @override
  String get id => 'f$relPath';
  @override
  String get name => p.basename(relPath);
}

/// The library: every title held in memory per section, with the database
/// kept in step on every change.
class Library extends ChangeNotifier {
  Library._();
  static final Library I = Library._();

  final Map<Section, List<Title>> _titles = {for (final s in Section.values) s: []};
  final Map<Section, List<Tag>> _tags = {for (final s in Section.values) s: []};
  final Map<Section, Map<int, Set<int>>> _tagMap = {for (final s in Section.values) s: {}};
  final Map<Section, Set<String>> unavailableRoots = {for (final s in Section.values) s: {}};
  final Map<int, Title> _byId = {};
  final Map<Section, LibFilter> filters = {for (final s in Section.values) s: LibFilter()};
  String? sevenZip;
  /// After two unclean exits: no folder watching or background cover making.
  bool safeMode = false;
  int _randomSeed = Random().nextInt(1 << 30);
  final List<StreamSubscription> _watchers = [];
  Timer? _watchDebounce;
  final Set<Section> _watchPending = {};

  List<Title> titles(Section s) => _titles[s]!;
  List<Tag> tags(Section s) => _tags[s]!;
  Set<int> tagsOf(Title t) => _tagMap[t.section]![t.id] ?? const {};
  Title? byId(int id) => _byId[id];
  Tag? tagById(Section s, int id) => _tags[s]!.where((t) => t.id == id).firstOrNull;

  void load() {
    sevenZip = findSevenZip();
    if (sevenZip == null) {
      AppLog.I.warn('7-Zip wasn\'t found, so CBR files can\'t be opened.');
    } else {
      AppLog.I.info('Using 7-Zip at $sevenZip');
    }
    _byId.clear();
    for (final s in Section.values) {
      _titles[s] = Db.I.titles(s);
      for (final t in _titles[s]!) {
        _byId[t.id] = t;
      }
      _tags[s] = Db.I.tags(s);
      _tagMap[s] = Db.I.tagMap(s);
    }
    notifyListeners();
  }

  void reloadTags(Section s) {
    _tags[s] = Db.I.tags(s);
    _tagMap[s] = Db.I.tagMap(s);
    notifyListeners();
  }

  /// Goes up on every change, so screens can reuse work until it moves.
  int version = 0;

  @override
  void notifyListeners() {
    version++;
    super.notifyListeners();
  }

  void changed() => notifyListeners();

  void reshuffle() {
    _randomSeed = Random().nextInt(1 << 30);
    notifyListeners();
  }

  // ---------------- queries ----------------

  bool matches(Title t, LibFilter f, {bool inSeries = false}) {
    if (f.search.isNotEmpty) {
      final q = f.search.toLowerCase();
      final tagNames = tagsOf(t).map((id) => tagById(t.section, id)?.name ?? '').join(' ');
      final hay = '${t.displayTitle} ${t.altTitle ?? ''} ${t.displayArtist ?? ''} ${t.circle ?? ''} '
              '${t.parody ?? ''} ${t.source ?? ''} ${t.fileName} $tagNames ${t.relDir}'
          .toLowerCase();
      for (final word in q.split(RegExp(r'\s+'))) {
        if (word.isNotEmpty && !hay.contains(word)) return false;
      }
    }
    bool tri(Tri x, bool v) => x == Tri.any || (x == Tri.yes ? v : !v);
    if (!tri(f.read, t.isRead)) return false;
    if (!tri(f.inProgress, t.inProgress)) return false;
    if (!tri(f.favourite, t.favourite)) return false;
    if (!tri(f.rated, t.rating > 0)) return false;
    if (!tri(f.series, inSeries)) return false;
    if (!tri(f.needsCheck, t.needsCheck)) return false;
    final a = t.displayArtist ?? '';
    if (f.artists.isNotEmpty && !f.artists.contains(a)) return false;
    if (f.excludeArtists.contains(a)) return false;
    final tg = tagsOf(t);
    if (f.tags.isNotEmpty && !f.tags.every(tg.contains)) return false;
    if (f.excludeTags.any(tg.contains)) return false;
    if (!tri(f.ratingRange, t.rating >= f.minRating && t.rating <= f.maxRating && t.rating > 0)) {
      return false;
    }
    if (!tri(f.readCount, t.readCount >= f.readCountMin)) return false;
    if (!tri(f.pageRange, t.pages >= f.minPages && t.pages <= f.maxPages)) return false;
    final mb = t.size / 1024 / 1024;
    if (!tri(f.sizeRange, mb >= f.minSizeMb && mb <= f.maxSizeMb)) return false;
    final since = nowSec() - f.readInDays * 86400;
    if (!tri(f.readIn, t.lastReadAt >= since)) return false;
    return true;
  }

  /// Series grouping: titles that share a series key and have more than one member.
  Map<String, List<Title>> seriesGroups(Section s) {
    final m = <String, List<Title>>{};
    for (final t in _titles[s]!) {
      if (t.missing || t.isContainer) continue;
      m.putIfAbsent(t.groupKey, () => []).add(t);
    }
    m.removeWhere((k, v) => v.length < 2);
    for (final v in m.values) {
      v.sort(chapterOrder);
    }
    return m;
  }

  static int chapterOrder(Title a, Title b) {
    final ca = a.displayChapter ?? (a.orderPrefix?.toDouble()) ?? 0;
    final cb = b.displayChapter ?? (b.orderPrefix?.toDouble()) ?? 0;
    final c = ca.compareTo(cb);
    if (c != 0) return c;
    return naturalCompare(a.fileName, b.fileName);
  }

  /// The entries for the grid, after filters, grouping and sorting.
  List<Entry> entries(Section s, {String? folder, bool? folderView}) {
    final ss = Settings.I.of(s);
    final f = filters[s]!;
    final useFolders = s == Section.comics && (folderView ?? ss.comicsFolderView);
    final List<Entry> out;
    if (useFolders) {
      out = _folderEntries(s, folder ?? '', f);
    } else {
      final groups = seriesGroups(s);
      final grouped = <String>{};
      final list = <Entry>[];
      for (final g in groups.entries) {
        final members = g.value.where((t) => matches(t, f, inSeries: true)).toList();
        if (members.isEmpty) continue;
        grouped.add(g.key);
        final first = g.value.first;
        list.add(GroupEntry(g.key, g.value, _groupLabel(first)));
      }
      for (final t in _titles[s]!) {
        if (t.missing || t.isContainer) continue;
        if (groups.containsKey(t.groupKey)) continue;
        if (matches(t, f)) list.add(TitleEntry(t));
      }
      out = list;
    }
    sortEntries(out, ss.sort, ss.sortDesc);
    return out;
  }

  String _groupLabel(Title t) {
    final base = t.displaySeries;
    if (t.section == Section.comics && t.volume != null) return '$base v${t.volume}';
    return base;
  }

  List<Entry> _folderEntries(Section s, String folder, LibFilter f) {
    final sub = <String, List<Title>>{};
    final here = <Entry>[];
    final prefix = folder.isEmpty ? '' : '$folder${p.separator}';
    for (final t in _titles[s]!) {
      if (t.missing || t.isContainer) continue;
      final rel = t.root.isEmpty ? t.relDir : p.join(_rootLabel(t.root), t.relDir);
      final relNorm = rel.endsWith(p.separator) ? rel.substring(0, rel.length - 1) : rel;
      if (folder.isEmpty || relNorm == folder || relNorm.startsWith(prefix)) {
        final rest = folder.isEmpty ? relNorm : (relNorm == folder ? '' : relNorm.substring(prefix.length));
        if (!matches(t, f)) continue;
        if (rest.isEmpty) {
          here.add(TitleEntry(t));
        } else {
          final first = rest.split(p.separator).first;
          sub.putIfAbsent(prefix + first, () => []).add(t);
        }
      }
    }
    final folders = sub.entries.map((e) => FolderEntry(e.key, e.value..sort(_pathOrder))).toList()
      ..sort((a, b) => naturalCompare(a.relPath, b.relPath));
    return [...folders, ...here];
  }

  int _pathOrder(Title a, Title b) => naturalCompare(a.path, b.path);

  String _rootLabel(String root) {
    // With one folder per section the root itself isn't shown.
    return '';
  }

  void sortEntries(List<Entry> list, String key, bool desc) {
    final folders = list.whereType<FolderEntry>().toList();
    final rest = list.where((e) => e is! FolderEntry).toList();
    num agg(Entry e, num Function(Title) f, {bool max = true, bool sum = false}) {
      final ts = e.titles;
      if (sum) return ts.fold<num>(0, (a, t) => a + f(t));
      return ts.map(f).reduce((a, b) => max ? (a > b ? a : b) : (a < b ? a : b));
    }

    int cmp(Entry a, Entry b) {
      switch (key) {
        case 'artist':
          final c = (a.cover.displayArtist ?? '￿').toLowerCase().compareTo(
              (b.cover.displayArtist ?? '￿').toLowerCase());
          return c != 0 ? c : naturalCompare(a.name, b.name);
        case 'size':
          return agg(a, (t) => t.size, sum: true).compareTo(agg(b, (t) => t.size, sum: true));
        case 'pages':
          return agg(a, (t) => t.pages, sum: true).compareTo(agg(b, (t) => t.pages, sum: true));
        case 'rating':
          return agg(a, (t) => t.rating).compareTo(agg(b, (t) => t.rating));
        case 'added':
          return agg(a, (t) => t.addedAt).compareTo(agg(b, (t) => t.addedAt));
        case 'lastRead':
          return agg(a, (t) => t.lastReadAt).compareTo(agg(b, (t) => t.lastReadAt));
        case 'firstCompleted':
          return agg(a, (t) => t.firstCompletedAt == 0 ? 1 << 40 : t.firstCompletedAt, max: false)
              .compareTo(agg(b, (t) => t.firstCompletedAt == 0 ? 1 << 40 : t.firstCompletedAt, max: false));
        case 'lastCompleted':
          return agg(a, (t) => t.lastCompletedAt).compareTo(agg(b, (t) => t.lastCompletedAt));
        case 'readCount':
          return agg(a, (t) => t.readCount, sum: true).compareTo(agg(b, (t) => t.readCount, sum: true));
        case 'timeSpent':
          return agg(a, (t) => t.timeSpent, sum: true).compareTo(agg(b, (t) => t.timeSpent, sum: true));
        case 'progress':
          return entryProgress(a).compareTo(entryProgress(b));
        case 'random':
          return (a.cover.id * 2654435761 ^ _randomSeed).toUnsigned(32)
              .compareTo((b.cover.id * 2654435761 ^ _randomSeed).toUnsigned(32));
        default:
          return naturalCompare(a.name, b.name);
      }
    }

    rest.sort((a, b) {
      final c = cmp(a, b);
      final r = desc ? -c : c;
      return r != 0 ? r : naturalCompare(a.name, b.name);
    });
    list
      ..clear()
      ..addAll(folders)
      ..addAll(rest);
  }

  double entryProgress(Entry e) {
    if (e is TitleEntry) return e.t.progress;
    final ts = e.titles;
    if (ts.isEmpty) return 0;
    return ts.where((t) => t.isRead).length / ts.length;
  }

  // ---------------- reading state ----------------

  void setRating(Title t, double r) {
    t.rating = r;
    Db.I.updateReading(t);
    notifyListeners();
  }

  void toggleFavourite(Iterable<Title> ts, [bool? value]) {
    final v = value ?? !ts.every((t) => t.favourite);
    for (final t in ts) {
      t.favourite = v;
      Db.I.updateReading(t);
    }
    notifyListeners();
  }

  /// Marks read by hand. Hand marks are labelled so they don't count towards time.
  void markRead(Iterable<Title> ts, bool read) {
    final now = nowSec();
    Db.I.raw.execute('BEGIN');
    for (final t in ts) {
      if (read) {
        if (t.isRead) continue;
        Db.I.addCompletion(t.id, now, manual: true);
        t.readCount = 1;
        t.manualRead = true;
        t.firstCompletedAt = t.firstCompletedAt == 0 ? now : t.firstCompletedAt;
        t.lastCompletedAt = now;
        t.lastPage = 0;
      } else {
        Db.I.removeManualCompletions(t.id);
        final left = Db.I.completions(titleId: t.id);
        t.readCount = left.length;
        t.manualRead = false;
        if (left.isEmpty) {
          t.firstCompletedAt = 0;
          t.lastCompletedAt = 0;
          t.lastPage = 0;
        }
      }
      Db.I.updateReading(t);
    }
    Db.I.raw.execute('COMMIT');
    notifyListeners();
  }

  /// Every chapter before [t] in its series.
  List<Title> previousChapters(Title t) {
    final g = seriesGroups(t.section)[t.groupKey];
    if (g == null) return [];
    final i = g.indexWhere((x) => x.id == t.id);
    return i <= 0 ? [] : g.sublist(0, i);
  }

  void saveEdits(Title t) {
    Db.I.updateEdits(t);
    notifyListeners();
  }

  // ---------------- tags ----------------

  Tag createTag(Section s, String name) {
    final colors = [0xff9b86ff, 0xff2fe0c0, 0xffff6fb1, 0xffffbf5a, 0xff5aa8ff, 0xff5be38a,
      0xffff8a5c, 0xffd07bff, 0xff7fd4ff, 0xfff2e05a];
    final t = Db.I.createTag(s, name, colors[_tags[s]!.length % colors.length]);
    reloadTags(s);
    return t;
  }

  void addTag(Tag tag, Iterable<Title> ts) {
    Db.I.addToTag(tag.id, ts.map((t) => t.id));
    reloadTags(tag.section);
  }

  void removeTag(Tag tag, Iterable<Title> ts) {
    Db.I.removeFromTag(tag.id, ts.map((t) => t.id));
    reloadTags(tag.section);
  }

  // ---------------- scanning ----------------

  void scan(Section s, {bool quiet = false}) {
    final name = 'Scanning ${s.label}';
    if (Jobs.I.isQueued(name)) return;
    Jobs.I.add(Job(name, (job) => _scan(s, job), canPause: true));
  }

  Future<String?> _scan(Section s, Job job) async {
    final ss = Settings.I.of(s);
    final roots = ss.folders;
    final excluded = ss.excluded.map((e) => e.toLowerCase()).toSet();
    unavailableRoots[s]!.clear();
    job.setDetail('Listing files…');
    final listed = <String, (int, int, String)>{}; // path -> size, mtime, root
    for (final root in roots) {
      if (!Directory(root).existsSync()) {
        unavailableRoots[s]!.add(root);
        AppLog.I.warn('${s.label}: the folder $root can\'t be reached. Is its drive connected?');
        continue;
      }
      final files = await _listInBackground(root, excluded);
      for (final f in files) {
        listed[f.$1] = (f.$2, f.$3, root);
      }
      if (!await job.checkpoint()) return null;
    }
    notifyListeners();

    final existing = {for (final t in _titles[s]!) t.path: t};
    final toInspect = <String>[];
    for (final e in listed.entries) {
      final t = existing[e.key];
      // Unchanged files are skipped, damaged ones included: they're retried only when they change.
      if (t == null || t.size != e.value.$1 || t.mtime != e.value.$2) {
        toInspect.add(e.key);
      } else if (t.missing) {
        t.missing = false;
        Db.I.raw.execute('UPDATE titles SET missing=0 WHERE id=?', [t.id]);
      }
    }
    // Missing files: only under roots that can be reached.
    final goneByFp = <String, Title>{};
    for (final t in _titles[s]!) {
      if (listed.containsKey(t.path)) continue;
      if (unavailableRoots[s]!.any((r) => p.isWithin(r, t.path))) continue;
      if (!t.missing) {
        t.missing = true;
        Db.I.raw.execute('UPDATE titles SET missing=1 WHERE id=?', [t.id]);
      }
      goneByFp[t.fingerprint] = t;
    }

    final sz = sevenZip;
    final total = toInspect.length;
    var done = 0;
    var added = 0, moved = 0, updated = 0, failed = 0;
    job.progress(0, total: total, detail: total == 0 ? 'Nothing new' : 'Reading new and changed files');
    const batchSize = 24;
    var lastRefresh = DateTime.now();
    for (var i = 0; i < toInspect.length; i += batchSize) {
      if (!await job.checkpoint()) break;
      final batch = toInspect.sublist(i, min(i + batchSize, toInspect.length));
      AppLog.I.fileOnly('Scan ${s.label}: files ${i + 1}–${i + batch.length} of $total · memory ${ProcessInfo.currentRss ~/ (1024 * 1024)} MB · ${p.basename(batch.first)}');
      final infos = await _inspectInBackground(batch, sz);
      Db.I.raw.execute('BEGIN');
      for (final info in infos) {
        final root = listed[info.path]!.$3;
        if (info.error != null) {
          failed++;
          AppLog.I.warn('Couldn\'t read ${p.basename(info.path)}: ${info.error}');
        }
        final ex = existing[info.path];
        if (ex != null) {
          _applyInfo(ex, info, root);
          updated++;
        } else if (goneByFp[info.fingerprint] != null) {
          final t = goneByFp.remove(info.fingerprint)!;
          existing.remove(t.path);
          _applyInfo(t, info, root);
          moved++;
        } else {
          final t = _insert(s, info, root);
          if (t != null) {
            _titles[s]!.add(t);
            _byId[t.id] = t;
            added++;
          }
        }
        done++;
      }
      Db.I.raw.execute('COMMIT');
      job.progress(done, detail: p.basename(batch.last));
      if (DateTime.now().difference(lastRefresh).inSeconds >= 3) {
        lastRefresh = DateTime.now();
        notifyListeners();
      }
    }
    notifyListeners();
    if (!safeMode) Thumbs.I.queueMissing(s);
    final missing = _titles[s]!.where((t) => t.missing).length;
    return '${s.label}: ${listed.length} files · $added new · $moved moved · $updated updated'
        '${failed > 0 ? ' · $failed couldn\'t be read' : ''}${missing > 0 ? ' · $missing not found' : ''}';
  }

  static List<(String, int, int)> _listBooks(String root, Set<String> excluded) {
    final out = <(String, int, int)>[];
    void walk(Directory d) {
      List<FileSystemEntity> items;
      try {
        items = d.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final e in items) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (excluded.contains(name.toLowerCase())) continue;
          walk(e);
        } else if (e is File) {
          final ext = p.extension(name).toLowerCase();
          if (ext == '.cbz' || ext == '.cbr' || ext == '.zip' || ext == '.rar' || ext == '.cb7') {
            try {
              final st = e.statSync();
              out.add((e.path, st.size, st.modified.millisecondsSinceEpoch ~/ 1000));
            } catch (_) {}
          }
        }
      }
    }

    walk(Directory(root));
    return out;
  }

  ParsedName parseFor(Section s, String fileName) => switch (s) {
        Section.manga => parseManga(fileName),
        Section.comics => parseComic(fileName),
        Section.artbooks => parseArtBook(fileName),
      };

  void _applyInfo(Title t, FileInfo info, String root) {
    final parsed = parseFor(t.section, p.basename(info.path));
    t
      ..path = info.path
      ..root = root
      ..relDir = _rel(root, info.path)
      ..fileName = p.basename(info.path)
      ..size = info.size
      ..mtime = info.mtime
      ..fingerprint = info.fingerprint
      ..kind = info.kind
      ..pages = info.pages
      ..missing = false;
    _applyParsed(t, parsed);
    Db.I.raw.execute('''UPDATE titles SET path=?, root=?, rel_dir=?, file_name=?, size=?, mtime=?,
        fingerprint=?, kind=?, pages=?, missing=0, title=?, alt_title=?, artist=?, circle=?, series_key=?,
        series_base=?, chapter=?, volume=?, year=?, order_prefix=?, source=?, event=?, parody=?,
        language=?, gallery_id=?, extras=?, needs_check=? WHERE id=?''', [
      t.path, t.root, t.relDir, t.fileName, t.size, t.mtime, t.fingerprint, t.kind, t.pages,
      t.title, t.altTitle, t.artist, t.circle, t.seriesKey, t.seriesBase, t.chapter, t.volume,
      t.year, t.orderPrefix, t.source, t.event, t.parody, t.language, t.galleryId, t.extras,
      t.needsCheck ? 1 : 0, t.id,
    ]);
  }

  void _applyParsed(Title t, ParsedName r) {
    t
      ..title = r.title
      ..altTitle = r.altTitle
      ..artist = r.artist
      ..circle = r.circle
      ..seriesKey = r.seriesKey
      ..seriesBase = r.seriesBase
      ..chapter = r.chapter
      ..volume = r.volume
      ..year = r.year
      ..orderPrefix = r.order
      ..source = r.source
      ..event = r.event
      ..parody = r.parody
      ..language = r.language
      ..galleryId = r.galleryId
      ..extras = r.extras.join(' · ')
      ..needsCheck = t.userTitle == null && r.needsCheck;
  }

  String _rel(String root, String path) {
    final r = p.relative(p.dirname(path), from: root);
    return r == '.' ? '' : r;
  }

  Title? _insert(Section s, FileInfo info, String root) {
    final r = parseFor(s, p.basename(info.path));
    final t = Title(
      id: 0,
      uid: newUid(),
      section: s,
      path: info.path,
      root: root,
      relDir: _rel(root, info.path),
      fileName: p.basename(info.path),
      size: info.size,
      mtime: info.mtime,
      fingerprint: info.fingerprint,
      kind: info.kind,
      pages: info.pages,
      title: r.title,
      seriesKey: r.seriesKey,
      seriesBase: r.seriesBase,
      addedAt: nowSec(),
    );
    _applyParsed(t, r);
    try {
      Db.I.raw.execute('''INSERT INTO titles(uid, section, path, root, rel_dir, file_name, size, mtime,
          fingerprint, kind, pages, title, alt_title, artist, circle, series_key, series_base, chapter,
          volume, year, order_prefix, source, event, parody, language, gallery_id, extras, needs_check,
          added_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', [
        t.uid, s.name, t.path, t.root, t.relDir, t.fileName, t.size, t.mtime, t.fingerprint, t.kind,
        t.pages, t.title, t.altTitle, t.artist, t.circle, t.seriesKey, t.seriesBase, t.chapter,
        t.volume, t.year, t.orderPrefix, t.source, t.event, t.parody, t.language, t.galleryId,
        t.extras, t.needsCheck ? 1 : 0, t.addedAt,
      ]);
      t.id = Db.I.raw.lastInsertRowId;
      return t;
    } catch (e) {
      AppLog.I.warn('Couldn\'t add ${t.fileName}: $e');
      return null;
    }
  }

  /// Re-applies the parsing rules to every title (after an update to them).
  void reparse(Section s) {
    Db.I.raw.execute('BEGIN');
    for (final t in _titles[s]!) {
      _applyParsed(t, parseFor(s, t.fileName));
      Db.I.raw.execute('''UPDATE titles SET title=?, alt_title=?, artist=?, circle=?, series_key=?,
        series_base=?, chapter=?, volume=?, year=?, order_prefix=?, source=?, event=?, parody=?,
        language=?, gallery_id=?, extras=?, needs_check=? WHERE id=?''', [
        t.title, t.altTitle, t.artist, t.circle, t.seriesKey, t.seriesBase, t.chapter, t.volume,
        t.year, t.orderPrefix, t.source, t.event, t.parody, t.language, t.galleryId, t.extras,
        t.needsCheck ? 1 : 0, t.id,
      ]);
    }
    Db.I.raw.execute('COMMIT');
    notifyListeners();
  }

  // ---------------- watching ----------------

  void startWatching() {
    for (final w in _watchers) {
      w.cancel();
    }
    _watchers.clear();
    if (!Settings.I.watchFolders) return;
    for (final s in Section.values) {
      for (final root in Settings.I.of(s).folders) {
        if (!Directory(root).existsSync()) continue;
        try {
          _watchers.add(Directory(root).watch(recursive: true).listen((e) {
            final ext = p.extension(e.path).toLowerCase();
            if (ext == '.cbz' || ext == '.cbr' || ext == '.zip' || ext == '.rar' || e.isDirectory) {
              _watchPending.add(s);
              _watchDebounce?.cancel();
              _watchDebounce = Timer(const Duration(seconds: 4), () {
                for (final x in _watchPending) {
                  scan(x, quiet: true);
                }
                _watchPending.clear();
              });
            }
          }, onError: (_) {}));
        } catch (e) {
          AppLog.I.warn('Can\'t watch $root for changes: $e');
        }
      }
    }
  }

  void resetAll() {
    Db.I.resetLibrary();
    load();
  }
}

// Top-level so the background isolate is sent only these arguments.
Future<List<(String, int, int)>> _listInBackground(String root, Set<String> excluded) =>
    Isolate.run(() => Library._listBooks(root, excluded));

Future<List<FileInfo>> _inspectInBackground(List<String> paths, String? sevenZip) =>
    Isolate.run(() => [for (final x in paths) inspectFile(x, sevenZip)]);

/// Cover thumbnails, cached on disk (Cache\thumbs).
///
/// Which covers exist is kept in memory (read from the folder once), so
/// drawing the grid never touches the disk. Covers that couldn't be made are
/// remembered too, so they aren't retried on every redraw.
class Thumbs extends ChangeNotifier {
  Thumbs._();
  static final Thumbs I = Thumbs._();

  /// Set by the UI layer: decodes, scales and encodes one cover.
  Future<Uint8List?> Function(Uint8List bytes)? encoder;
  final Map<String, Future<File?>> _pending = {};
  final Set<String> _have = {};
  final Set<String> _failed = {};
  bool _loaded = false;
  int _running = 0;
  final int _workers = min(6, max(2, Platform.numberOfProcessors ~/ 2));
  final List<(Title, Completer<File?>)> _wait = [];
  int version = 0;

  /// Reads the list of existing covers once, in the background.
  Future<void> loadIndex() async {
    _have.clear();
    final d = Directory(AppPaths.I.thumbs);
    try {
      if (await d.exists()) {
        await for (final f in d.list()) {
          if (f is File) _have.add(p.basename(f.path));
        }
      }
    } catch (_) {}
    _loaded = true;
    version++;
    notifyListeners();
  }

  void forgetAll() {
    _have.clear();
    _failed.clear();
    version++;
    notifyListeners();
  }

  String nameFor(Title t) => '${t.fingerprint}_${t.coverPage}.jpg';
  String fileFor(Title t) => p.join(AppPaths.I.thumbs, nameFor(t));

  File? cached(Title t) => _have.contains(nameFor(t)) ? File(fileFor(t)) : null;
  bool failed(Title t) => _failed.contains(nameFor(t)) || t.unreadable;

  Future<File?> get(Title t) {
    final name = nameFor(t);
    if (_have.contains(name)) return Future.value(File(fileFor(t)));
    if (_failed.contains(name) || t.unreadable || t.missing || !_loaded) return Future.value(null);
    final path = fileFor(t);
    return _pending.putIfAbsent(path, () {
      final c = Completer<File?>();
      _wait.insert(0, (t, c));
      _pump();
      // A block body: returning the removed future here would make it wait on itself.
      return c.future.whenComplete(() {
        _pending.remove(path);
      });
    });
  }

  /// Covers asked for by the grid jump the queue; ones scrolled past are dropped.
  void forgetRequestsExcept(Set<int> visibleIds) {
    _wait.removeWhere((w) {
      if (visibleIds.contains(w.$1.id)) return false;
      w.$2.complete(null);
      return true;
    });
  }

  void _pump() {
    while (_running < _workers && _wait.isNotEmpty) {
      final (t, c) = _wait.removeAt(0);
      _running++;
      _make(t).then((f) {
        if (!c.isCompleted) c.complete(f);
      }).catchError((Object e) {
        if (!c.isCompleted) c.complete(null);
      }).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  Future<File?> _make(Title t) async {
    if (t.missing || encoder == null) return null;
    final name = nameFor(t);
    try {
      final bytes = await readOnePage(t.path, t.coverPage, sevenZip: Library.I.sevenZip, cacheDir: AppPaths.I.pageCache);
      if (bytes == null) {
        _failed.add(name);
        return null;
      }
      final jpg = await encoder!(bytes);
      if (jpg == null) {
        _failed.add(name);
        return null;
      }
      final out = fileFor(t);
      await writeFileSafely(out, jpg);
      _have.add(name);
      version++;
      return File(out);
    } catch (e) {
      _failed.add(name);
      AppLog.I.warn('Couldn\'t make a cover for ${t.fileName}: $e');
      return null;
    }
  }

  /// Background job that makes every missing cover.
  void queueMissing(Section s) {
    final name = 'Making ${s.label} covers';
    if (Jobs.I.isQueued(name)) return;
    final todo = Library.I.titles(s).where((t) => !t.missing && !failed(t) && cached(t) == null).toList();
    if (todo.isEmpty) return;
    Jobs.I.add(Job(name, (job) async {
      job.progress(0, total: todo.length, detail: 'covers');
      var done = 0, made = 0;
      // Several at once, one per worker.
      for (var i = 0; i < todo.length; i += _workers) {
        if (!await job.checkpoint()) break;
        final chunk = todo.sublist(i, min(i + _workers, todo.length));
        final results = await Future.wait(chunk.map(get)); // shared with the grid, so a cover is never made twice at once
        made += results.whereType<File>().length;
        done += chunk.length;
        job.progress(done, detail: chunk.last.displayTitle);
        if (done % 60 < _workers) notifyListeners();
      }
      notifyListeners();
      final failedCount = done - made;
      return '$made ${s.label} covers made${failedCount > 0 ? ' · $failedCount couldn\'t be made (listed in the log)' : ''}';
    }, canPause: true));
  }

  Future<int> cacheSize() async {
    if (!_loaded) await loadIndex();
    var total = 0;
    final d = Directory(AppPaths.I.thumbs);
    if (!await d.exists()) return 0;
    await for (final f in d.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }
}
