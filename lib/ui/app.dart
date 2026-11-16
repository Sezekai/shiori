// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:window_manager/window_manager.dart';

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/settings.dart';
import 'appearance_page.dart';
import 'history_page.dart';
import 'library_page.dart';
import 'look.dart';
import 'reader.dart';
import 'saved_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'widgets.dart';

enum PageId { library, history, stats, saved, settings, look }

/// Where the app is: which screen, which section, what's open.
class Nav extends ChangeNotifier {
  Nav._();
  static final Nav I = Nav._();

  PageId page = PageId.library;
  Section section = Section.comics;
  bool railHidden = false;
  bool panelsHidden = false;
  bool logOpen = false;
  bool keysOpen = false;
  bool fullScreen = false;
  bool readerOpen = false;
  final FocusNode searchFocus = FocusNode();

  final List<(PageId, Section)> _history = [];
  final List<bool Function()> _backHandlers = [];

  void go(PageId p, [Section? s]) {
    final next = (p, s ?? section);
    if (next != (page, section)) {
      _history.add((page, section));
      if (_history.length > 50) _history.removeAt(0);
    }
    page = p;
    if (s != null) section = s;
    notifyListeners();
  }

  /// Screens add a handler while they have something to step back from
  /// (an open panel, a folder); the newest one goes first.
  void addBack(bool Function() h) => _backHandlers.add(h);
  void removeBack(bool Function() h) => _backHandlers.remove(h);

  /// The mouse's back button: closes the innermost thing, else the previous screen.
  void back() {
    if (keysOpen) {
      toggle('keys');
      return;
    }
    for (final h in _backHandlers.reversed.toList()) {
      if (h()) return;
    }
    if (_history.isNotEmpty) {
      final (p, s) = _history.removeLast();
      page = p;
      section = s;
      notifyListeners();
    }
  }

  void toggle(String what) {
    switch (what) {
      case 'rail':
        railHidden = !railHidden;
        Settings.I.windowState['railHidden'] = railHidden;
        Settings.I.save();
      case 'panels':
        panelsHidden = !panelsHidden;
      case 'log':
        logOpen = !logOpen;
      case 'keys':
        keysOpen = !keysOpen;
    }
    notifyListeners();
  }

  Future<void> toggleFullScreen() async {
    fullScreen = !fullScreen;
    try {
      await windowManager.setFullScreen(fullScreen);
    } catch (_) {}
    notifyListeners();
  }

  void changed() => notifyListeners();

  String get screenName => switch (page) {
        PageId.library => section.label,
        PageId.history => 'History',
        PageId.stats => 'Stats',
        PageId.saved => 'Saved pages',
        PageId.settings => 'Settings',
        PageId.look => 'Appearance',
      };
}

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

class ShioriApp extends StatelessWidget {
  const ShioriApp({super.key, this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Look.I,
      builder: (_, _) => MaterialApp(
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        title: 'Shiori',
        theme: Look.I.theme(),
        // Flutter's Windows accessibility bridge crashes (access violation in
        // AccessibilityBridge::CreateRemoveReparentedNodesUpdate) when a
        // Windows tool turns it on and the grid's layout changes quickly.
        // Shiori doesn't expose its controls to that bridge, so it stays off.
        builder: (context, child) => ExcludeSemantics(child: child ?? const SizedBox()),
        home: home ?? const Shell(),
      ),
    );
  }
}

