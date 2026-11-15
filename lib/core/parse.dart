/// Works out titles, artists and series from file names.
///
/// Pure functions with no I/O, so they're unit tested in `test/parse_test.dart`.
library;

class ParsedName {
  String title = '';
  String? altTitle; // romaji or Japanese title, searchable but not shown
  String? artist;
  String? circle;
  String? event; // (C90)
  String? source; // (Comic Bavel 2025-08)
  String? parody; // (Granblue Fantasy)
  String? language;
  String? galleryId;
  List<String> extras = []; // [Digital], translator groups…
  String seriesBase = ''; // title without chapter numbers
  double? chapter;
  String? volume;
  int? year;
  int? order; // reading-order prefix: "042 - Spider-Woman 009"
  bool needsCheck = false;

  String get seriesKey => normaliseKey('${artist ?? ''}|$seriesBase${volume == null ? '' : '|v$volume'}');
}

final _cjk = RegExp(r'[぀-ヿ㐀-䶿一-鿿가-힯＀-￯]');
final _languages = {
  'english', 'chinese', 'japanese', 'korean', 'spanish', 'french', 'german',
  'russian', 'portuguese', 'italian', 'thai', 'vietnamese', 'indonesian',
  'polish', 'portuguese-br', 'eng', 'jp', 'cn',
};
final _sourceHint = RegExp(
    r'comic|vol\.?\s*\d|#\s*\d|\d{4}-\d{2}|kairakuten|bavel|x-eros|dascomi|europa|angel|isekairakuten|anthurium|high voltage|weekly|magazine|shitsurakuten|beast|megastore|hotmilk|mujin|exe|girls form|anthology',
    caseSensitive: false);
final _galleryTail = RegExp(
    r'\s*-?\s*(?:\[[_.]?\d{4,7}[_.]?\]|\(\d{5,7}\))\s*$');

String normaliseKey(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9぀-鿿|]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String stripExtension(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i <= 0) return fileName;
  final ext = fileName.substring(i + 1).toLowerCase();
  if (ext.length > 4) return fileName;
  return fileName.substring(0, i);
}

