import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'log.dart';
import 'paths.dart';
import 'settings.dart';

const _uuid = Uuid();
String newUid() => _uuid.v4();
int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// One file in the library.
class Title {
  int id;
  String uid;
  Section section;
  String path;
  String root; // the library folder it was found under
  String relDir; // folder relative to root ('' at the top)
  String fileName;
  int size;
  int mtime;
  String fingerprint;
  String kind; // zip | rar
  int pages;
  String title;
  String? altTitle;
  String? artist;
  String? circle;
  String seriesKey;
  String seriesBase;
  double? chapter;
  String? volume;
  int? year;
  int? orderPrefix;
  String? source;
  String? event;
  String? parody;
  String? language;
  String? galleryId;
  String extras;
  bool needsCheck;
  // Hand edits win over parsing and survive rescans.
  String? userTitle;
  String? userArtist;
  String? userSeries;
  double? userChapter;
  int coverPage;
  int addedAt;
  bool missing;
  double rating; // 0 = not rated; 0.5 … 5
  bool favourite;
  int lastPage;
  int lastReadAt;
  int firstCompletedAt;
  int lastCompletedAt;
  int readCount;
  int timeSpent; // seconds of active reading
  bool manualRead; // marked read by hand with no real reading
  String? direction; // per-title override
  bool? coverOffset;
  bool? crop;

  Title({
    required this.id,
    required this.uid,
    required this.section,
    required this.path,
    required this.root,
    required this.relDir,
    required this.fileName,
    required this.size,
    required this.mtime,
    required this.fingerprint,
    required this.kind,
    required this.pages,
    required this.title,
    this.altTitle,
    this.artist,
    this.circle,
    required this.seriesKey,
    required this.seriesBase,
    this.chapter,
    this.volume,
    this.year,
    this.orderPrefix,
    this.source,
    this.event,
    this.parody,
    this.language,
    this.galleryId,
    this.extras = '',
    this.needsCheck = false,
    this.userTitle,
    this.userArtist,
    this.userSeries,
    this.userChapter,
    this.coverPage = 0,
    required this.addedAt,
    this.missing = false,
    this.rating = 0,
    this.favourite = false,
    this.lastPage = 0,
    this.lastReadAt = 0,
    this.firstCompletedAt = 0,
    this.lastCompletedAt = 0,
    this.readCount = 0,
    this.timeSpent = 0,
    this.manualRead = false,
    this.direction,
    this.coverOffset,
    this.crop,
  });

  String get displayTitle => userTitle ?? title;
  String? get displayArtist => userArtist ?? artist;
  String get displaySeries => userSeries ?? seriesBase;
  double? get displayChapter => userChapter ?? chapter;
  String get groupKey => userSeries != null
      ? '${(displayArtist ?? '').toLowerCase()}|${userSeries!.toLowerCase()}'
      : seriesKey;
  bool get isRead => readCount > 0;
  bool get inProgress => readCount == 0 && lastPage > 0;
  double get progress => pages <= 0
      ? 0
      : isRead && lastPage == 0
          ? 1
          : ((lastPage + 1) / pages).clamp(0.0, 1.0);

