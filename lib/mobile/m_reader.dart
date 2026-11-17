import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../core/archives.dart';
import '../core/db.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/settings.dart';
import '../ui/widgets.dart';
import 'mobile_app.dart';
import 'pc.dart';
import 'remote_book.dart';
import 'store.dart';

Future<void> openMobileReader(BuildContext context, Title t, List<Title> chapters, {int? page}) async {
  if (!Store.I.isDownloaded(t) && !Pc.I.online) await Pc.I.check();
  if (!context.mounted) return;
  await Navigator.of(context).push(PageRouteBuilder(
    pageBuilder: (_, _, _) => MReader(title: t, chapters: chapters, startPage: page),
    transitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

/// One screenful: one page, half a page, or two pages side by side.
class _View {
  _View(this.parts);
  final List<(int page, int half)> parts; // half: 0 whole, 1 left, 2 right
  List<int> get pages => parts.map((x) => x.$1).toList();
}

class MReader extends StatefulWidget {
  const MReader({super.key, required this.title, required this.chapters, this.startPage});
  final Title title;
  final List<Title> chapters;
  final int? startPage;
  @override
  State<MReader> createState() => _MReaderState();
}

class _MReaderState extends State<MReader> with WidgetsBindingObserver {
  late Title t;
  Book? book;
  String? error;
  bool loading = true;
  List<_View> views = [];
  int pos = 0;
  int anchorPage = 0;
  bool controls = false;
  final Map<int, (int, int)> sizes = {};
  final LinkedHashMap<int, Uint8List> _bytes = LinkedHashMap();
  final Map<int, Future<Uint8List>> _loading = {};
  PageController? pager;
  final ScrollController strip = ScrollController();
  final TransformationController zoom = TransformationController();
  bool zoomed = false;
  StreamSubscription? _vol;
  Size screen = Size.zero;

  // Reading record.
  int sessionStart = 0;
  int activeSeconds = 0;
  int fromPage = 0;
  final Set<int> seen = {};
  bool completedThisSession = false;
  DateTime lastInput = DateTime.now();
  Timer? _tick;
  Timer? _savePos;

  SectionSettings get ss => Settings.I.of(t.section);
  ReadDirection get dir =>
      t.direction == null ? ss.direction : ReadDirection.values.firstWhere((d) => d.name == t.direction, orElse: () => ss.direction);
  bool get stripMode => dir == ReadDirection.ttb && ss.verticalStyle == VerticalStyle.strip;
  bool get rtl => dir == ReadDirection.rtl;
  int get n => book?.length ?? 0;

  bool get twoPages {
    final mode = Settings.I.get<String>('m.twoPages', 'auto');
    if (stripMode || dir == ReadDirection.ttb || mode == 'never') return false;
    if (mode == 'always') return true;
    return screen.width > 560 && screen.width > screen.height * 0.85;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (Settings.I.get<bool>('m.volumeKeys', true)) {
      Native.setVolumeKeys(true);
      _vol = Native.volume.stream.listen((k) => k == 'down' ? next() : prev());
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(lastInput).inMinutes < Settings.I.idleMinutes) activeSeconds++;
    });
    _open(widget.title, widget.startPage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) _flushPosition();
  }

  Future<void> _open(Title title, int? startPage) async {
    _endSession();
    book?.close();
    setState(() {
      t = title;
      book = null;
      error = null;
      loading = true;
      views = [];
      sizes.clear();
      _bytes.clear();
      _loading.clear();
    });
    try {
      final local = Store.I.downloadOf(t);
      final b = local != null
          ? await FastZipBook.open(local)
          : await RemoteBook.open(t, maxWidth: _screenPixels());
      if (!mounted) {
        b.close();
        return;
      }
      book = b;
      if (b is RemoteBook) b.loaded.addListener(_onLoaded);
      final int start = (startPage ?? (t.isRead && t.lastPage == 0 ? 0 : t.lastPage)).clamp(0, max(0, b.length - 1)).toInt();
      anchorPage = start;
      fromPage = start;
      sessionStart = nowSec();
      activeSeconds = 0;
      seen.clear();
      completedThisSession = false;
      if (b is RemoteBook) b.preloadAll(start);
      setState(() => loading = false);
      _rebuild();
    } catch (e) {
      AppLog.I.warn('Couldn\'t open ${t.fileName} on the phone: $e');
      if (mounted) {
        setState(() {
          loading = false;
          error = Pc.I.online ? 'Couldn\'t open this file: $e' : 'This title isn\'t downloaded and the PC can\'t be reached.';
        });
      }
    }
  }

  /// The screen's longest side in pixels: big pages can be shrunk to this.
  int _screenPixels() {
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    return max(v.physicalSize.width, v.physicalSize.height).round().clamp(800, 4000);
  }

  void _onLoaded() {
    final b = book;
    if (b is! RemoteBook || !mounted) return;
    // Learn page shapes near where we are, so spreads split and pair right.
    for (var i = max(0, anchorPage - 4); i < min(n, anchorPage + 8); i++) {
      if (!sizes.containsKey(i) && b.has(i)) _bytesFor(i);
    }
    setState(() {});
  }

  Future<Uint8List> _bytesFor(int i) {
    final have = _bytes[i];
    if (have != null) return Future.value(have);
    return _loading.putIfAbsent(i, () async {
      try {
        final b = await book!.page(i);
        _bytes[i] = b;
        while (_bytes.length > 12) {
          _bytes.remove(_bytes.keys.first);
        }
        final sz = imageSize(b);
        if (sz != null && sizes[i] != sz) {
          sizes[i] = sz;
          _rebuildSoon();
        }
        return b;
      } finally {
        _loading.remove(i);
      }
    });
  }

  bool _wide(int i) {
    final s = sizes[i];
    return s != null && s.$1 > s.$2 * 1.1;
  }

  Timer? _rb;
  void _rebuildSoon() {
    _rb?.cancel();
    _rb = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _rebuild();
    });
  }

  /// Works out what each screenful shows, keeping the current page in view.
  void _rebuild() {
    final two = twoPages;
    final split = ss.split == SplitMode.split || (ss.split == SplitMode.singleOnly && !two);
    final out = <_View>[];
    var i = 0;
    while (i < n) {
      if (!stripMode && split && !two && _wide(i)) {
        out.add(_View([(i, rtl ? 2 : 1)]));
        out.add(_View([(i, rtl ? 1 : 2)]));
        i++;
        continue;
      }
      final alone = !two || _wide(i) || (ss.coverOffset && i == 0) || i == n - 1 || _wide(i + 1);
      if (alone) {
        out.add(_View([(i, 0)]));
        i++;
      } else {
        out.add(_View(rtl ? [(i + 1, 0), (i, 0)] : [(i, 0), (i + 1, 0)]));
        i += 2;
      }
    }
    views = out;
    final p = views.indexWhere((v) => v.pages.contains(anchorPage));
    pos = p < 0 ? 0 : p;
    if (pager == null) {
      pager = PageController(initialPage: pos);
    } else if (pager!.hasClients && pager!.page?.round() != pos) {
      pager!.jumpToPage(pos);
    }
    setState(() {});
    _shown();
  }

  void _shown() {
    if (views.isEmpty) return;
    final pages = views[pos].pages;
    seen.addAll(pages);
    anchorPage = pages.reduce(min);
    final b = book;
    if (b is RemoteBook) b.focus = anchorPage;
    t.lastPage = anchorPage;
    t.lastReadAt = nowSec();
    if (pages.reduce(max) >= n - 1 && n > 0 && !completedThisSession && (seen.length > 1 || n == 1)) {
      _complete();
    }
    Db.I.updateReading(t);
    _savePos?.cancel();
    _savePos = Timer(const Duration(seconds: 4), _flushPosition);
    // Warm the pages either side.
    for (final v in [pos - 1, pos + 1, pos + 2]) {
      if (v >= 0 && v < views.length) {
        for (final pg in views[v].pages) {
          _bytesFor(pg).ignore();
        }
      }
    }
  }

  void _flushPosition() {
    _savePos?.cancel();
    Store.I.recordPosition(t);
  }

  void _complete() {
    completedThisSession = true;
    final now = nowSec();
    Store.I.recordCompletion(t, now);
    t.readCount += 1;
    t.manualRead = false;
    t.firstCompletedAt = t.firstCompletedAt == 0 ? now : t.firstCompletedAt;
    t.lastCompletedAt = now;
    Db.I.updateReading(t);
    Future.microtask(Library.I.changed);
  }

  void _endSession() {
    if (book == null) return;
    if (activeSeconds < 5 && seen.length < 2) return;
    if (completedThisSession) t.lastPage = 0;
    t.timeSpent += activeSeconds;
    Db.I.updateReading(t);
    _flushPosition();
    Store.I.recordSession(t,
        startedAt: sessionStart,
        activeSeconds: activeSeconds,
        fromPage: fromPage,
        toPage: seen.isEmpty ? fromPage : seen.reduce(max),
        pagesSeen: seen.length,
        completed: completedThisSession);
    if (completedThisSession) Store.I.afterFinished(t);
    activeSeconds = 0;
    seen.clear();
    // Not straight away: this also runs while the reader is being closed.
    Future.microtask(Library.I.changed);
  }

  @override
  void dispose() {
    _endSession();
    _tick?.cancel();
    _rb?.cancel();
    _vol?.cancel();
    Native.setVolumeKeys(false);
    final b = book;
    if (b is RemoteBook) b.loaded.removeListener(_onLoaded);
    b?.close();
    pager?.dispose();
    strip.dispose();
    zoom.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ------------------------------------------------------------ navigation

  void _input() => lastInput = DateTime.now();

  void next() {
    _input();
    if (stripMode) {
      strip.animateTo(min(strip.offset + screen.height * 0.85, strip.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      return;
    }
    if (pos >= views.length - 1) {
      _atEnd();
      return;
    }
    pager?.jumpToPage(pos + 1);
  }

  void prev() {
    _input();
    if (stripMode) {
      strip.animateTo(max(strip.offset - screen.height * 0.85, 0), duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      return;
    }
    if (pos > 0) pager?.jumpToPage(pos - 1);
  }

  Title? get nextChapter {
    final list = widget.chapters;
    final i = list.indexWhere((x) => x.id == t.id);
    if (i < 0) return null;
    for (final c in list.skip(i + 1)) {
      if (Settings.I.skipRead && c.isRead) continue;
      return c;
    }
    return null;
  }

  Title? get prevChapter {
    final list = widget.chapters;
    final i = list.indexWhere((x) => x.id == t.id);
    return i > 0 ? list[i - 1] : null;
  }

  void _atEnd() {
    final nx = nextChapter;
    if (nx == null) {
      mToast('That was the last page');
      return;
    }
    if (!Store.I.isDownloaded(nx) && !Pc.I.online) {
      mToast('The next chapter isn\'t downloaded and the PC can\'t be reached');
      return;
    }
    _open(nx, 0);
  }

  void _tap(TapUpDetails d) {
    final x = d.localPosition.dx / screen.width;
    final y = d.localPosition.dy / screen.height;
    final zones = Settings.I.get<String>('m.tapZones', 'follow');
    if (zones == 'off' || (x > 0.3 && x < 0.7 && !(stripMode && (y < 0.25 || y > 0.75)))) {
      setState(() => controls = !controls);
      return;
    }
    if (stripMode) {
      y < 0.5 ? prev() : next();
      return;
    }
    final left = x <= 0.3;
    final forward = zones == 'follow' && rtl ? left : !left;
    forward ? next() : prev();
  }

  // ------------------------------------------------------------ saving

  Future<void> _save() async {
    if (views.isEmpty) return;
    final v = views[pos];
    var parts = v.parts;
    if (parts.length == 2) {
      final pick = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: const Text('Left page'), onTap: () => Navigator.pop(c, 0)),
            ListTile(title: const Text('Right page'), onTap: () => Navigator.pop(c, 1)),
            ListTile(title: const Text('Both, as one image'), onTap: () => Navigator.pop(c, 2)),
          ]),
        ),
      );
      if (pick == null) return;
      parts = pick == 2 ? parts : [parts[pick]];
    }
    var r = await Store.I.savePage(t, parts);
    if (!mounted) return;
    if (r == null) {
      mToast('Waiting to save. The PC will save it when you\'re connected.');
      return;
    }
    if (r['result'] == 'duplicate') {
      final again = await mConfirm(
          context,
          'This would be a duplicate',
          'You saved this page from this chapter on ${dateText(r['at'] as int)}'
              '${r['moved'] == true ? ' (the file has since been moved)' : ' as ${r['file']}'}. Saving again makes a second copy with a new name.',
          'Save anyway');
      if (!again) return;
      r = await Store.I.savePage(t, parts, force: true);
      if (r == null) {
        mToast('Waiting to save. The PC will save it when you\'re connected.');
        return;
      }
    }
    if (r['result'] == 'saved') {
      mToast('Saved on the PC as ${r['file']}');
    } else if (r['result'] == 'failed') {
      mToast('The PC couldn\'t save it: ${r['message']}');
    }
  }

  // ------------------------------------------------------------ drawing

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    if (sz != screen) {
      final changed = screen != Size.zero && (sz.width > sz.height) != (screen.width > screen.height) || (screen.width - sz.width).abs() > 100;
      screen = sz;
      if (changed && book != null) WidgetsBinding.instance.addPostFrameCallback((_) => _rebuild());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: _body()),
        if (book is RemoteBook) _loadLine(book as RemoteBook),
        if (Settings.I.pageNumbers && views.isNotEmpty && !controls)
          Positioned(
            right: 10,
            bottom: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Text(_pageLabel(), style: ts(size: 12, c: Colors.white70, tab: true)),
              ),
            ),
          ),
        if (controls) ..._controls(),
      ]),
    );
  }

  String _pageLabel() {
    final pages = views[pos].pages..sort();
    return '${pages.map((x) => x + 1).join('–')} / $n';
  }

  Widget _loadLine(RemoteBook b) => Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: ValueListenableBuilder<int>(
          valueListenable: b.loaded,
          builder: (_, loaded, _) => loaded >= b.length
              ? const SizedBox()
              : LinearProgressIndicator(
                  value: b.length == 0 ? null : loaded / b.length,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: lk.acc.withValues(alpha: 0.8),
                ),
        ),
      );

  Widget _body() {
    if (loading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(t.displayTitle, style: ts(c: Colors.white70)),
        ]),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, color: tk.warn, size: 40),
            const SizedBox(height: 12),
            Text(error!, textAlign: TextAlign.center, style: ts(c: Colors.white70)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          ]),
        ),
      );
    }
    if (views.isEmpty) return const SizedBox();
    if (stripMode) {
      return GestureDetector(
        onTapUp: _tap,
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _input();
            final i = _stripIndex();
            if (i != anchorPage && i >= 0 && i < n) {
              pos = views.indexWhere((v) => v.pages.contains(i));
              if (pos < 0) pos = 0;
              _shown();
              setState(() {});
            }
            return false;
          },
          child: ListView.builder(
            controller: strip,
            itemCount: n + 1,
            itemBuilder: (_, i) => i == n ? _endCard() : _page(i, 0, screen.width, fitWidth: true),
          ),
        ),
      );
    }
    return GestureDetector(
      onTapUp: zoomed ? null : _tap,
      onDoubleTapDown: (d) {
        _input();
        if (zoomed) {
          zoom.value = Matrix4.identity();
          setState(() => zoomed = false);
        } else {
          final p = d.localPosition;
          zoom.value = Matrix4.identity()
            ..translateByDouble(-p.dx, -p.dy, 0, 1)
            ..scaleByDouble(2.2, 2.2, 1, 1);
          setState(() => zoomed = true);
        }
      },
      onDoubleTap: () {},
      child: PageView.builder(
        controller: pager,
        reverse: rtl,
        scrollDirection: dir == ReadDirection.ttb ? Axis.vertical : Axis.horizontal,
        physics: zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        itemCount: views.length + 1,
        onPageChanged: (i) {
          _input();
          if (i >= views.length) {
            // The "what's next" screen after the last page.
            return;
          }
          zoom.value = Matrix4.identity();
          zoomed = false;
          setState(() => pos = i);
          _shown();
        },
        itemBuilder: (_, i) {
          if (i >= views.length) return _endCard();
          final v = views[i];
          final w = screen.width / v.parts.length;
          final row = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final (pg, half) in v.parts) Flexible(child: _page(pg, half, w))],
          );
          if (i != pos) return row;
          return InteractiveViewer(
            transformationController: zoom,
            minScale: 1,
            maxScale: 6,
            onInteractionEnd: (_) {
              final z = zoom.value.getMaxScaleOnAxis() > 1.02;
              if (z != zoomed) setState(() => zoomed = z);
            },
            child: SizedBox(width: screen.width, height: screen.height, child: row),
          );
        },
      ),
    );
  }

  int _stripIndex() {
    if (!strip.hasClients) return anchorPage;
    // Estimate from the known page heights.
    var y = 0.0;
    final target = strip.offset + screen.height * 0.3;
    for (var i = 0; i < n; i++) {
      final s = sizes[i];
      y += s == null ? screen.width * 1.42 : screen.width * s.$2 / s.$1;
      if (y > target) return i;
    }
    return n - 1;
  }

  Widget _page(int i, int half, double width, {bool fitWidth = false}) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final s = sizes[i];
    Widget placeholder() => SizedBox(
          width: width,
          height: fitWidth ? (s == null ? width * 1.42 : width * s.$2 / s.$1) : screen.height,
          child: Center(child: Text('${i + 1}', style: ts(size: 28, c: Colors.white24, tab: true))),
        );
    return FutureBuilder<Uint8List>(
      key: ValueKey('p$i-$half'),
      future: _bytesFor(i),
      initialData: _bytes[i],
      builder: (_, snap) {
        final b = snap.data;
        if (b == null) {
          if (snap.hasError) {
            return SizedBox(
              width: width,
              height: fitWidth ? width : screen.height,
              child: Center(child: Text('Page ${i + 1} couldn\'t be loaded', style: ts(c: Colors.white54))),
            );
          }
          return placeholder();
        }
        final cw = (width * dpr * (half == 0 ? 1.5 : 3)).round();
        Widget im = Image.memory(b, fit: fitWidth ? BoxFit.fitWidth : BoxFit.contain, width: fitWidth ? width : null,
            cacheWidth: s != null && s.$1 < cw ? null : cw, gaplessPlayback: true, filterQuality: FilterQuality.medium);
        if (half != 0 && s != null) {
          im = AspectRatio(
            aspectRatio: s.$1 / 2 / s.$2,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: half == 1 ? Alignment.centerLeft : Alignment.centerRight,
                child: AspectRatio(aspectRatio: s.$1 / s.$2, child: Image.memory(b, fit: BoxFit.fill, cacheWidth: cw)),
              ),
            ),
          );
          return Center(child: im);
        }
        return fitWidth ? im : Center(child: im);
      },
    );
  }

  Widget _endCard() {
    final nx = nextChapter;
    return Container(
      color: Colors.black,
      height: stripMode ? 260 : null,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Finished ${t.displayTitle}', textAlign: TextAlign.center, style: ts(c: Colors.white, w: FontWeight.w700, size: 16)),
        const SizedBox(height: 16),
        if (nx != null) ...[
          Text('Next: ${nx.displayTitle}', textAlign: TextAlign.center, style: ts(c: Colors.white70)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _atEnd, child: const Text('Read next chapter')),
          const SizedBox(height: 8),
        ],
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ]),
    );
  }

  List<Widget> _controls() {
    final b = book;
    return [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Container(
          color: Colors.black.withValues(alpha: 0.82),
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(c: Colors.white, w: FontWeight.w600)),
                Text(
                    [
                      if (Store.I.isDownloaded(t)) 'Downloaded' else 'From ${Pc.I.pcName}',
                      if (b is RemoteBook && b.loaded.value < b.length) '${b.loaded.value} of ${b.length} pages loaded',
                    ].join(' · '),
                    style: ts(c: Colors.white54, size: 12)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white),
              tooltip: 'Save page on the PC',
              onPressed: _save,
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: 'Reading options',
              onPressed: _options,
            ),
          ]),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          color: Colors.black.withValues(alpha: 0.82),
          padding: EdgeInsets.fromLTRB(8, 6, 8, 8 + MediaQuery.of(context).padding.bottom),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.skip_previous, color: Colors.white),
              tooltip: 'Previous chapter',
              onPressed: prevChapter == null ? null : () => _open(prevChapter!, 0),
            ),
            Text('${anchorPage + 1}', style: ts(c: Colors.white, tab: true)),
            Expanded(
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Slider(
                  value: anchorPage.toDouble().clamp(0, max(0, n - 1).toDouble()),
                  min: 0,
                  max: max(1, n - 1).toDouble(),
                  onChanged: (v) {
                    _input();
                    anchorPage = v.round();
                    final i = views.indexWhere((x) => x.pages.contains(anchorPage));
                    if (i < 0) return;
                    if (stripMode) {
                      var y = 0.0;
                      for (var k = 0; k < anchorPage; k++) {
                        final s = sizes[k];
                        y += s == null ? screen.width * 1.42 : screen.width * s.$2 / s.$1;
                      }
                      strip.jumpTo(min(y, strip.position.maxScrollExtent));
                    } else {
                      pager?.jumpToPage(i);
                    }
                    setState(() {});
                  },
                ),
              ),
            ),
            Text('$n', style: ts(c: Colors.white54, tab: true)),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white),
              tooltip: 'Next chapter',
              onPressed: nextChapter == null ? null : _atEnd,
            ),
          ]),
        ),
      ),
    ];
  }

  Future<void> _options() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          void apply() {
            Settings.I.extra['m.ownReader'] = true;
            Settings.I.save();
            set(() {});
            _rebuild();
          }

          return SafeArea(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              Text('Reading direction for this title', style: ts(c: tk.sec)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ltr', label: Text('Left → right')),
                  ButtonSegment(value: 'rtl', label: Text('Right → left')),
                  ButtonSegment(value: 'ttb', label: Text('Down')),
                ],
                selected: {dir.name},
                onSelectionChanged: (x) {
                  t.direction = x.first == ss.direction.name ? null : x.first;
                  Db.I.updateReading(t);
                  apply();
                },
              ),
              if (dir == ReadDirection.ttb) ...[
                const SizedBox(height: 10),
                SegmentedButton<VerticalStyle>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: VerticalStyle.paged, label: Text('Page by page')),
                    ButtonSegment(value: VerticalStyle.strip, label: Text('Continuous strip')),
                  ],
                  selected: {ss.verticalStyle},
                  onSelectionChanged: (x) {
                    ss.verticalStyle = x.first;
                    apply();
                  },
                ),
              ],
              const SizedBox(height: 14),
              Text('Two pages side by side', style: ts(c: tk.sec)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'auto', label: Text('When unfolded')),
                  ButtonSegment(value: 'always', label: Text('Always')),
                  ButtonSegment(value: 'never', label: Text('Never')),
                ],
                selected: {Settings.I.get<String>('m.twoPages', 'auto')},
                onSelectionChanged: (x) {
                  Settings.I.extra['m.twoPages'] = x.first;
                  apply();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Cover on its own', style: ts()),
                value: ss.coverOffset,
                onChanged: (v) {
                  ss.coverOffset = v;
                  apply();
                },
              ),
              const SizedBox(height: 6),
              Text('Split wide pages', style: ts(c: tk.sec)),
              const SizedBox(height: 6),
              SegmentedButton<SplitMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SplitMode.off, label: Text('Off')),
                  ButtonSegment(value: SplitMode.split, label: Text('Split')),
                  ButtonSegment(value: SplitMode.singleOnly, label: Text('Folded only')),
                ],
                selected: {ss.split},
                onSelectionChanged: (x) {
                  ss.split = x.first;
                  apply();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Page number in the corner', style: ts()),
                value: Settings.I.pageNumbers,
                onChanged: (v) {
                  Settings.I.pageNumbers = v;
                  apply();
                },
              ),
            ]),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }
}
