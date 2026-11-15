import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';
import 'jobs.dart';
import 'library.dart';
import 'log.dart';
import 'settings.dart';

/// One-time import from YACReader libraries (`.yacreaderlibrary\library.ydb`).
class YacImport {
  static List<(Section, String)> findLibraries() {
    final out = <(Section, String)>[];
    for (final s in Section.values) {
      for (final root in Settings.I.of(s).folders) {
        final db = p.join(root, '.yacreaderlibrary', 'library.ydb');
        if (File(db).existsSync()) out.add((s, root));
      }
    }
    return out;
  }

  static void queue() {
    final libs = findLibraries();
    if (libs.isEmpty) return;
    Jobs.I.add(Job('Importing from YACReader', (job) async {
      var matched = 0, unmatched = 0, reads = 0, ratings = 0, favs = 0, tags = 0;
      final missingNames = <String>[];
      job.progress(0, total: libs.length);
      var i = 0;
      for (final (section, root) in libs) {
        if (!await job.checkpoint()) break;
        job.setDetail(root);
        final r = _importOne(section, root, missingNames);
        matched += r.$1;
        unmatched += r.$2;
        reads += r.$3;
        ratings += r.$4;
        favs += r.$5;
        tags += r.$6;
        job.progress(++i);
      }
      for (final n in missingNames.take(200)) {
        AppLog.I.info('YACReader: not in the library: $n');
      }
      Library.I.load();
      return 'YACReader import: $matched matched · $reads read · $ratings rated · $favs favourites · $tags tag links'
          '${unmatched > 0 ? ' · $unmatched not found (listed in the log)' : ''}';
    }));
  }

  static Set<String> _columns(Database d, String table) {
    try {
      return d.select('PRAGMA table_info($table)').map((r) => r['name'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  static (int, int, int, int, int, int) _importOne(Section s, String root, List<String> missingNames) {
    final path = p.join(root, '.yacreaderlibrary', 'library.ydb');
    final d = sqlite3.open(path, mode: OpenMode.readOnly);
    var matched = 0, unmatched = 0, reads = 0, ratings = 0, favs = 0, tagLinks = 0;
    try {
      final byPath = {
        for (final t in Library.I.titles(s)) p.normalize(t.path).toLowerCase(): t,
      };
      final infoCols = _columns(d, 'comic_info');
      final hasLast = infoCols.contains('lastTimeOpened');
      final rows = d.select(
          'SELECT c.id AS cid, c.path AS path, i.read AS read, i.currentPage AS page, i.rating AS rating'
          '${hasLast ? ', i.lastTimeOpened AS last' : ''} FROM comic c JOIN comic_info i ON i.id = c.comicInfoId');
      final byComic = <int, Title>{};
      Db.I.raw.execute('BEGIN');
      for (final r in rows) {
        final rel = (r['path'] as String).replaceAll('/', p.separator);
        final full = p.normalize(p.join(root, rel.startsWith(p.separator) ? rel.substring(1) : rel));
        final t = byPath[full.toLowerCase()];
        if (t == null) {
          unmatched++;
          missingNames.add(full);
          continue;
        }
        matched++;
        byComic[r['cid'] as int] = t;
        final read = (r['read'] as int? ?? 0) == 1;
        final page = (r['page'] as int? ?? 1) - 1;
        final ratingRaw = (r['rating'] as num?)?.toDouble() ?? 0;
        final last = hasLast ? (r['last'] as int? ?? 0) : 0;
        if (read && t.readCount == 0) {
          Db.I.addCompletion(t.id, last, source: 'yacreader');
          t.readCount = 1;
          t.firstCompletedAt = last;
          t.lastCompletedAt = last;
          reads++;
        } else if (!read && page > 0 && t.lastPage == 0) {
          t.lastPage = page.clamp(0, t.pages > 0 ? t.pages - 1 : 0);
        }
        if (last > t.lastReadAt) t.lastReadAt = last;
        if (ratingRaw > 0 && t.rating == 0) {
          t.rating = ratingRaw > 5 ? (ratingRaw / 2).clamp(0.5, 5) : ratingRaw;
          ratings++;
        }
        Db.I.updateReading(t);
        Db.I.raw.execute('UPDATE titles SET yac_imported=1 WHERE id=?', [t.id]);
      }
      Db.I.raw.execute('COMMIT');

      // Favourites: YACReader's default list 1.
      try {
        for (final r in d.select(
            'SELECT comic_id FROM comic_default_reading_list WHERE default_reading_list_id = 1')) {
          final t = byComic[r['comic_id'] as int];
          if (t != null && !t.favourite) {
            t.favourite = true;
            Db.I.updateReading(t);
            favs++;
          }
        }
      } catch (_) {}

      // Labels and reading lists become tags.
      Tag tagNamed(String name) {
        final existing = Library.I.tags(s).where((x) => x.name.toLowerCase() == name.toLowerCase());
        return existing.isNotEmpty ? existing.first : Library.I.createTag(s, name);
      }

      void link(String listSql, String memberSql) {
        try {
          for (final l in d.select(listSql)) {
            final tag = tagNamed(l['name'] as String);
            final members = d
                .select(memberSql, [l['id']])
                .map((m) => byComic[m['comic_id'] as int])
                .whereType<Title>()
                .toList();
            if (members.isNotEmpty) {
              Library.I.addTag(tag, members);
              tagLinks += members.length;
            }
          }
        } catch (_) {}
      }

      link('SELECT id, name FROM label', 'SELECT comic_id FROM comic_label WHERE label_id = ? ORDER BY ordering');
      link('SELECT id, name FROM reading_list',
          'SELECT comic_id FROM comic_reading_list WHERE reading_list_id = ? ORDER BY ordering');
    } catch (e) {
      try {
        Db.I.raw.execute('ROLLBACK');
      } catch (_) {}
      AppLog.I.error('YACReader import from $root failed', e);
    } finally {
      d.dispose();
    }
    return (matched, unmatched, reads, ratings, favs, tagLinks);
  }
}
