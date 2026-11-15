// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../core/archives.dart';
import '../core/db.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/savepage.dart';
import '../core/settings.dart';
import 'library_page.dart';
import 'widgets.dart';

/// One piece of a view: a page, or one half of a split spread.
class Part {
  const Part(this.page, [this.half = 0]);
  final int page;
  final int half; // 0 whole, 1 left half, 2 right half
  @override
  bool operator ==(Object o) => o is Part && o.page == page && o.half == half;
  @override
  int get hashCode => page * 3 + half;
}

/// What's on screen at once: one or two parts, left to right.
class View {
  const View(this.parts);
  final List<Part> parts;
  Iterable<int> get pages => parts.map((x) => x.page);
}

/// Lets the self-test drive the open reader.
abstract class ReaderControl {
  static ReaderControl? active;
  void next();
  Future<void> saveCurrent({bool both = true});
  List<List<int>> get layout;
  int get position;
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.title, required this.queue, this.startPage});
  final Title title;
  final List<Title> queue;
  final int? startPage;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> implements ReaderControl {
  late Title t;
  Book? book;
  String? error;
  int get n => book?.length ?? 0;

  // Page data
  final Map<int, Uint8List> bytes = {};
  final Map<int, (int, int)> dims = {};
  final Map<int, ui.Image> images = {};
  final Map<int, Rect> crops = {};
  final Map<int, ui.Image> strip = {};
  final Map<int, String> hashes = {};
  final Set<int> failed = {};
  final Set<int> _decoding = {};
  int _bytesTotal = 0;
  int _loaderGen = 0;
  Set<String> savedHashes = {};

  // Layout
  List<View> views = [];
  int pos = 0; // index into views; views.length = end screen
  int anchorPage = 0;

  // Session
  late int sessionStart;
  int activeSeconds = 0;
  DateTime lastInput = DateTime.now();
  final Set<int> seen = {};
  int fromPage = 0;
  bool completedThisSession = false;
  Timer? _tick;

  // UI
  bool ui_ = false;
  bool showStrip = false;
  double zoom = 1;
  Offset pan = Offset.zero;
  Size viewport = Size.zero;
  final ScrollController stripScroll = ScrollController();
  final ScrollController vScroll = ScrollController();
  final FocusNode focus = FocusNode(debugLabel: 'reader');

  SectionSettings get ss => Settings.I.of(t.section);
  ReadDirection get direction =>
      ReadDirection.values.firstWhere((d) => d.name == t.direction, orElse: () => ss.direction);
  bool get coverOffset => t.coverOffset ?? ss.coverOffset;
  bool get crop => t.crop ?? ss.crop;
  bool get stripMode => direction == ReadDirection.ttb && ss.verticalStyle == VerticalStyle.strip;
  bool get doublePage {
    if (direction == ReadDirection.ttb) return false;
    return switch (ss.layout) {
      PageLayout.single => false,
      PageLayout.double => true,
      PageLayout.auto => viewport.width > viewport.height * 1.2,
    };
  }

  bool get splitActive => switch (ss.split) {
        SplitMode.off => false,
        SplitMode.split => true,
        SplitMode.singleOnly => !doublePage,
      };

  @override
  List<List<int>> get layout => [for (final v in views) v.parts.map((x) => x.page * 10 + x.half).toList()];
  @override
  int get position => pos;

  @override
  Future<void> saveCurrent({bool both = true}) async {
    final view = pos < views.length ? views[pos] : null;
    if (view == null) return;
    final pp = <PagePart>[];
    for (final x in both ? view.parts : [view.parts.first]) {
      final b = await _bytesFor(x.page);
      if (b == null) return;
      pp.add(PagePart(x.page, b, p.extension(book!.pageNames[x.page]), half: x.half));
    }
    final r = await PageSaver.save(title: t, parts: pp);
    if (r is SaveFailed) AppLog.I.warn(r.message);
    savedHashes = Db.I.savedHashes();
  }

  @override
  void initState() {
    super.initState();
    ReaderControl.active = this;
    savedHashes = Db.I.savedHashes();
    _openTitle(widget.title, widget.startPage);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(lastInput).inMinutes < Settings.I.idleMinutes) activeSeconds++;
    });
  }

  @override
  void dispose() {
    if (ReaderControl.active == this) ReaderControl.active = null;
    _endSession();
    _tick?.cancel();
    book?.close();
    for (final im in images.values) {
      im.dispose();
    }
    for (final im in strip.values) {
      im.dispose();
    }
    stripScroll.dispose();
    vScroll.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _openTitle(Title title, int? startPage) async {
    t = title;
    _loaderGen++;
    book?.close();
    book = null;
    error = null;
    for (final im in images.values) {
      im.dispose();
    }
    for (final im in strip.values) {
      im.dispose();
    }
    bytes.clear();
    dims.clear();
    images.clear();
    crops.clear();
    strip.clear();
    hashes.clear();
    failed.clear();
    _decoding.clear();
    _bytesTotal = 0;
    views = [];
    pos = 0;
    zoom = 1;
    pan = Offset.zero;
    sessionStart = nowSec();
    activeSeconds = 0;
    seen.clear();
    completedThisSession = false;
    lastInput = DateTime.now();
    setState(() {});
    try {
      final b = await Book.open(t.path, cacheDir: AppPaths.I.pageCache, sevenZip: Library.I.sevenZip);
      if (!mounted) return;
      book = b;
      if (b.length == 0) {
        error = 'This file has no pages Shiori can show.';
      }
      if (b.length != t.pages) {
        t.pages = b.length;
        Db.I.raw.execute('UPDATE titles SET pages=? WHERE id=?', [t.pages, t.id]);
      }
      final int start = (startPage ?? (t.lastPage > 0 ? t.lastPage : 0)).clamp(0, max(0, n - 1)).toInt();
      anchorPage = start;
      fromPage = start;
      _rebuildViews();
      _goToPage(start, record: false);
      _loader(_loaderGen);
    } catch (e) {
      AppLog.I.error('Couldn\'t open ${t.fileName}', e);
      error = 'Couldn\'t open this file. $e';
    }
    if (mounted) setState(() {});
  }

  // ---------------- loading ----------------

  /// Reads every page in the background, nearest to the current page first,
  /// so pages are ready before they're reached.
  Future<void> _loader(int gen) async {
    final b = book;
    if (b == null) return;
    while (mounted && gen == _loaderGen) {
      final cur = _currentPage;
      int? next;
      for (var d = 0; d < n; d++) {
        for (final i in [cur + d, cur - d]) {
          if (i >= 0 && i < n && !bytes.containsKey(i) && !failed.contains(i)) {
            next = i;
            break;
          }
        }
        if (next != null) break;
      }
      if (next == null) break;
      try {
        final data = await b.page(next);
        if (gen != _loaderGen || !mounted) return;
        bytes[next] = data;
        _bytesTotal += data.length;
        hashes[next] = hashBytes(data);
        final d = imageSize(data);
        if (d != null) {
          final wasWide = _isWide(next);
          dims[next] = d;
          if (_isWide(next) != wasWide) _rebuildViews();
        }
        _evictBytes();
        if (_visiblePages.contains(next) || (next - cur).abs() < 6) _decodeAround();
      } catch (e) {
        failed.add(next);
        AppLog.I.warn('Page ${next + 1} of ${t.fileName} couldn\'t be read: $e');
      }
      if (mounted) setState(() {});
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _evictBytes() {
    const cap = 400 * 1024 * 1024;
    if (_bytesTotal <= cap) return;
    final cur = _currentPage;
    final keys = bytes.keys.toList()..sort((a, b) => (b - cur).abs().compareTo((a - cur).abs()));
    for (final k in keys) {
      if (_bytesTotal <= cap * 0.8) break;
      if ((k - cur).abs() < 10) break;
      _bytesTotal -= bytes.remove(k)!.length;
    }
  }

  Future<Uint8List?> _bytesFor(int i) async {
    final b = bytes[i];
    if (b != null) return b;
    try {
      final data = await book!.page(i);
      bytes[i] = data;
      _bytesTotal += data.length;
      return data;
    } catch (_) {
      return null;
    }
  }

  void _decodeAround() {
    final want = <int>{};
    for (var v = max(0, pos - 1); v < min(views.length, pos + 4); v++) {
      want.addAll(views[v].pages);
    }
    if (stripMode) {
      final c = _currentPage;
      for (var i = max(0, c - 2); i < min(n, c + 5); i++) {
        want.add(i);
      }
    }
    for (final i in want) {
      _decode(i);
    }
    // Free decoded pages far away.
    final drop = images.keys.where((k) => !want.contains(k) && (k - _currentPage).abs() > 8).toList();
    for (final k in drop) {
      images.remove(k)?.dispose();
    }
  }

  Future<void> _decode(int i) async {
    if (images.containsKey(i) || _decoding.contains(i) || failed.contains(i)) return;
    final data = bytes[i];
    if (data == null) return;
    _decoding.add(i);
    try {
      final d = dims[i];
      int? tw, th;
      if (d != null && max(d.$1, d.$2) > 4096) {
        if (d.$1 >= d.$2) {
          tw = 4096;
        } else {
          th = 4096;
        }
      }
      final codec = await ui.instantiateImageCodec(data, targetWidth: tw, targetHeight: th);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      images[i] = frame.image;
      dims[i] ??= (frame.image.width, frame.image.height);
      if (crop && !crops.containsKey(i)) crops[i] = await _findCrop(data);
      setState(() {});
    } catch (e) {
      failed.add(i);
      final ext = p.extension(book!.pageNames[i]).toUpperCase().replaceAll('.', '');
      AppLog.I.warn('Page ${i + 1} couldn\'t be shown ($ext): $e');
      setState(() {});
    } finally {
      _decoding.remove(i);
    }
  }

  /// Finds plain white or black margins from a small copy of the page.
  Future<Rect> _findCrop(Uint8List data) async {
    try {
      final codec = await ui.instantiateImageCodec(data, targetWidth: 160);
      final fr = await codec.getNextFrame();
      final im = fr.image;
      final bd = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = im.width, h = im.height;
      im.dispose();
      if (bd == null) return const Rect.fromLTRB(0, 0, 1, 1);
      int lum(int x, int y) {
        final o = (y * w + x) * 4;
        return (bd.getUint8(o) + bd.getUint8(o + 1) + bd.getUint8(o + 2)) ~/ 3;
      }

      final bg = lum(1, 1);
      bool blank(int v) => (v - bg).abs() < 18 && (bg > 225 || bg < 30);
      bool rowBlank(int y) {
        for (var x = 0; x < w; x += 2) {
          if (!blank(lum(x, y))) return false;
        }
        return true;
      }

      bool colBlank(int x) {
        for (var y = 0; y < h; y += 2) {
          if (!blank(lum(x, y))) return false;
        }
        return true;
      }

      if (!(bg > 225 || bg < 30)) return const Rect.fromLTRB(0, 0, 1, 1);
      var top = 0, bottom = h - 1, left = 0, right = w - 1;
      while (top < h ~/ 3 && rowBlank(top)) {
        top++;
      }
      while (bottom > h * 2 ~/ 3 && rowBlank(bottom)) {
        bottom--;
      }
      while (left < w ~/ 3 && colBlank(left)) {
        left++;
      }
      while (right > w * 2 ~/ 3 && colBlank(right)) {
        right--;
      }
      const pad = 1;
      return Rect.fromLTRB(max(0, left - pad) / w, max(0, top - pad) / h, min(w, right + 1 + pad) / w, min(h, bottom + 1 + pad) / h);
    } catch (_) {
      return const Rect.fromLTRB(0, 0, 1, 1);
    }
  }

  // ---------------- layout ----------------

  bool _isWide(int i) {
    final d = dims[i];
    return d != null && d.$1 > d.$2 * 1.15;
  }

  void _rebuildViews() {
    final parts = <Part>[];
    final rtl = direction == ReadDirection.rtl;
    for (var i = 0; i < n; i++) {
      if (splitActive && _isWide(i) && direction != ReadDirection.ttb) {
        // Reading order: right half first when reading right to left.
        parts.addAll(rtl ? [Part(i, 2), Part(i, 1)] : [Part(i, 1), Part(i, 2)]);
      } else {
        parts.add(Part(i));
      }
    }
    final out = <View>[];
    if (!doublePage) {
      for (final x in parts) {
        out.add(View([x]));
      }
    } else {
      var k = 0;
      if (coverOffset && parts.isNotEmpty) {
        out.add(View([parts[0]]));
        k = 1;
      }
      while (k < parts.length) {
        final a = parts[k];
        final aWide = a.half == 0 && _isWide(a.page);
        if (aWide || k + 1 >= parts.length) {
          out.add(View([a]));
          k++;
          continue;
        }
        final b = parts[k + 1];
        if (b.half == 0 && _isWide(b.page)) {
          out.add(View([a]));
          k++;
          continue;
        }
        out.add(View(rtl ? [b, a] : [a, b]));
        k += 2;
      }
    }
    views = out;
    final anchor = anchorPage;
    final idx = views.indexWhere((v) => v.pages.contains(anchor));
    pos = idx < 0 ? 0 : idx;
  }

  int get _currentPage {
    if (stripMode) return anchorPage;
    if (pos >= views.length) return max(0, n - 1);
    return views[pos].pages.reduce(min);
  }

  Set<int> get _visiblePages => pos < views.length ? views[pos].pages.toSet() : {};

  void _goToPage(int page, {bool record = true}) {
    anchorPage = page.clamp(0, max(0, n - 1));
    if (stripMode) {
      _scrollStripTo(anchorPage);
    } else {
      final i = views.indexWhere((v) => v.pages.contains(anchorPage));
      if (i >= 0) pos = i;
    }
    zoom = 1;
    pan = const Offset(0, 1e9);
    _onPageShown(record: record);
  }

  void _onPageShown({bool record = true}) {
    final pages = stripMode ? {anchorPage} : _visiblePages;
    if (pages.isEmpty) return;
    seen.addAll(pages);
    final last = pages.reduce(max);
    t.lastPage = pages.reduce(min);
    t.lastReadAt = nowSec();
    if (last >= n - 1 && n > 0 && !completedThisSession && seen.length > 1) {
      _complete();
    } else {
      Db.I.updateReading(t);
    }
    _decodeAround();
    _scrollPageStrip();
    if (mounted) setState(() {});
  }

  void _complete() {
    completedThisSession = true;
    final now = nowSec();
    Db.I.addCompletion(t.id, now);
    t.readCount += 1;
    t.manualRead = false;
    t.firstCompletedAt = t.firstCompletedAt == 0 ? now : t.firstCompletedAt;
    t.lastCompletedAt = now;
    Db.I.updateReading(t);
    AppLog.I.info('Finished ${t.displayTitle} (read ${t.readCount} times)');
  }

  void _endSession() {
    if (book == null) return;
    final pagesSeen = seen.length;
    if (activeSeconds < 5 && pagesSeen < 2) return;
    final to = seen.isEmpty ? fromPage : seen.reduce(max);
    if (completedThisSession) t.lastPage = 0;
    t.timeSpent += activeSeconds;
    Db.I.updateReading(t);
    Db.I.addSession(
      titleId: t.id,
      startedAt: sessionStart,
      endedAt: nowSec(),
      activeSeconds: activeSeconds,
      fromPage: fromPage,
      toPage: to,
      pagesSeen: pagesSeen,
      completed: completedThisSession,
    );
  }

  // ---------------- navigation ----------------

  void _input() => lastInput = DateTime.now();

  @override
  void next() {
    _input();
    if (stripMode) {
      _scrollBy(viewport.height * 0.9);
      return;
    }
    if (pos >= views.length) {
      _nextFile();
      return;
    }
    setState(() {
      pos++;
      zoom = 1;
      pan = const Offset(0, 1e9);
      if (pos < views.length) anchorPage = views[pos].pages.reduce(min);
    });
    if (pos < views.length) {
      _onPageShown();
    } else {
      if (!completedThisSession && n > 0) _complete();
      setState(() {});
    }
  }

  void prev() {
    _input();
    if (stripMode) {
      _scrollBy(-viewport.height * 0.9);
      return;
    }
    if (pos <= 0) return;
    setState(() {
      pos--;
      zoom = 1;
      pan = const Offset(0, 1e9);
      anchorPage = views[pos].pages.reduce(min);
    });
    _onPageShown();
  }

  Title? get nextTitle {
    final q = widget.queue;
    final i = q.indexWhere((x) => x.id == t.id);
    for (var k = i + 1; k < q.length; k++) {
      final c = q[k];
      if (c.missing) continue;
      if (Settings.I.skipRead && c.isRead) continue;
      return c;
    }
    return null;
  }

  void _nextFile() {
    final nt = nextTitle;
    if (nt == null) {
      _close();
      return;
    }
    _endSession();
    _openTitle(nt, null);
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  // Strip mode
  double _stripItemHeight(int i, double width) {
    final d = dims[i];
    final aspect = d == null ? 1.42 : d.$2 / d.$1;
    return width * aspect;
  }

  double get _stripWidth => (viewport.width * (ss.fit == FitMode.width ? 1.0 : 0.62) * zoom).clamp(200, viewport.width * 3);

  void _scrollStripTo(int page) {
    if (!vScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) => vScroll.hasClients ? _scrollStripTo(page) : null);
      return;
    }
    var y = 0.0;
    for (var i = 0; i < page; i++) {
      y += _stripItemHeight(i, _stripWidth) + 6;
    }
    vScroll.jumpTo(y.clamp(0, vScroll.position.maxScrollExtent));
  }

  void _scrollBy(double dy) {
    if (!vScroll.hasClients) return;
    vScroll.animateTo((vScroll.offset + dy).clamp(0, vScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
  }

  void _onStripScroll() {
    var y = 0.0;
    final off = vScroll.offset + viewport.height * 0.3;
    var page = 0;
    for (var i = 0; i < n; i++) {
      final h = _stripItemHeight(i, _stripWidth) + 6;
      if (y + h > off) {
        page = i;
        break;
      }
      y += h;
      page = i;
    }
    if (page != anchorPage) {
      anchorPage = page;
      _onPageShown();
    }
    if (vScroll.position.pixels >= vScroll.position.maxScrollExtent - 2 && !completedThisSession && n > 0) {
      seen.add(n - 1);
      _complete();
      setState(() {});
    }
  }

  // ---------------- settings changes ----------------

  void _setDirection(ReadDirection d) {
    t.direction = d.name;
    Db.I.updateReading(t);
    anchorPage = _currentPage;
    _rebuildViews();
    if (stripMode) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripTo(anchorPage));
    setState(() {});
  }

  void _relayout() {
    anchorPage = _currentPage;
    _rebuildViews();
    setState(() {});
  }

  void _toggleCoverOffset() {
    t.coverOffset = !coverOffset;
    Db.I.updateReading(t);
    _relayout();
  }

  void _toggleCrop() {
    t.crop = !crop;
    Db.I.updateReading(t);
    if (t.crop == true) {
      for (final i in images.keys) {
        if (!crops.containsKey(i) && bytes[i] != null) {
          _findCrop(bytes[i]!).then((r) {
            crops[i] = r;
            if (mounted) setState(() {});
          });
        }
      }
    }
    setState(() {});
  }

  void _toggleDouble() {
    ss.layout = doublePage ? PageLayout.single : PageLayout.double;
    Settings.I.save();
    _relayout();
  }

  // ---------------- saving ----------------

  Future<void> _savePage() async {
    _input();
    final view = stripMode ? View([Part(anchorPage)]) : (pos < views.length ? views[pos] : null);
    if (view == null) return;
    List<Part> parts = view.parts;
    if (parts.length > 1) {
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AppDialog(
          title: 'Save which page?',
          body: Text('Two pages are showing. Save one of them, or both side by side as one image.', style: ts(c: tk.sec)),
          actions: [
            Btn('Left page', onTap: () => Navigator.pop(c, 'left')),
            Btn('Right page', onTap: () => Navigator.pop(c, 'right')),
            Btn.primary('Both combined', onTap: () => Navigator.pop(c, 'both')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'left') parts = [parts.first];
      if (choice == 'right') parts = [parts.last];
    }
    final pp = <PagePart>[];
    for (final x in parts) {
      final b = await _bytesFor(x.page);
      if (b == null) {
        toast('That page isn\'t loaded yet', ToastKind.error);
        return;
      }
      pp.add(PagePart(x.page, b, p.extension(book!.pageNames[x.page]), half: x.half));
    }
    final r = await PageSaver.save(title: t, parts: pp);
    switch (r) {
      case Saved(:final path):
        savedHashes = Db.I.savedHashes();
        toast('Saved ${p.basename(path)}');
      case AlreadySaved(:final at):
        toast('Already saved on ${dateText(at)}, so it wasn\'t saved again', ToastKind.info);
      case SaveFailed(:final message):
        toast(message, ToastKind.error);
    }
    if (mounted) setState(() {});
  }

  bool _isSaved(Part x) {
    final h = hashes[x.page];
    if (h == null) return false;
    return savedHashes.contains(x.half == 0 ? h : '$h#${x.half}');
  }

  // ---------------- keys ----------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (typingField()) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final rtl = direction == ReadDirection.rtl;
    _input();
    if (k == LogicalKeyboardKey.escape) {
      if (showStrip) {
        setState(() => showStrip = false);
      } else if (zoom != 1) {
        setState(() {
          zoom = 1;
          pan = Offset.zero;
        });
      } else if (_fullScreen) {
        _toggleFullScreen();
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      rtl ? prev() : next();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      rtl ? next() : prev();
    } else if (k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.space) {
      next();
    } else if (k == LogicalKeyboardKey.pageUp) {
      prev();
    } else if (k == LogicalKeyboardKey.home) {
      _goToPage(0);
    } else if (k == LogicalKeyboardKey.end) {
      _goToPage(n - 1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      stripMode ? _scrollBy(-120) : _zoomBy(1.15);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      stripMode ? _scrollBy(120) : _zoomBy(1 / 1.15);
    } else if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.15);
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(1 / 1.15);
    } else if (k == LogicalKeyboardKey.digit0) {
      setState(() {
        zoom = 1;
        pan = Offset.zero;
      });
    } else if (k == LogicalKeyboardKey.digit1) {
      _actualSize();
    } else if (k == LogicalKeyboardKey.keyD) {
      _toggleDouble();
    } else if (k == LogicalKeyboardKey.keyO) {
      _toggleCoverOffset();
    } else if (k == LogicalKeyboardKey.keyC) {
      _toggleCrop();
    } else if (k == LogicalKeyboardKey.keyP) {
      _savePage();
    } else if (k == LogicalKeyboardKey.keyV) {
      Library.I.toggleFavourite([t]);
      toast(t.favourite ? 'Added to favourites' : 'Removed from favourites');
      setState(() {});
    } else if (k == LogicalKeyboardKey.keyN) {
      _nextFile();
    } else if (k == LogicalKeyboardKey.keyG) {
      setState(() => showStrip = !showStrip);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _toggleFullScreen();
    } else if (k == LogicalKeyboardKey.keyH) {
      setState(() => ui_ = !ui_);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool typingField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText);
  }

  bool _fullScreen = false;
  Future<void> _toggleFullScreen() async {
    _fullScreen = !_fullScreen;
    try {
      await windowManager.setFullScreen(_fullScreen);
    } catch (_) {}
    setState(() {});
  }

  void _zoomBy(double f) => setState(() => zoom = (zoom * f).clamp(0.3, 8));

  void _actualSize() {
    final i = _currentPage;
    final d = dims[i];
    if (d == null || viewport.isEmpty) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fitted = _fitSize(views.isNotEmpty && pos < views.length ? views[pos] : View([Part(i)]), viewport);
    setState(() => zoom = (d.$2 / dpr) / fitted.height);
  }

  // ---------------- drawing ----------------

  Rect _src(Part x) {
    final d = dims[x.page] ?? (1000, 1420);
    final w = d.$1.toDouble(), h = d.$2.toDouble();
    var r = Rect.fromLTWH(0, 0, w, h);
    if (x.half == 1) r = Rect.fromLTWH(0, 0, w / 2, h);
    if (x.half == 2) r = Rect.fromLTWH(w / 2, 0, w / 2, h);
    if (crop && crops[x.page] != null) {
      final c = crops[x.page]!;
      final cr = Rect.fromLTRB(c.left * w, c.top * h, c.right * w, c.bottom * h);
      r = r.intersect(cr);
      if (r.isEmpty) r = Rect.fromLTWH(0, 0, w, h);
    }
    return r;
  }

  double _aspect(Part x) {
    final r = _src(x);
    return r.width / r.height;
  }

  /// Size of the whole view (both pages, same height) under the fit mode.
  Size _fitSize(View v, Size box) {
    final total = v.parts.fold<double>(0, (a, x) => a + _aspect(x));
    double h;
    switch (ss.fit) {
      case FitMode.screen:
        h = min(box.height, box.width / total);
      case FitMode.width:
        h = box.width / total;
      case FitMode.height:
        h = box.height;
      case FitMode.original:
        final d = dims[v.parts.first.page];
        final dpr = MediaQuery.devicePixelRatioOf(context);
        h = d == null ? box.height : _src(v.parts.first).height / dpr;
    }
    return Size(h * total, h);
  }

  Widget _pageWidget(Part x, double height) {
    final im = images[x.page];
    final w = height * _aspect(x);
    if (im == null) {
      return Container(
        width: w,
        height: height,
        color: tk.stage,
        alignment: Alignment.center,
        child: failed.contains(x.page)
            ? Text(
                'Page ${x.page + 1} can\'t be shown${book != null ? ' (${p.extension(book!.pageNames[x.page]).replaceAll('.', '').toUpperCase()})' : ''}',
                style: ts(c: tk.sec))
            : SizedBox(width: 120, child: Progress(value: null, height: 3)),
      );
    }
    final src = _src(x);
    final scale = im.width / (dims[x.page]?.$1 ?? im.width);
    final srcPx = Rect.fromLTRB(src.left * scale, src.top * scale, src.right * scale, src.bottom * scale);
    return SizedBox(width: w, height: height, child: CustomPaint(painter: _PagePainter(im, srcPx)));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: tk.stage,
        body: LayoutBuilder(builder: (context, c) {
          final newViewport = Size(c.maxWidth, c.maxHeight);
          if (newViewport != viewport) {
            final wasDouble = viewport == Size.zero ? null : doublePage;
            viewport = newViewport;
            if (wasDouble != null && wasDouble != doublePage) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _relayout());
            }
          }
          return Stack(children: [
            Positioned.fill(child: _content()),
            if (Settings.I.pageNumbers && n > 0 && !ui_) Positioned(right: 14, bottom: 10, child: _pageNumber()),
            if (ui_) ..._overlay(),
            if (showStrip) Positioned(left: 0, right: 0, bottom: ui_ ? 64 : 0, child: _pageStrip()),
            const ToastLayer(),
          ]);
        }),
      ),
    );
  }

  Widget _pageNumber() {
    final pages = stripMode ? [anchorPage] : (pos < views.length ? views[pos].pages.toList() : <int>[]);
    if (pages.isEmpty) return const SizedBox();
    pages.sort();
    final label = pages.length == 1 ? '${pages.first + 1} / $n' : '${pages.first + 1}–${pages.last + 1} / $n';
    final saved = (stripMode ? [Part(anchorPage)] : views[pos].parts).any(_isSaved);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (saved) const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.bookmark_added, size: 13, color: Colors.white)),
        Text(label, style: ts(c: Colors.white, size: 12, tab: true)),
      ]),
    );
  }

  Widget _content() {
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error!, style: ts(c: tk.sec), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Btn('Close the reader', onTap: _close),
        ]),
      );
    }
    if (book == null) return Center(child: SizedBox(width: 200, child: Progress(value: null, height: 4)));
    if (stripMode) return _stripView();
    if (pos >= views.length) return _endScreen();
    final v = views[pos];
    final size = _fitSize(v, viewport);
    final w = size.width * zoom, h = size.height * zoom;
    final row = Row(mainAxisSize: MainAxisSize.min, children: [for (final x in v.parts) _pageWidget(x, h)]);
    final overflowX = max(0.0, w - viewport.width), overflowY = max(0.0, h - viewport.height);
    pan = Offset(pan.dx.clamp(-overflowX / 2, overflowX / 2), pan.dy.clamp(-overflowY / 2, overflowY / 2));
    return Listener(
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent) return;
        _input();
        if (HardwareKeyboard.instance.isControlPressed) {
          _zoomBy(e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
        } else if (overflowY > 0) {
          final ny = pan.dy - e.scrollDelta.dy;
          if ((e.scrollDelta.dy > 0 && pan.dy <= -overflowY / 2) || (e.scrollDelta.dy < 0 && pan.dy >= overflowY / 2)) {
            e.scrollDelta.dy > 0 ? next() : prev();
          } else {
            setState(() => pan = Offset(pan.dx, ny.clamp(-overflowY / 2, overflowY / 2)));
          }
        } else {
          e.scrollDelta.dy > 0 ? next() : prev();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          if (overflowX > 0 || overflowY > 0) setState(() => pan += d.delta);
        },
        onTapUp: (d) => _tapAt(d.localPosition),
        onDoubleTap: () => setState(() {
          zoom = zoom == 1 ? 2 : 1;
          pan = Offset.zero;
        }),
        child: ClipRect(
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(offset: pan, child: SizedBox(width: w, height: h, child: row)),
          ),
        ),
      ),
    );
  }

  void _tapAt(Offset at) {
    _input();
    final x = at.dx / viewport.width;
    if (x > 0.35 && x < 0.65) {
      setState(() => ui_ = !ui_);
      return;
    }
    final leftSide = x <= 0.35;
    if (direction == ReadDirection.rtl) {
      leftSide ? next() : prev();
    } else if (direction == ReadDirection.ttb) {
      at.dy / viewport.height > 0.5 || !leftSide ? next() : prev();
    } else {
      leftSide ? prev() : next();
    }
  }

  Widget _stripView() {
    final width = _stripWidth;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _onStripScroll();
        return false;
      },
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
            _zoomBy(e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
          }
          _input();
        },
        child: GestureDetector(
          onTapUp: (d) {
            final x = d.localPosition.dx / viewport.width;
            if (x > 0.3 && x < 0.7) setState(() => ui_ = !ui_);
          },
          child: ListView.builder(
            controller: vScroll,
            itemCount: n + 1,
            itemBuilder: (_, i) {
              if (i == n) return SizedBox(height: viewport.height * 0.8, child: _endScreen());
              _decode(i);
              final h = _stripItemHeight(i, width);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(child: _pageWidget(Part(i), h)),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _endScreen() {
    final nt = nextTitle;
    final tags = Library.I.tagsOf(t).map((id) => Library.I.tagById(t.section, id)).whereType<Tag>();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final x = d.localPosition.dx / max(1, viewport.width);
        if (x < 0.25) prev();
      },
      child: Center(
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line2)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.check_circle_outline, color: tk.ok, size: 20),
              const SizedBox(width: 8),
              Text('Finished', style: ts(size: 15, w: FontWeight.w700)),
              const Spacer(),
              Text('Read ${t.readCount} ${t.readCount == 1 ? 'time' : 'times'}', style: ts(c: tk.sec)),
            ]),
            const SizedBox(height: 6),
            Text(t.displayTitle, style: ts(c: tk.sec), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            Row(children: [
              Stars(value: t.rating, size: 26, onChanged: (v) {
                Library.I.setRating(t, v);
                setState(() {});
              }),
              const SizedBox(width: 12),
              IconBtn(t.favourite ? Icons.favorite : Icons.favorite_border,
                  color: t.favourite ? const Color(0xFFFF6FB1) : null, tooltip: 'Favourite (V)', onTap: () {
                Library.I.toggleFavourite([t]);
                setState(() {});
              }),
              const SizedBox(width: 6),
              TagMenu(section: t.section, titles: [t]),
            ]),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [for (final g in tags) TagChip(g.name, Color(g.color))]),
            ],
            const SizedBox(height: 18),
            if (nt != null) ...[
              Text('Next', style: ts(c: tk.faint, size: 12)),
              const SizedBox(height: 4),
              Row(children: [
                SizedBox(width: 44, height: 62, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CoverThumb(title: nt, width: 44))),
                const SizedBox(width: 10),
                Expanded(child: Text(nt.displayTitle, style: ts(w: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Btn('Back to the library', onTap: _close),
              const Spacer(),
              if (nt != null) Btn.primary('Read next', icon: Icons.skip_next, onTap: _nextFile),
            ]),
            const SizedBox(height: 6),
            Text(nt != null ? 'Turn the page again to open the next file.' : 'That was the last one in this list.',
                style: ts(c: tk.faint, size: 12)),
          ]),
        ),
      ),
    );
  }

  List<Widget> _overlay() {
    final pagesNow = stripMode ? [anchorPage] : (pos < views.length ? views[pos].pages.toList() : [max(0, n - 1)]);
    final cur = pagesNow.isEmpty ? 0 : pagesNow.reduce(min);
    final loaded = bytes.length + failed.length;
    return [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: tk.panel.withValues(alpha: 0.96),
          child: Row(children: [
            IconBtn(Icons.arrow_back, tooltip: 'Close the reader (Esc)', onTap: _close),
            const SizedBox(width: 8),
            Expanded(child: Text(t.displayTitle, style: ts(w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            Drop<ReadDirection>(
              value: direction,
              items: const [
                (ReadDirection.ltr, 'Left to right'),
                (ReadDirection.rtl, 'Right to left'),
                (ReadDirection.ttb, 'Top to bottom'),
              ],
              onChanged: _setDirection,
            ),
            const SizedBox(width: 6),
            if (direction == ReadDirection.ttb)
              Seg<VerticalStyle>(
                value: ss.verticalStyle,
                items: const [(VerticalStyle.paged, 'Page by page'), (VerticalStyle.strip, 'Strip')],
                onChanged: (v) {
                  ss.verticalStyle = v;
                  Settings.I.save();
                  _relayout();
                  if (stripMode) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripTo(anchorPage));
                },
              )
            else
              Seg<PageLayout>(
                value: ss.layout,
                items: const [(PageLayout.single, 'Single'), (PageLayout.double, 'Two pages'), (PageLayout.auto, 'Auto')],
                onChanged: (v) {
                  ss.layout = v;
                  Settings.I.save();
                  _relayout();
                },
              ),
            const SizedBox(width: 6),
            Drop<FitMode>(
              value: ss.fit,
              items: const [
                (FitMode.screen, 'Fit screen'),
                (FitMode.width, 'Fit width'),
                (FitMode.height, 'Fit height'),
                (FitMode.original, 'Original size'),
              ],
              onChanged: (v) {
                ss.fit = v;
                Settings.I.save();
                setState(() {
                  zoom = 1;
                  pan = Offset.zero;
                });
              },
            ),
            const SizedBox(width: 6),
            Drop<SplitMode>(
              value: ss.split,
              items: const [
                (SplitMode.off, 'Wide pages: whole'),
                (SplitMode.split, 'Wide pages: split'),
                (SplitMode.singleOnly, 'Split in single-page mode'),
              ],
              onChanged: (v) {
                ss.split = v;
                Settings.I.save();
                _relayout();
              },
            ),
            const SizedBox(width: 4),
            IconBtn(Icons.looks_one_outlined, tooltip: 'Offset the cover (O)', active: coverOffset, onTap: _toggleCoverOffset),
            IconBtn(Icons.crop, tooltip: 'Crop borders (C)', active: crop, onTap: _toggleCrop),
            IconBtn(Icons.view_carousel_outlined, tooltip: 'Page strip (G)', active: showStrip, onTap: () => setState(() => showStrip = !showStrip)),
            IconBtn(Icons.bookmark_add_outlined, tooltip: 'Save page (P)', onTap: _savePage),
            IconBtn(t.favourite ? Icons.favorite : Icons.favorite_border, tooltip: 'Favourite (V)',
                color: t.favourite ? const Color(0xFFFF6FB1) : null, onTap: () {
              Library.I.toggleFavourite([t]);
              setState(() {});
            }),
            IconBtn(_fullScreen ? Icons.fullscreen_exit : Icons.fullscreen, tooltip: 'Full screen (F)', onTap: _toggleFullScreen),
          ]),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: tk.panel.withValues(alpha: 0.96),
          child: Row(children: [
            Text('${cur + 1} / $n', style: ts(tab: true, w: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Directionality(
                textDirection: direction == ReadDirection.rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Slider(
                  value: cur.toDouble().clamp(0, max(0, n - 1).toDouble()),
                  min: 0,
                  max: max(1, n - 1).toDouble(),
                  onChanged: (v) => _goToPage(v.round()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(loaded >= n ? 'All pages loaded' : 'Loading pages · $loaded of $n', style: ts(c: tk.faint, size: 11.5, tab: true)),
                const SizedBox(height: 4),
                Progress(value: n == 0 ? 0 : loaded / n, height: 3),
              ]),
            ),
            const SizedBox(width: 12),
            Stars(value: t.rating, size: 18, onChanged: (v) {
              Library.I.setRating(t, v);
              setState(() {});
            }),
            if (nextTitle != null) ...[
              const SizedBox(width: 12),
              Btn('Next file', icon: Icons.skip_next, dense: true, tooltip: nextTitle!.displayTitle, onTap: _nextFile),
            ],
          ]),
        ),
      ),
    ];
  }

  Widget _pageStrip() {
    return Container(
      height: 128,
      color: tk.panel.withValues(alpha: 0.96),
      child: ListView.builder(
        controller: stripScroll,
        scrollDirection: Axis.horizontal,
        reverse: direction == ReadDirection.rtl,
        padding: const EdgeInsets.all(8),
        itemCount: n,
        itemExtent: 84,
        itemBuilder: (_, i) {
          _stripThumb(i);
          final im = strip[i];
          final active = (stripMode ? {anchorPage} : _visiblePages).contains(i);
          return GestureDetector(
            onTap: () => _goToPage(i),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(color: active ? lk.outline : tk.line, width: active ? 2 : 1),
                borderRadius: BorderRadius.circular(4),
                color: tk.stage,
              ),
              child: Column(children: [
                Expanded(child: im == null ? const SizedBox() : RawImage(image: im, fit: BoxFit.contain)),
                Text('${i + 1}', style: ts(size: 11, c: tk.sec, tab: true)),
              ]),
            ),
          );
        },
      ),
    );
  }

  final Set<int> _stripPending = {};
  void _stripThumb(int i) {
    if (strip.containsKey(i) || _stripPending.contains(i)) return;
    final b = bytes[i];
    if (b == null) return;
    _stripPending.add(i);
    ui.instantiateImageCodec(b, targetWidth: 120).then((c) => c.getNextFrame()).then((f) {
      _stripPending.remove(i);
      if (!mounted) {
        f.image.dispose();
        return;
      }
      setState(() => strip[i] = f.image);
    }).catchError((Object _) {
      _stripPending.remove(i);
    });
  }

  void _scrollPageStrip() {
    if (!showStrip || !stripScroll.hasClients) return;
    final target = (_currentPage * 84.0 - viewport.width / 2 + 42).clamp(0.0, stripScroll.position.maxScrollExtent);
    stripScroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.image, this.src);
  final ui.Image image;
  final Rect src;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    canvas.drawImageRect(image, src, Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_PagePainter old) => old.image != image || old.src != src;
}