bool get typingInField {
  final f = FocusManager.instance.primaryFocus;
  final ctx = f?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final FocusNode _focus = FocusNode(debugLabel: 'shell');

  @override
  void initState() {
    super.initState();
    Nav.I.railHidden = Settings.I.windowState['railHidden'] == true;
    AppLog.I.addListener(_onLog);
  }

  int _seenErrors = 0;
  void _onLog() {
    if (AppLog.I.errorCount > _seenErrors) {
      _seenErrors = AppLog.I.errorCount;
      if (!Nav.I.logOpen) {
        Nav.I.logOpen = true;
        Nav.I.changed();
      }
    }
  }

  @override
  void dispose() {
    AppLog.I.removeListener(_onLog);
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (Nav.I.readerOpen) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.escape) {
      if (Nav.I.keysOpen) {
        Nav.I.toggle('keys');
      } else if (Nav.I.panelsHidden) {
        Nav.I.toggle('panels');
      } else if (Nav.I.fullScreen) {
        Nav.I.toggleFullScreen();
      } else if (Nav.I.logOpen) {
        Nav.I.toggle('log');
      } else if (typingInField) {
        FocusScope.of(context).unfocus();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f11) {
      Nav.I.toggleFullScreen();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyF) {
      Nav.I.go(PageId.library);
      Nav.I.searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (typingInField || ctrl) return KeyEventResult.ignored;
    if (Nav.I.keysOpen && k != LogicalKeyboardKey.keyK) return KeyEventResult.handled;
    switch (k) {
      case LogicalKeyboardKey.keyK:
        Nav.I.toggle('keys');
      case LogicalKeyboardKey.slash:
        Nav.I.go(PageId.library);
        Nav.I.searchFocus.requestFocus();
      case LogicalKeyboardKey.keyF:
        Nav.I.toggleFullScreen();
      case LogicalKeyboardKey.keyH:
        Nav.I.toggle('panels');
      case LogicalKeyboardKey.keyL:
        Nav.I.toggle('log');
      case LogicalKeyboardKey.keyM:
        Nav.I.toggle('rail');
      case LogicalKeyboardKey.keyS:
        Nav.I.go(PageId.settings);
      case LogicalKeyboardKey.digit1:
        Nav.I.go(PageId.library, Section.comics);
      case LogicalKeyboardKey.digit2:
        Nav.I.go(PageId.library, Section.artbooks);
      case LogicalKeyboardKey.digit3:
        Nav.I.go(PageId.library, Section.manga);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) Nav.I.back();
      },
      child: Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: Nav.I,
        builder: (context, _) {
          final nav = Nav.I;
          return Scaffold(
            backgroundColor: tk.ground,
            body: Stack(children: [
              Column(children: [
                if (!nav.fullScreen) const TitleBar(),
                Expanded(
                  child: Row(children: [
                    if (!nav.railHidden && !nav.panelsHidden) const Rail(),
                    Expanded(child: _content(nav)),
                  ]),
                ),
                if (!nav.panelsHidden) const StatusBar(),
              ]),
              if (nav.logOpen) const Positioned(left: 0, right: 0, bottom: 36, child: LogDrawer()),
              if (nav.keysOpen) const KeysPopup(),
              const ToastLayer(),
            ]),
          );
        },
      ),
      ),
    );
  }

  Widget _content(Nav nav) {
    switch (nav.page) {
      case PageId.library:
        return LibraryPage(key: ValueKey(nav.section), section: nav.section);
      case PageId.history:
        return const HistoryPage();
      case PageId.stats:
        return const StatsPage();
      case PageId.saved:
        return const SavedPagesPage();
      case PageId.settings:
        return const SettingsPage();
      case PageId.look:
        return const AppearancePage();
    }
  }
}

// ---------------- title bar ----------------

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});
  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final bar = Container(
      height: 32,
      decoration: BoxDecoration(color: tk.ground, border: Border(bottom: BorderSide(color: tk.line))),
      child: Row(children: [
        const SizedBox(width: 12),
        Text('Shiori', style: ts(size: 12, w: FontWeight.w600)),
        ListenableBuilder(
          listenable: Nav.I,
          builder: (_, _) => Text('  ·  ${Nav.I.screenName}', style: ts(size: 12, c: tk.faint)),
        ),
        const Spacer(),
        const StatusPills(),
        if (isDesktop) const WindowButtons(),
      ]),
    );
    if (!isDesktop) return bar;
    return GestureDetector(
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: DragToMoveArea(child: bar),
    );
  }
}