  static Title fromRow(Row r) => Title(
        id: r['id'] as int,
        uid: r['uid'] as String,
        section: Section.byName(r['section'] as String),
        path: r['path'] as String,
        root: r['root'] as String,
        relDir: r['rel_dir'] as String,
        fileName: r['file_name'] as String,
        size: r['size'] as int,
        mtime: r['mtime'] as int,
        fingerprint: r['fingerprint'] as String,
        kind: r['kind'] as String,
        pages: r['pages'] as int,
        title: r['title'] as String,
        altTitle: r['alt_title'] as String?,
        artist: r['artist'] as String?,
        circle: r['circle'] as String?,
        seriesKey: r['series_key'] as String,
        seriesBase: r['series_base'] as String,
        chapter: (r['chapter'] as num?)?.toDouble(),
        volume: r['volume'] as String?,
        year: r['year'] as int?,
        orderPrefix: r['order_prefix'] as int?,
        source: r['source'] as String?,
        event: r['event'] as String?,
        parody: r['parody'] as String?,
        language: r['language'] as String?,
        galleryId: r['gallery_id'] as String?,
        extras: r['extras'] as String? ?? '',
        needsCheck: (r['needs_check'] as int? ?? 0) == 1,
        userTitle: r['user_title'] as String?,
        userArtist: r['user_artist'] as String?,
        userSeries: r['user_series'] as String?,
        userChapter: (r['user_chapter'] as num?)?.toDouble(),
        coverPage: r['cover_page'] as int? ?? 0,
        addedAt: r['added_at'] as int,
        missing: (r['missing'] as int? ?? 0) == 1,
        rating: (r['rating'] as num?)?.toDouble() ?? 0,
        favourite: (r['favourite'] as int? ?? 0) == 1,
        lastPage: r['last_page'] as int? ?? 0,
        lastReadAt: r['last_read_at'] as int? ?? 0,
        firstCompletedAt: r['first_completed_at'] as int? ?? 0,
        lastCompletedAt: r['last_completed_at'] as int? ?? 0,
        readCount: r['read_count'] as int? ?? 0,
        timeSpent: r['time_spent'] as int? ?? 0,
        manualRead: (r['manual_read'] as int? ?? 0) == 1,
        direction: r['direction'] as String?,
        coverOffset: r['cover_offset'] == null ? null : (r['cover_offset'] as int) == 1,
        crop: r['crop'] == null ? null : (r['crop'] as int) == 1,
      );
}

class ReadingSession {
  final int id;
  final int titleId;
  final int startedAt;
  final int endedAt;
  final int activeSeconds;
  final int fromPage;
  final int toPage;
  final int pagesSeen;
  final bool completed;
  final String device;
  final String source;
  ReadingSession(this.id, this.titleId, this.startedAt, this.endedAt, this.activeSeconds,
      this.fromPage, this.toPage, this.pagesSeen, this.completed, this.device, this.source);
}

class Tag {
  int id;
  Section section;
  String name;
  int color;
  int sortIndex;
  String innerSort; // manual | any sort key
  Tag(this.id, this.section, this.name, this.color, this.sortIndex, this.innerSort);
}

class SavedPage {
  final int id;
  final int titleId;
  final String pages;
  final String imageHash;
  final int at;
  final String path;
  SavedPage(this.id, this.titleId, this.pages, this.imageHash, this.at, this.path);
}

/// The library database (SQLite, in the data folder).
class Db {
  Db._(this.raw);
  static late Db I;
  final Database raw;

  static Db open(String path) {
    Directory(p.dirname(path)).createSync(recursive: true);
    final d = sqlite3.open(path);
    d.execute('PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON;');
    final db = Db._(d);
    db._migrate();
    return db;
  }