/// Manga and doujinshi: `(C90) [Circle (Artist)] Title (Parody) [English] [Group] [_123456_]`.
ParsedName parseManga(String fileName) {
  final r = ParsedName();
  var s = stripExtension(fileName).trim();
  // "Attitude_ Part 1" and "Demon Lord_": an underscore standing in for "?".
  s = s.replaceAllMapped(RegExp(r'(\w)_(?=\s|$)'), (m) => '${m.group(1)}?');
  // Stray closing brackets at the end: "(572948))".
  while (s.endsWith('))') && '('.allMatches(s).length < ')'.allMatches(s).length) {
    s = s.substring(0, s.length - 1);
  }
  // Trailing {tags} and {Doujins.com}.
  for (var guard = 0; guard < 3; guard++) {
    final cb = RegExp(r'\s*\{([^{}]*)\}\s*$').firstMatch(s);
    if (cb == null || cb.start == 0) break;
    r.extras.insert(0, cb.group(1)!.trim());
    s = s.substring(0, cb.start).trim();
  }

  // Gallery numbers at the end, possibly several forms.
  for (var guard = 0; guard < 3; guard++) {
    final m = _galleryTail.firstMatch(s);
    if (m == null) break;
    r.galleryId ??= RegExp(r'\d+').firstMatch(m.group(0)!)!.group(0);
    s = s.substring(0, m.start).trim();
  }
  // Trailing "-[436200]" glued to the title.
  final glued = RegExp(r'-\[(\d{4,7})\]$').firstMatch(s);
  if (glued != null) {
    r.galleryId ??= glued.group(1);
    s = s.substring(0, glued.start).trim();
  }

  // Event prefix: (C90)
  final ev = RegExp(r'^\(([^)]{1,30})\)\s*(?=\[)').firstMatch(s);
  if (ev != null) {
    r.event = ev.group(1);
    s = s.substring(ev.end).trim();
  }

  // Leading [Circle (Artist)] or [Artist]; also the malformed "(Artist)] ".
  final lead = RegExp(r'^\[([^\]]+)\]\s*').firstMatch(s) ??
      RegExp(r'^\(([^()\]]+)\)\]\s*').firstMatch(s);
  if (lead != null) {
    final b = lead.group(1)!.trim();
    final ca = RegExp(r'^(.*?)\s*\(([^)]+)\)\s*$').firstMatch(b);
    if (ca != null && ca.group(1)!.isNotEmpty) {
      r.circle = ca.group(1)!.trim();
      r.artist = ca.group(2)!.trim();
    } else {
      r.artist = b.replaceAll(RegExp(r'\.$'), '').trim();
    }
    s = s.substring(lead.end).trim();
  }

  // Trailing [tags] and (groups), outermost first.
  for (var guard = 0; guard < 12; guard++) {
    final sq = RegExp(r'\s*\[([^\[\]]*)\]\s*$').firstMatch(s);
    final cb = RegExp(r'\s*\{([^{}]*)\}\s*$').firstMatch(s);
    if (cb != null && cb.start > 0) {
      r.extras.insert(0, cb.group(1)!.trim());
      s = s.substring(0, cb.start).trim();
      continue;
    }
    if (sq != null && sq.start > 0) {
      final t = sq.group(1)!.trim();
      if (_languages.contains(t.toLowerCase())) {
        r.language = t;
      } else if (t.isNotEmpty) {
        r.extras.insert(0, t);
      }
      s = s.substring(0, sq.start).trim();
      continue;
    }
    final pr = RegExp(r'\s*\(([^()]*)\)\s*$').firstMatch(s);
    if (pr != null && pr.start > 0) {
      final t = pr.group(1)!.trim();
      if (RegExp(r'^\d{5,7}$').hasMatch(t)) {
        r.galleryId ??= t;
      } else if (_sourceHint.hasMatch(t)) {
        r.source ??= t;
      } else if (RegExp(r'^(decensored|colou?ri[sz]ed|x\d{3,4}|digital|uncensored)$',
              caseSensitive: false)
          .hasMatch(t)) {
        r.extras.insert(0, t);
      } else {
        r.parody ??= t;
      }
      s = s.substring(0, pr.start).trim();
      continue;
    }
    break;
  }
  s = s.replaceAll(RegExp(r'[\s\-–_]+$'), '').trim();

  // Two titles: "Romaji _ English", "Romaji - 中文", "Romaji | English",
  // and "Murasaki No Yume  Purple Dream" (two spaces).
  var parts = s.split(RegExp(r'\s+(?:_|\||｜)\s+'));
  if (parts.length < 2) {
    parts = s.split(RegExp(r'\s{2,}'));
    if (parts.length == 2 && (parts[1].length < 3 || !RegExp(r'[A-Za-z]').hasMatch(parts[1]))) {
      parts = [s];
    }
  }
  if (parts.length >= 2) {
    r.altTitle = parts.first.trim();
    s = parts.sublist(1).join(' ').trim();
  }
  final dash = s.split(RegExp(r'\s+-\s+'));
  if (dash.length >= 2) {
    final keep = dash.where((x) => !_cjk.hasMatch(x)).toList();
    final drop = dash.where((x) => _cjk.hasMatch(x)).toList();
    if (drop.isNotEmpty && keep.isNotEmpty) {
      r.altTitle = drop.join(' - ');
      s = keep.join(' - ');
    }
  }

  // Romaji and English run together with no separator.
  final split = splitRomajiEnglish(s);
  if (split != null) {
    r.altTitle ??= split.$1;
    s = split.$2;
    r.needsCheck = split.$3;
  }

  r.title = s.isEmpty ? stripExtension(fileName) : s;
  _chapters(r);
  return r;
}