class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});
  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool maxed = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) => mounted ? setState(() => maxed = v) : null);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => maxed = true);
  @override
  void onWindowUnmaximize() => setState(() => maxed = false);

  Widget _b(String glyph, VoidCallback onTap, String tip, {bool close = false}) => Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 700),
        child: Hoverable(
          builder: (h) => GestureDetector(
            onTap: onTap,
            child: Container(
              width: 46,
              height: 32,
              color: h ? (close ? const Color(0xFFE81123) : tk.raised2) : Colors.transparent,
              alignment: Alignment.center,
              child: CustomPaint(
                size: const Size(10, 10),
                painter: _GlyphPainter(glyph, h && close ? Colors.white : tk.sec),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(children: [
        _b('min', () => windowManager.minimize(), 'Minimise'),
        _b(maxed ? 'restore' : 'max', () => maxed ? windowManager.unmaximize() : windowManager.maximize(),
            maxed ? 'Restore' : 'Maximise'),
        _b('close', () => windowManager.close(), 'Close', close: true),
      ]);
}

/// The three window glyphs, drawn in the same 10 × 10 box with 1 px lines.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final String glyph;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final pt = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..isAntiAlias = glyph == 'close';
    switch (glyph) {
      case 'min':
        c.drawLine(Offset(0, s.height / 2 + 0.5), Offset(s.width, s.height / 2 + 0.5), pt);
      case 'max':
        c.drawRect(const Rect.fromLTWH(0.5, 0.5, 9, 9), pt);
      case 'restore':
        c.drawRect(const Rect.fromLTWH(0.5, 2.5, 7, 7), pt);
        c.drawPath(Path()
          ..moveTo(2.5, 2.5)
          ..lineTo(2.5, 0.5)
          ..lineTo(9.5, 0.5)
          ..lineTo(9.5, 7.5)
          ..lineTo(7.5, 7.5), pt);
      case 'close':
        c.drawLine(Offset.zero, Offset(s.width, s.height), pt);
        c.drawLine(Offset(s.width, 0), Offset(0, s.height), pt);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.glyph != glyph || o.color != color;
}

class StatusPills extends StatelessWidget {
  const StatusPills({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Jobs.I,
      builder: (_, _) {
        final j = Jobs.I.current;
        if (j == null) return const SizedBox();
        final f = j.fraction;
        final count = Jobs.I.queue.length;
        return GestureDetector(
          onTap: () => Nav.I.toggle('log'),
          child: Container(
            height: 22,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: lk.tint(tk.raised, 0.2), borderRadius: BorderRadius.circular(11)),
            child: Row(children: [
              Icon(Icons.circle, size: 7, color: j.stalled ? tk.warn : lk.acc),
              const SizedBox(width: 6),
              Text(
                  '${j.name}${j.total != null ? ' ${j.done}/${j.total}' : ''}${f != null ? ' · ${(f * 100).floor()}%' : ''}'
                  '${count > 0 ? ' · $count more queued' : ''}',
                  style: ts(size: 11.5, w: FontWeight.w600, tab: true)),
              const SizedBox(width: 8),
              SizedBox(width: 40, child: Progress(value: f, height: 4)),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------- rail ----------------

class Rail extends StatelessWidget {
  const Rail({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Nav.I, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final nav = Nav.I;
    Widget item(IconData icon, String label, bool active, VoidCallback onTap, {int? badge}) => Hoverable(
          builder: (h) => GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 56,
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: active ? tk.raised : (h ? tk.raised.withValues(alpha: 0.5) : null),
                  borderRadius: BorderRadius.circular(lk.rControl + 2),
                ),
                child: Column(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Icon(icon, size: 19, color: active ? lk.acc : tk.sec),
                    if (badge != null && badge > 0)
                      Positioned(
                        right: -10,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: lk.acc, borderRadius: BorderRadius.circular(8)),
                          child: Text('$badge', style: ts(size: 9.5, w: FontWeight.w700, c: lk.onAcc)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(label, style: ts(size: 11, c: active ? tk.text : tk.sec), textAlign: TextAlign.center,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ),
        );
    final lib = nav.page == PageId.library;
    return Container(
      width: 64,
      color: tk.rail,
      child: Column(children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(gradient: lk.grad, borderRadius: BorderRadius.circular(lk.rPanel)),
          child: Icon(Icons.bookmark_outline, size: 20, color: lk.onAcc),
        ),
        const SizedBox(height: 10),
        item(Icons.auto_stories_outlined, 'Comics', lib && nav.section == Section.comics,
            () => nav.go(PageId.library, Section.comics)),
        item(Icons.palette_outlined, 'Art Books', lib && nav.section == Section.artbooks,
            () => nav.go(PageId.library, Section.artbooks)),
        item(Icons.menu_book_outlined, 'Manga', lib && nav.section == Section.manga,
            () => nav.go(PageId.library, Section.manga)),
        item(Icons.history, 'History', nav.page == PageId.history, () => nav.go(PageId.history)),
        item(Icons.insights_outlined, 'Stats', nav.page == PageId.stats, () => nav.go(PageId.stats)),
        item(Icons.collections_outlined, 'Saved', nav.page == PageId.saved, () => nav.go(PageId.saved)),
        const Spacer(),
        Container(height: 1, width: 40, color: tk.line, margin: const EdgeInsets.symmetric(vertical: 6)),
        item(Icons.brush_outlined, 'Look', nav.page == PageId.look, () => nav.go(PageId.look)),
        item(Icons.settings_outlined, 'Settings', nav.page == PageId.settings, () => nav.go(PageId.settings)),
        item(Icons.keyboard_outlined, 'Keys', nav.keysOpen, () => nav.toggle('keys')),
        ListenableBuilder(
          listenable: AppLog.I,
          builder: (_, _) => item(Icons.receipt_long_outlined, 'Log', nav.logOpen, () => nav.toggle('log')),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ---------------- status bar ----------------

int _countVersion = -1;
int _count = 0;

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Jobs.I,
      builder: (_, _) {
        final j = Jobs.I.current;
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: tk.panel, border: Border(top: BorderSide(color: tk.line))),
          child: j == null ? _idle() : _running(j),
        );
      },
    );
  }

  Widget _idle() => Row(children: [
        Text('Ready', style: ts(w: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(Jobs.I.lastResult.isEmpty ? 'Nothing running' : Jobs.I.lastResult,
              style: ts(c: Jobs.I.lastFailed ? tk.danger : tk.sec), overflow: TextOverflow.ellipsis),
        ),
        _libCount(),
        const SizedBox(width: 10),
        Btn.ghost('Log', icon: Icons.receipt_long_outlined, dense: true, onTap: () => Nav.I.toggle('log')),
      ]);

  Widget _libCount() => ListenableBuilder(
        listenable: Library.I,
        builder: (_, _) {
          if (_countVersion != Library.I.version) {
            _countVersion = Library.I.version;
            _count = Section.values.fold<int>(
                0, (a, s) => a + Library.I.titles(s).where((t) => !t.missing && !t.isContainer).length);
          }
          return Text('$_count titles', style: ts(c: tk.faint, tab: true));
        },
      );

  Widget _running(Job j) {
    final f = j.fraction;
    final left = j.timeLeft;
    final queued = Jobs.I.queue.length;
    final stall = j.stalled;
    final stallFor = DateTime.now().difference(j.lastProgress).inSeconds;
    return Row(children: [
      Text(j.name, style: ts(w: FontWeight.w600)),
      const SizedBox(width: 8),
      Flexible(
        flex: 3,
        child: Text(
            '${j.detail}${j.total != null ? ' · ${j.done} of ${j.total}' : ''}${queued > 0 ? ' · $queued more queued' : ''}',
            style: ts(c: tk.sec, tab: true),
            overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: 12),
      SizedBox(width: 180, child: Progress(value: j.paused ? f : f)),
      const SizedBox(width: 8),
      SizedBox(
          width: 38,
          child: Text(f == null ? '' : '${(f * 100).floor()}%', style: ts(tab: true, w: FontWeight.w600))),
      Flexible(
        flex: 3,
        child: Text(
          j.paused
              ? 'Paused · ${formatDuration(j.elapsed)} elapsed'
              : stall
                  ? 'No progress for $stallFor s · the log shows what is running · ${formatDuration(j.elapsed)} elapsed'
                  : '${formatDuration(j.elapsed)} elapsed · ${f == null ? 'size not known yet' : left == null ? 'working out time left…' : humanLeft(left)}',
          style: ts(c: stall ? tk.warn : tk.sec, tab: true),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      if (j.canPause) Btn.ghost(j.paused ? 'Resume' : 'Pause', dense: true, onTap: Jobs.I.togglePause),
      Btn.ghost('Stop', dense: true, icon: Icons.stop_circle_outlined, onTap: Jobs.I.stop),
      Btn.ghost('Log', dense: true, icon: Icons.receipt_long_outlined, onTap: () => Nav.I.toggle('log')),
    ]);
  }
}

// ---------------- log drawer ----------------

class LogDrawer extends StatelessWidget {
  const LogDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: tk.panel,
        border: Border(top: BorderSide(color: tk.line2)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
          child: Row(children: [
            Text('Log', style: ts(w: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(child: Text(AppLog.I.logDir ?? '', style: ts(c: tk.faint, size: 11.5, mono: true), overflow: TextOverflow.ellipsis)),
            Btn.ghost('Copy', dense: true, onTap: () {
              Clipboard.setData(ClipboardData(text: AppLog.I.lines.join('\n')));
              toast('Log copied');
            }),
            Btn.ghost('Clear', dense: true, onTap: AppLog.I.clear),
            Btn.ghost('Close', dense: true, onTap: () => Nav.I.toggle('log')),
          ]),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: AppLog.I,
            builder: (_, _) {
              final lines = AppLog.I.lines;
              return Container(
                color: tk.field,
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: lines.length,
                  itemBuilder: (_, i) {
                    final l = lines[lines.length - 1 - i];
                    return Text(l,
                        style: ts(
                            mono: true,
                            size: 11.5,
                            c: l.contains('ERROR') ? tk.danger : l.contains('WARN') ? tk.warn : tk.sec));
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------- keyboard shortcuts popup ----------------

const keyGroups = <(String, List<(String, String)>)>[
  ('Anywhere', [
    ('K', 'Keyboard shortcuts'),
    ('/', 'Search the library'),
    ('Ctrl+F', 'Search the library'),
    ('F, F11', 'Full screen'),
    ('H', 'Hide panels'),
    ('M', 'Show or hide the sidebar'),
    ('L', 'Open or close the log'),
    ('S', 'Settings'),
    ('1 2 3', 'Comics, Art Books, Manga'),
    ('Esc', 'Close, innermost first'),
    ('Mouse back', 'Go back: close panels, up a folder, previous screen'),
  ]),
  ('Library', [
    ('Click', 'Show its details on the right'),
    ('Click again', 'Read or continue'),
    ('Right-click', 'More: adjust the cover, cover page…'),
    ('Ctrl+click', 'Tick'),
    ('Shift+click', 'Tick a range'),
    ('Ctrl+A', 'Tick everything shown'),
    ('R', 'Random title'),
    ('+ −, Ctrl+wheel', 'Bigger or smaller covers'),
    ('Backspace', 'Up one folder (comics)'),
  ]),
  ('Reader', [
    ('← →', 'Previous / next, following the reading direction'),
    ('PgUp PgDn', 'Previous / next'),
    ('Space', 'Show or hide the controls'),
    ('Mouse back', 'Close the reader'),
    ('Home End', 'First / last page'),
    ('↑ ↓', 'Zoom (scroll in strip mode)'),
    ('0, 1', 'Fit; actual size'),
    ('D', 'Single or two pages'),
    ('O', 'Offset the cover'),
    ('C', 'Crop borders'),
    ('P', 'Save page'),
    ('V', 'Favourite'),
    ('N', 'Next file'),
    ('G', 'Page strip'),
    ('Esc', 'Close the reader'),
  ]),
  ('Dialogs', [
    ('Enter', 'Confirm'),
    ('Esc', 'Cancel'),
  ]),
];

class KeysPopup extends StatelessWidget {
  const KeysPopup({super.key});
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => Nav.I.toggle('keys'),
        child: Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: LayoutBuilder(builder: (context, c) {
              final maxW = c.maxWidth - 48;
              final maxH = c.maxHeight - 48;
              final cols = (maxW / 340).floor().clamp(1, 4);
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cols * 340.0 + 40, maxHeight: maxH),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: tk.panel,
                    borderRadius: BorderRadius.circular(lk.rPanel),
                    border: Border.all(color: tk.line2),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Keyboard shortcuts', style: ts(size: lk.fontSize + 2, w: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Text('K or Esc closes', style: ts(size: 12, c: tk.faint)),
                    ]),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          children: [
                            for (final g in keyGroups)
                              SizedBox(
                                width: 320,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(g.$1, style: ts(size: 12, c: tk.sec, w: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  for (final k in g.$2)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(children: [
                                        SizedBox(
                                          width: 120,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                  color: tk.raised,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: tk.line2)),
                                              child: Text(k.$1, style: ts(mono: true, size: 11.5)),
                                            ),
                                          ),
                                        ),
                                        Expanded(child: Text(k.$2, style: ts(c: tk.sec))),
                                      ]),
                                    ),
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Opens the reader full-window over everything.
Future<void> openReader(BuildContext context, Title t, {List<Title>? context_, int? startPage}) async {
  Nav.I.readerOpen = true;
  await Navigator.of(context).push(PageRouteBuilder(
    pageBuilder: (_, _, _) => ReaderPage(title: t, queue: context_ ?? [t], startPage: startPage),
    transitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
  Nav.I.readerOpen = false;
  Library.I.changed();
}