  void _migrate() {
    final v = raw.select('PRAGMA user_version').first.values.first as int;
    if (v < 1) {
      raw.execute('''
CREATE TABLE IF NOT EXISTS titles(
  id INTEGER PRIMARY KEY, uid TEXT NOT NULL, section TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE, root TEXT NOT NULL, rel_dir TEXT NOT NULL, file_name TEXT NOT NULL,
  size INTEGER NOT NULL, mtime INTEGER NOT NULL, fingerprint TEXT NOT NULL, kind TEXT NOT NULL,
  pages INTEGER NOT NULL DEFAULT 0, title TEXT NOT NULL, alt_title TEXT, artist TEXT, circle TEXT,
  series_key TEXT NOT NULL, series_base TEXT NOT NULL, chapter REAL, volume TEXT, year INTEGER,
  order_prefix INTEGER, source TEXT, event TEXT, parody TEXT, language TEXT, gallery_id TEXT,
  extras TEXT, needs_check INTEGER DEFAULT 0,
  user_title TEXT, user_artist TEXT, user_series TEXT, user_chapter REAL,
  cover_page INTEGER DEFAULT 0, added_at INTEGER NOT NULL, missing INTEGER DEFAULT 0,
  rating REAL DEFAULT 0, favourite INTEGER DEFAULT 0, last_page INTEGER DEFAULT 0,
  last_read_at INTEGER DEFAULT 0, first_completed_at INTEGER DEFAULT 0,
  last_completed_at INTEGER DEFAULT 0, read_count INTEGER DEFAULT 0, time_spent INTEGER DEFAULT 0,
  manual_read INTEGER DEFAULT 0, direction TEXT, cover_offset INTEGER, crop INTEGER,
  yac_imported INTEGER DEFAULT 0, updated_at INTEGER DEFAULT 0);
CREATE INDEX IF NOT EXISTS titles_fp ON titles(fingerprint);
CREATE INDEX IF NOT EXISTS titles_section ON titles(section);
CREATE TABLE IF NOT EXISTS sessions(
  id INTEGER PRIMARY KEY, uid TEXT NOT NULL, title_id INTEGER NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
  started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, active_seconds INTEGER NOT NULL,
  from_page INTEGER, to_page INTEGER, pages_seen INTEGER, completed INTEGER DEFAULT 0,
  device TEXT DEFAULT 'PC', source TEXT DEFAULT 'pc');
CREATE INDEX IF NOT EXISTS sessions_title ON sessions(title_id);
CREATE TABLE IF NOT EXISTS completions(
  id INTEGER PRIMARY KEY, uid TEXT NOT NULL, title_id INTEGER NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
  at INTEGER NOT NULL, manual INTEGER DEFAULT 0, source TEXT DEFAULT 'pc');
CREATE INDEX IF NOT EXISTS completions_title ON completions(title_id);
CREATE TABLE IF NOT EXISTS tags(
  id INTEGER PRIMARY KEY, section TEXT NOT NULL, name TEXT NOT NULL, color INTEGER NOT NULL,
  sort_index INTEGER NOT NULL, inner_sort TEXT NOT NULL DEFAULT 'manual');
CREATE TABLE IF NOT EXISTS title_tags(
  tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  title_id INTEGER NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
  position INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(tag_id, title_id));
CREATE TABLE IF NOT EXISTS saved_pages(
  id INTEGER PRIMARY KEY, title_id INTEGER, pages TEXT NOT NULL, image_hash TEXT NOT NULL,
  at INTEGER NOT NULL, path TEXT NOT NULL, format TEXT);
CREATE INDEX IF NOT EXISTS saved_hash ON saved_pages(image_hash);
CREATE TABLE IF NOT EXISTS changes(
  id INTEGER PRIMARY KEY, uid TEXT NOT NULL, at INTEGER NOT NULL, kind TEXT NOT NULL,
  title_uid TEXT, payload TEXT);
PRAGMA user_version = 1;
''');
    }
  }

  // ---------- titles ----------

  List<Title> titles(Section s) => raw
      .select('SELECT * FROM titles WHERE section = ?', [s.name])
      .map(Title.fromRow)
      .toList();

  List<Title> allTitles() =>
      raw.select('SELECT * FROM titles').map(Title.fromRow).toList();

  Title? titleById(int id) {
    final r = raw.select('SELECT * FROM titles WHERE id = ?', [id]);
    return r.isEmpty ? null : Title.fromRow(r.first);
  }

  void updateReading(Title t) {
    raw.execute('''UPDATE titles SET rating=?, favourite=?, last_page=?, last_read_at=?,
      first_completed_at=?, last_completed_at=?, read_count=?, time_spent=?, manual_read=?,
      direction=?, cover_offset=?, crop=?, updated_at=? WHERE id=?''', [
      t.rating,
      t.favourite ? 1 : 0,
      t.lastPage,
      t.lastReadAt,
      t.firstCompletedAt,
      t.lastCompletedAt,
      t.readCount,
      t.timeSpent,
      t.manualRead ? 1 : 0,
      t.direction,
      t.coverOffset == null ? null : (t.coverOffset! ? 1 : 0),
      t.crop == null ? null : (t.crop! ? 1 : 0),
      nowSec(),
      t.id,
    ]);
  }

  void updateEdits(Title t) {
    raw.execute('''UPDATE titles SET user_title=?, user_artist=?, user_series=?, user_chapter=?,
      cover_page=?, needs_check=?, updated_at=? WHERE id=?''', [
      t.userTitle,
      t.userArtist,
      t.userSeries,
      t.userChapter,
      t.coverPage,
      t.needsCheck ? 1 : 0,
      nowSec(),
      t.id,
    ]);
  }

  // ---------- reading records ----------