void _chapters(ParsedName r) {
  var base = r.title;
  double? ch;
  final chm = RegExp(
          r'\s*[-–:,]?\s*\b(?:Ch(?:apter)?|Episode|Ep|Part|Act)\.?\s*(\d+(?:\.\d+)?)(?:\s*[-~]\s*\d+)?\b\s*',
          caseSensitive: false)
      .firstMatch(base);
  if (chm != null) {
    ch = double.parse(chm.group(1)!);
    base = (base.substring(0, chm.start) + ' ' + base.substring(chm.end)).trim();
  } else {
    final half = RegExp(r'\s*\b(Zenpen|Chuuhen|Kouhen|Kanketsuhen)\b\s*',
            caseSensitive: false)
        .firstMatch(base);
    if (half != null) {
      ch = switch (half.group(1)!.toLowerCase()) {
        'zenpen' => 1,
        'chuuhen' => 2,
        _ => 3,
      };
      base = (base.substring(0, half.start) + ' ' + base.substring(half.end)).trim();
    } else {
      final tail = RegExp(r'\s+(\d{1,2})$').firstMatch(base);
      if (tail != null && tail.start > 0) {
        ch = double.parse(tail.group(1)!);
        base = base.substring(0, tail.start).trim();
      }
    }
  }
  base = base.replaceAll(RegExp(r'[\s\-–:,~]+$'), '').trim();
  r.chapter = ch;
  r.seriesBase = base.isEmpty ? r.title : base;
}

final _romajiWord = RegExp(
    r"^(?:(?:[kgsztdnhbpmyrwfjv]|ch|sh|ts|ky|gy|ny|hy|by|py|my|ry|j|kk|tt|ss|pp|cch)?[aiueoō]+n?|n)+(?:-(?:chan|kun|san|sama|sensei|senpai|chi|tan))?[!?.,…~]*$",
    caseSensitive: false);
const _commonEnglish = {
  'a', 'i', 'me', 'my', 'to', 'no', 'so', 'go', 'do', 'be', 'he', 'we', 'you',
  'one', 'are', 'here', 'more', 'take', 'make', 'made', 'time', 'home',
  'game', 'name', 'same', 'mine', 'line', 'nine', 'wine', 'came', 'come', 'love',
  'some', 'rose', 'use', 'wife', 'life', 'nice', 'naive', 'kiss', 'date',
  'sister', 'mama', 'papa',
};

bool isRomajiWord(String w) {
  final clean = w.replaceAll(RegExp(r"[^A-Za-zō\-!?.,…~']"), '');
  if (clean.isEmpty) return false;
  return _romajiWord.hasMatch(clean);
}

/// Finds where English starts in "Mujintou no Ono-san Ono-san on an uninhabited island".
/// Returns (romaji, english, unsure) or null when there's no clear split.
(String, String, bool)? splitRomajiEnglish(String s) {
  final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length < 4) return null;
  bool romaji(String w) =>
      isRomajiWord(w) && !_commonEnglish.contains(w.toLowerCase());
  bool numberish(String w) => RegExp(r'^[\d.!?~♥❤&+]+$').hasMatch(w);
  // Must start with real romaji.
  var i = 0;
  var romajiCount = 0;
  while (i < words.length && (isRomajiWord(words[i]) || numberish(words[i]))) {
    if (romaji(words[i])) romajiCount++;
    i++;
  }
  if (romajiCount < 2 || i >= words.length || i == words.length) return null;
  // Back up so the split starts on a capitalised English word if possible.
  var cut = i;
  for (var j = i; j > 1; j--) {
    final w = words[j - 1];
    if (_commonEnglish.contains(w.toLowerCase()) ||
        (w.isNotEmpty && w[0] == w[0].toUpperCase() && !romaji(w))) {
      cut = j - 1;
    } else {
      break;
    }
  }
  final rest = words.sublist(cut);
  final english = rest.where((w) => !isRomajiWord(w)).length;
  if (rest.length < 2 || english < 1) return null;
  if (english / rest.length < 0.34) return null;
  final unsure = english / rest.length < 0.6 || cut < 2;
  return (words.sublist(0, cut).join(' '), rest.join(' '), unsure);
}