  void addSession({
    required int titleId,
    required int startedAt,
    required int endedAt,
    required int activeSeconds,
    required int fromPage,
    required int toPage,
    required int pagesSeen,
    required bool completed,
    String device = 'PC',
    String source = 'pc',
  }) {
    raw.execute(
        '''INSERT INTO sessions(uid,title_id,started_at,ended_at,active_seconds,from_page,to_page,
        pages_seen,completed,device,source) VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
        [newUid(), titleId, startedAt, endedAt, activeSeconds, fromPage, toPage, pagesSeen,
          completed ? 1 : 0, device, source]);
  }

  void addCompletion(int titleId, int at, {bool manual = false, String source = 'pc'}) {
    raw.execute('INSERT INTO completions(uid,title_id,at,manual,source) VALUES(?,?,?,?,?)',
        [newUid(), titleId, at, manual ? 1 : 0, source]);
  }

  void removeManualCompletions(int titleId) {
    raw.execute('DELETE FROM completions WHERE title_id=? AND manual=1', [titleId]);
  }

  List<ReadingSession> sessions({Section? section, int? titleId}) {
    final where = <String>[];
    final args = <Object?>[];
    if (section != null) {
      where.add('t.section = ?');
      args.add(section.name);
    }
    if (titleId != null) {
      where.add('s.title_id = ?');
      args.add(titleId);
    }
    final sql = 'SELECT s.* FROM sessions s JOIN titles t ON t.id = s.title_id'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY s.started_at DESC';
    return raw
        .select(sql, args)
        .map((r) => ReadingSession(
            r['id'] as int,
            r['title_id'] as int,
            r['started_at'] as int,
            r['ended_at'] as int,
            r['active_seconds'] as int,
            r['from_page'] as int? ?? 0,
            r['to_page'] as int? ?? 0,
            r['pages_seen'] as int? ?? 0,
            (r['completed'] as int? ?? 0) == 1,
            r['device'] as String? ?? 'PC',
            r['source'] as String? ?? 'pc'))
        .toList();
  }

  List<(int titleId, int at, bool manual, String source)> completions({Section? section, int? titleId}) {
    final where = <String>[];
    final args = <Object?>[];
    if (section != null) {
      where.add('t.section = ?');
      args.add(section.name);
    }
    if (titleId != null) {
      where.add('c.title_id = ?');
      args.add(titleId);
    }
    return raw
        .select(
            'SELECT c.* FROM completions c JOIN titles t ON t.id = c.title_id'
            '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY c.at DESC',
            args)
        .map((r) => (
              r['title_id'] as int,
              r['at'] as int,
              (r['manual'] as int? ?? 0) == 1,
              r['source'] as String? ?? 'pc'
            ))
        .toList();
  }

  void deleteSession(int id) => raw.execute('DELETE FROM sessions WHERE id=?', [id]);
  void deleteSessionsFor(int titleId) =>
      raw.execute('DELETE FROM sessions WHERE title_id=?', [titleId]);
  void deleteAllHistory(Section? s) {
    if (s == null) {
      raw.execute('DELETE FROM sessions');
    } else {
      raw.execute(
          'DELETE FROM sessions WHERE title_id IN (SELECT id FROM titles WHERE section=?)', [s.name]);
    }
  }

  // ---------- tags ----------

  List<Tag> tags(Section s) => raw
      .select('SELECT * FROM tags WHERE section=? ORDER BY sort_index, name', [s.name])
      .map((r) => Tag(r['id'] as int, Section.byName(r['section'] as String), r['name'] as String,
          r['color'] as int, r['sort_index'] as int, r['inner_sort'] as String))
      .toList();

  Tag createTag(Section s, String name, int color) {
    final idx = (raw.select('SELECT COALESCE(MAX(sort_index),0)+1 AS n FROM tags WHERE section=?',
            [s.name]).first['n'] as int);
    raw.execute('INSERT INTO tags(section,name,color,sort_index) VALUES(?,?,?,?)',
        [s.name, name, color, idx]);
    return Tag(raw.lastInsertRowId, s, name, color, idx, 'manual');
  }

  void updateTag(Tag t) => raw.execute(
      'UPDATE tags SET name=?, color=?, sort_index=?, inner_sort=? WHERE id=?',
      [t.name, t.color, t.sortIndex, t.innerSort, t.id]);
  void deleteTag(int id) => raw.execute('DELETE FROM tags WHERE id=?', [id]);

  /// title id -> tag ids
  Map<int, Set<int>> tagMap(Section s) {
    final m = <int, Set<int>>{};
    for (final r in raw.select(
        'SELECT tt.title_id, tt.tag_id FROM title_tags tt JOIN tags g ON g.id = tt.tag_id WHERE g.section=?',
        [s.name])) {
      m.putIfAbsent(r['title_id'] as int, () => {}).add(r['tag_id'] as int);
    }
    return m;
  }

  List<int> tagMembers(int tagId) => raw
      .select('SELECT title_id FROM title_tags WHERE tag_id=? ORDER BY position', [tagId])
      .map((r) => r['title_id'] as int)
      .toList();

  void addToTag(int tagId, Iterable<int> titleIds) {
    var pos = raw.select('SELECT COALESCE(MAX(position),0) AS n FROM title_tags WHERE tag_id=?',
        [tagId]).first['n'] as int;
    final st = raw.prepare(
        'INSERT OR IGNORE INTO title_tags(tag_id,title_id,position) VALUES(?,?,?)');
    for (final id in titleIds) {
      st.execute([tagId, id, ++pos]);
    }
    st.close();
  }

  void removeFromTag(int tagId, Iterable<int> titleIds) {
    for (final id in titleIds) {
      raw.execute('DELETE FROM title_tags WHERE tag_id=? AND title_id=?', [tagId, id]);
    }
  }

  void reorderTag(int tagId, List<int> titleIds) {
    raw.execute('BEGIN');
    for (var i = 0; i < titleIds.length; i++) {
      raw.execute('UPDATE title_tags SET position=? WHERE tag_id=? AND title_id=?',
          [i + 1, tagId, titleIds[i]]);
    }
    raw.execute('COMMIT');
  }

  // ---------- saved pages ----------

  SavedPage? savedByHash(String hash) {
    final r = raw.select('SELECT * FROM saved_pages WHERE image_hash=? LIMIT 1', [hash]);
    if (r.isEmpty) return null;
    final x = r.first;
    return SavedPage(x['id'] as int, x['title_id'] as int? ?? 0, x['pages'] as String,
        x['image_hash'] as String, x['at'] as int, x['path'] as String);
  }

  Set<String> savedHashes() =>
      raw.select('SELECT image_hash FROM saved_pages').map((r) => r['image_hash'] as String).toSet();

  void addSaved(int titleId, String pages, String hash, String path, String format) =>
      raw.execute('INSERT INTO saved_pages(title_id,pages,image_hash,at,path,format) VALUES(?,?,?,?,?,?)',
          [titleId, pages, hash, nowSec(), path, format]);

  List<SavedPage> savedPages(Section s) => raw
      .select(
          'SELECT sp.* FROM saved_pages sp JOIN titles t ON t.id = sp.title_id WHERE t.section=? ORDER BY sp.at DESC',
          [s.name])
      .map((x) => SavedPage(x['id'] as int, x['title_id'] as int? ?? 0, x['pages'] as String,
          x['image_hash'] as String, x['at'] as int, x['path'] as String))
      .toList();

  void forgetSaved(int id) => raw.execute('DELETE FROM saved_pages WHERE id=?', [id]);

  // ---------- maintenance ----------

  /// Keeps the last few copies of the database, since it holds all history.
  void backup(String dir) {
    try {
      Directory(dir).createSync(recursive: true);
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final target = p.join(dir, 'library-$stamp.db');
      if (File(target).existsSync()) return;
      raw.execute("VACUUM INTO '${target.replaceAll("'", "''")}'");
      final files = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('library-'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(7)) {
        f.deleteSync();
      }
    } catch (e) {
      AppLog.I.warn('Couldn\'t back up the library database: $e');
    }
  }

  void resetLibrary() {
    raw.execute('DELETE FROM title_tags; DELETE FROM sessions; DELETE FROM completions; DELETE FROM titles;');
  }

  void resetHistory() {
    raw.execute(
        'DELETE FROM sessions; DELETE FROM completions; UPDATE titles SET last_page=0,last_read_at=0,first_completed_at=0,last_completed_at=0,read_count=0,time_spent=0,manual_read=0;');
  }

  void resetSaved() => raw.execute('DELETE FROM saved_pages');

  void close() => raw.dispose();

  static String get defaultPath => AppPaths.I.db;
}