/// Comics: `Ultimate_Spider-Man_068_(2005)_(digital)_(Son_of_Ultron-Empire)`,
/// `042 - Spider-Woman 009`, `The Amazing Spider-Man v2 - 478 - 37`.
ParsedName parseComic(String fileName) {
  final r = ParsedName();
  var s = stripExtension(fileName).replaceAll('_', ' ').trim();
  final ord = RegExp(r'^(\d{2,4})\s*-\s+').firstMatch(s);
  if (ord != null) {
    r.order = int.parse(ord.group(1)!);
    s = s.substring(ord.end).trim();
  }
  // Remove trailing (…) and […] groups, picking up the year.
  for (var guard = 0; guard < 10; guard++) {
    final m = RegExp(r'\s*[\(\[]([^()\[\]]*)[\)\]]\s*$').firstMatch(s);
    if (m == null || m.start == 0) break;
    final t = m.group(1)!.trim();
    final y = RegExp(r'^(?:19|20)\d{2}$').firstMatch(t);
    if (y != null) {
      r.year = int.parse(t);
    } else if (t.isNotEmpty) {
      r.extras.insert(0, t);
    }
    s = s.substring(0, m.start).trim();
  }
  final vol = RegExp(r'\bv(?:ol\.?\s*)?(\d{1,2})\b', caseSensitive: false).firstMatch(s);
  String head = s;
  String tail = '';
  if (vol != null) {
    r.volume = vol.group(1);
    head = s.substring(0, vol.start).trim();
    tail = s.substring(vol.end).trim();
  }
  final searchIn = vol != null ? tail : s;
  final iss = RegExp(r'(?:^|[\s\-#]+)#?(\d{1,4}(?:\.\d+)?)(?=\s|$|-)').firstMatch(searchIn);
  if (iss != null) {
    r.chapter = double.parse(iss.group(1)!);
    if (vol == null) head = s.substring(0, iss.start).trim();
  }
  head = head.replaceAll(RegExp(r'[\s\-–#:]+$'), '').trim();
  r.seriesBase = head.isEmpty ? s : head;
  final issueText = r.chapter == null
      ? ''
      : ' #${r.chapter! == r.chapter!.roundToDouble() ? r.chapter!.toInt().toString().padLeft(3, '0') : r.chapter}';
  r.title = r.chapter == null && vol == null
      ? s
      : '${r.seriesBase}${r.volume != null ? ' v${r.volume}' : ''}$issueText';
  return r;
}

/// Art books: the name tidied, with a leading [Artist] if there is one.
ParsedName parseArtBook(String fileName) {
  final r = ParsedName();
  var s = stripExtension(fileName).replaceAll('_', ' ').trim();
  final lead = RegExp(r'^\[([^\]]+)\]\s*').firstMatch(s);
  if (lead != null) {
    r.artist = lead.group(1)!.trim();
    s = s.substring(lead.end).trim();
  }
  // Japanese title in trailing brackets becomes the alt title.
  final tailJp = RegExp(r'\s*\[([^\]]*)\]\s*$').firstMatch(s);
  if (tailJp != null && tailJp.start > 0 && _cjk.hasMatch(tailJp.group(1)!)) {
    r.altTitle = tailJp.group(1);
    s = s.substring(0, tailJp.start).trim();
  }
  r.title = s;
  r.seriesBase = s;
  final vol = RegExp(r'\b(?:Vol(?:ume)?\.?\s*|Archive\s+)([IVX]+|\d+)\b', caseSensitive: false)
      .firstMatch(s);
  if (vol != null) {
    r.seriesBase = s.substring(0, vol.start).trim();
  }
  return r;
}

/// Natural order: "2" before "10", "042 -" before "043 -", case ignored.
int naturalCompare(String a, String b) {
  final ra = RegExp(r'(\d+)|(\D+)');
  final ta = ra.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final tb = ra.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ta.length && i < tb.length; i++) {
    final x = ta[i], y = tb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    int c;
    if (nx != null && ny != null) {
      c = nx.compareTo(ny);
      if (c == 0) c = x.length.compareTo(y.length);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  return ta.length.compareTo(tb.length);
}
