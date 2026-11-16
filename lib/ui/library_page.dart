import 'dart:convert';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/settings.dart';
import '../core/yacreader.dart';
import 'app.dart';
import 'covers.dart';
import 'info_panel.dart';
import 'filters_panel.dart';
import 'tags_view.dart';
import 'title_page.dart';
import 'widgets.dart';

enum LibTab { library, tags, artists, check }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.section});
  final Section section;
  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage> {
  Section get s => widget.section;
  SectionSettings get ss => Settings.I.of(s);
  LibFilter get f => Library.I.filters[s]!;

  LibTab tab = LibTab.library;
  String folder = '';
  Entry? open; // the full title page
  Entry? selected; // shown in the side panel
  final Set<int> ticked = {};
  int? lastTickIndex;
  late final TextEditingController search = TextEditingController(text: f.search);
  final ScrollController scroll = ScrollController();
  final FocusNode _keys = FocusNode(debugLabel: 'library');
  List<Entry> _entries = [];
  String _entriesKey = '';

  /// For the self-test.
  static LibraryPageState? active;
  void selectFirst() {
    if (_entries.isNotEmpty) setState(() => selected = _entries.first);
  }

  @override
  void initState() {
    super.initState();
    active = this;
    Nav.I.addBack(_back);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferYac());
  }

  /// Mouse back: full page → side panel → ticks → up a folder.
  bool _back() {
    if (!mounted || Nav.I.page != PageId.library) return false;
    if (open != null) {
      setState(() => open = null);
      return true;
    }
    if (selected != null) {
      setState(() => selected = null);
      return true;
    }
    if (ticked.isNotEmpty) {
      setState(ticked.clear);
      return true;
    }
    if (tab != LibTab.library) {
      setState(() => tab = LibTab.library);
      return true;
    }
    if (folder.isNotEmpty) {
      setState(() => folder = p.dirname(folder) == '.' ? '' : p.dirname(folder));
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    Nav.I.removeBack(_back);
    search.dispose();
    scroll.dispose();
    _keys.dispose();
    super.dispose();
  }

  Future<void> _maybeOfferYac() async {
    if (Settings.I.yacImportOffered || !mounted) return;
    final libs = YacImport.findLibraries();
    if (libs.isEmpty) return;
    final total = Section.values.fold<int>(0, (a, x) => a + Library.I.titles(x).length);
    if (total == 0) return; // offer after the first scan
    Settings.I.yacImportOffered = true;
    Settings.I.save();
    final ok = await confirm(
        context,
        'Import from YACReader?',
        'Shiori found ${libs.length} YACReader ${libs.length == 1 ? 'library' : 'libraries'} in your folders. '
            'It can bring in read marks, the page you were on, ratings, favourites, and labels and reading lists '
            '(as tags). Your YACReader files aren\'t changed. This can also be done later from Settings.',
        confirmLabel: 'Import');
    if (ok) YacImport.queue();
  }

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Library.I, Settings.I]),
      builder: (context, _) {
        if (open != null) {
          final e = open!;
          return TitlePage(
            entry: e,
            onBack: () => setState(() => open = null),
            onOpenArtist: (a) => setState(() {
              open = null;
              tab = LibTab.library;
              f.artists = {a};
              f.excludeArtists.remove(a);
            }),
          );
        }
        final sel = _currentSelection();
        return Focus(
          focusNode: _keys,
          onKeyEvent: _onKey,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!Nav.I.panelsHidden) _header(),
                  if (!Nav.I.panelsHidden) const SizedBox(height: 8),
                  if (!Nav.I.panelsHidden) _toolbar(),
                  ..._banners(),
                  const SizedBox(height: 8),
                  Expanded(child: _body()),
                ]),
              ),
            ),
            if (sel != null && !Nav.I.panelsHidden)
              InfoPanel(
                key: ValueKey(sel.id),
                entry: sel,
                onClose: () => setState(() => selected = null),
                onExpand: () => setState(() => open = sel),
                onRead: (t, page) => openReader(context, t, context_: _readingQueueFrom(sel, t), startPage: page),
                onOpenArtist: (a) => setState(() {
                  selected = null;
                  tab = LibTab.library;
                  f.artists = {a};
                  f.excludeArtists.remove(a);
                }),
              ),
          ]),
        );
      },
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || typingInField) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyA) {
      setState(() => ticked.addAll(_entries.expand((x) => x.titles).map((t) => t.id)));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyR && !ctrl) {
      _random();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace && folder.isNotEmpty) {
      setState(() => folder = p.dirname(folder) == '.' ? '' : p.dirname(folder));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.equal || e.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _size(ss.tileSize + 20);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.minus || e.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _size(ss.tileSize - 20);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape && ticked.isNotEmpty) {
      setState(ticked.clear);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _size(double v) {
    ss.tileSize = v.clamp(110, 480);
    Settings.I.save();
  }

  void _random() {
    final list = _entries.where((e) => e is! FolderEntry).toList();
    if (list.isEmpty) {
      toast('Nothing to pick from with these filters', ToastKind.info);
      return;
    }
    setState(() => open = list[Random().nextInt(list.length)]);
  }

  Widget _header() {
    final count = Library.I.titles(s).where((t) => !t.missing).length;
    final desc = switch (s) {
      Section.manga => 'Your manga and doujinshi, grouped into series where there are several chapters.',
      Section.comics => 'Your comics, by folder in your reading order, or by series.',
      Section.artbooks => 'Your art books and guides.',
    };
    return Row(children: [
      Text(s.label, style: ts(size: 15, w: FontWeight.w700)),
      const SizedBox(width: 10),
      Expanded(child: Text('$desc  ·  $count titles', style: ts(c: tk.sec), overflow: TextOverflow.ellipsis)),
      Seg<LibTab>(
        value: tab,
        items: const [
          (LibTab.library, 'Library'),
          (LibTab.tags, 'Tags'),
          (LibTab.artists, 'Artists'),
          (LibTab.check, 'Check titles'),
        ],
        onChanged: (v) => setState(() => tab = v),
      ),
    ]);
  }

  Widget _toolbar() {
    final presets = ss.presets;
    return PanelBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Field(
              controller: search,
              focusNode: Nav.I.searchFocus,
              hint: 'Search titles, Japanese titles, artists and tags  ( / )',
              icon: Icons.search,
              onChanged: (v) {
                f.search = v;
                Library.I.changed();
              },
            ),
          ),
          const SizedBox(width: 8),
          Btn('Filters${f.isEmpty ? '' : ' •'}', icon: Icons.filter_list, onTap: _filters),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '',
            onSelected: (v) => _preset(v),
            itemBuilder: (_) => [
              for (final name in presets.keys) PopupMenuItem(value: 'apply:$name', child: Text(name, style: ts())),
              if (presets.isNotEmpty) const PopupMenuDivider(),
              PopupMenuItem(value: 'save', child: Text('Save current filters and sort…', style: ts())),
              for (final name in presets.keys)
                PopupMenuItem(value: 'delete:$name', child: Text('Delete "$name"', style: ts(c: tk.danger))),
            ],
            child: const IgnorePointer(child: Btn('Presets', icon: Icons.bookmarks_outlined, onTap: _noop)),
          ),
          const SizedBox(width: 8),
          Btn('Random', icon: Icons.casino_outlined, tooltip: 'Open a random title from what\'s shown (R)', onTap: _random),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: Jobs.I,
            builder: (_, _) => Btn.primary(
              Jobs.I.isQueued('Scanning ${s.label}') ? 'Scan queued' : (Jobs.I.current != null ? 'Add scan to the queue' : 'Scan ${s.label}'),
              icon: Icons.refresh,
              onTap: () => Library.I.scan(s),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Seg<bool>(
            value: ss.listView,
            items: const [(false, 'Grid'), (true, 'List')],
            onChanged: (v) {
              ss.listView = v;
              Settings.I.save();
            },
          ),
          if (!ss.listView)
            Drop<String>(
              value: ss.gridStyle,
              items: const [
                ('comfortable', 'Comfortable'),
                ('compact', 'Compact'),
                ('cover', 'Cover only'),
                ('staggered', 'Staggered'),
              ],
              onChanged: (v) {
                ss.gridStyle = v;
                Settings.I.save();
              },
            ),
          if (s == Section.comics)
            Seg<bool>(
              value: ss.comicsFolderView,
              items: const [(true, 'Folders'), (false, 'Series')],
              onChanged: (v) {
                ss.comicsFolderView = v;
                folder = '';
                Settings.I.save();
              },
            ),
          Text('Sort', style: ts(c: tk.sec)),
          Drop<String>(
            value: ss.sort,
            items: [for (final e in sortKeys.entries) (e.key, e.value)],
            onChanged: (v) {
              ss.sort = v;
              if (v == 'random') Library.I.reshuffle();
              Settings.I.save();
            },
          ),
          IconBtn(ss.sortDesc ? Icons.arrow_downward : Icons.arrow_upward,
              tooltip: ss.sortDesc ? 'Descending' : 'Ascending', onTap: () {
            ss.sortDesc = !ss.sortDesc;
            Settings.I.save();
          }),
          const SizedBox(width: 8),
          if (!ss.listView) ...[
            Seg<bool>(
              value: ss.coverFill,
              items: const [(true, 'Fill'), (false, 'Fit')],
              onChanged: (v) {
                ss.coverFill = v;
                Settings.I.save();
              },
            ),
            Tooltip(
              message: 'Rounded corners on covers',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.rounded_corner, size: 16, color: tk.sec),
                SizedBox(
                  width: 90,
                  child: Slider(
                    value: ss.coverRadius.clamp(0, 24),
                    min: 0,
                    max: 24,
                    onChanged: (v) {
                      ss.coverRadius = v.roundToDouble();
                      Settings.I.changedQuiet();
                    },
                    onChangeEnd: (_) => Settings.I.save(),
                  ),
                ),
              ]),
            ),
          ],
          Icon(Icons.photo_size_select_large, size: 16, color: tk.sec),
          SizedBox(
            width: 140,
            child: Slider(
              value: ss.tileSize.clamp(110, 480),
              min: 110,
              max: 480,
              onChanged: (v) {
                ss.tileSize = v;
                Settings.I.changedQuiet();
              },
              onChangeEnd: (_) => Settings.I.save(),
            ),
          ),
        ]),
      ]),
    );
  }

  static void _noop() {}

  void _preset(String v) async {
    if (v == 'save') {
      final name = await ask(context, 'Save as a preset', body: 'The current filters and sort are saved under this name.',
          confirmLabel: 'Save preset');
      if (name == null || name.isEmpty) return;
      ss.presets[name] = '${ss.sort}|${ss.sortDesc}|${_json(f.toJson())}';
      Settings.I.save();
      toast('Saved preset "$name"');
    } else if (v.startsWith('apply:')) {
      final raw = ss.presets[v.substring(6)];
      if (raw == null) return;
      final parts = raw.split('|');
      ss.sort = parts[0];
      ss.sortDesc = parts[1] == 'true';
      final nf = LibFilter.fromJson(_unjson(parts.sublist(2).join('|')));
      Library.I.filters[s] = nf;
      search.text = nf.search;
      Settings.I.save();
    } else if (v.startsWith('delete:')) {
      ss.presets.remove(v.substring(7));
      Settings.I.save();
    }
  }

  void _filters() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => FiltersPanel(section: s),
    );
    search.text = f.search;
    Library.I.changed();
  }

  List<Widget> _banners() {
    final out = <Widget>[];
    final un = Library.I.unavailableRoots[s]!;
    if (un.isNotEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Banner1(
          icon: Icons.usb_off,
          lead: 'Drive not connected.',
          text: '${un.join(', ')} can\'t be reached. The library still shows what was found before.',
          action: Btn('Retry', onTap: () => Library.I.scan(s)),
        ),
      ));
    }
    if (ss.folders.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Banner1(
          icon: Icons.create_new_folder_outlined,
          lead: 'No folders yet.',
          text: 'Add the folders that hold your ${s.label.toLowerCase()} in Settings.',
          action: Btn('Open Settings', onTap: () => Nav.I.go(PageId.settings)),
        ),
      ));
    }
    final pills = <Widget>[];
    void tri(String label, Tri v, void Function() clear) {
      if (v != Tri.any) pills.add(Pill(label, active: true, negative: v == Tri.no, onClose: clear));
    }

    tri('Read', f.read, () => f.read = Tri.any);
    tri('In progress', f.inProgress, () => f.inProgress = Tri.any);
    tri('Favourite', f.favourite, () => f.favourite = Tri.any);
    tri('Rated', f.rated, () => f.rated = Tri.any);
    tri('Series', f.series, () => f.series = Tri.any);
    tri('Needs a check', f.needsCheck, () => f.needsCheck = Tri.any);
    tri('Rating ${f.minRating}–${f.maxRating}', f.ratingRange, () => f.ratingRange = Tri.any);
    tri('Read ${f.readCountMin}+ times', f.readCount, () => f.readCount = Tri.any);
    tri('${f.minPages}–${f.maxPages} pages', f.pageRange, () => f.pageRange = Tri.any);
    tri('${f.minSizeMb}–${f.maxSizeMb} MB', f.sizeRange, () => f.sizeRange = Tri.any);
    tri('Read in the last ${f.readInDays} days', f.readIn, () => f.readIn = Tri.any);
    for (final a in f.artists) {
      pills.add(Pill(a, active: true, onClose: () => f.artists.remove(a)));
    }
    for (final a in f.excludeArtists) {
      pills.add(Pill(a, active: true, negative: true, onClose: () => f.excludeArtists.remove(a)));
    }
    for (final id in f.tags) {
      final t = Library.I.tagById(s, id);
      if (t != null) pills.add(Pill(t.name, active: true, color: Color(t.color), onClose: () => f.tags.remove(id)));
    }
    for (final id in f.excludeTags) {
      final t = Library.I.tagById(s, id);
      if (t != null) {
        pills.add(Pill(t.name, active: true, negative: true, color: Color(t.color), onClose: () => f.excludeTags.remove(id)));
      }
    }
    if (pills.isNotEmpty && tab == LibTab.library) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          ...pills.map((pl) => GestureDetector(onTap: Library.I.changed, child: pl)),
          Btn.ghost('Clear filters', dense: true, onTap: () {
            final keep = f.search;
            Library.I.filters[s] = LibFilter()..search = keep;
            Library.I.changed();
          }),
        ]),
      ));
    }
    if (ticked.isNotEmpty) out.add(Padding(padding: const EdgeInsets.only(top: 8), child: _selectionBar()));
    return out;
  }

  List<Title> get _tickedTitles => ticked.map(Library.I.byId).whereType<Title>().toList();

  Widget _selectionBar() {
    final ts_ = _tickedTitles;
    return Container(
      height: lk.hControl + 10,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: lk.tint(tk.panel, 0.12),
        borderRadius: BorderRadius.circular(lk.rPanel),
        border: Border.all(color: lk.acc.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Text('${ts_.length} ticked', style: ts(w: FontWeight.w600)),
        const SizedBox(width: 12),
        Btn('Mark read', icon: Icons.done_all, dense: true, onTap: () => Library.I.markRead(ts_, true)),
        const SizedBox(width: 6),
        Btn('Mark unread', icon: Icons.remove_done, dense: true, onTap: () async {
          if (await confirm(context, 'Mark ${ts_.length} as unread?',
              'Read marks you set by hand are removed. Real reading history is kept.', confirmLabel: 'Mark unread')) {
            Library.I.markRead(ts_, false);
          }
        }),
        const SizedBox(width: 6),
        Btn('Favourite', icon: Icons.favorite_border, dense: true, onTap: () => Library.I.toggleFavourite(ts_)),
        const SizedBox(width: 6),
        TagMenu(section: s, titles: ts_),
        const Spacer(),
        Btn.ghost('Clear ticks', dense: true, onTap: () => setState(ticked.clear)),
      ]),
    );
  }

  Widget _body() {
    switch (tab) {
      case LibTab.tags:
        return TagsView(section: s, onOpen: (e) => setState(() => open = e));
      case LibTab.artists:
        return ArtistsView(section: s, onPick: (a) => setState(() {
              tab = LibTab.library;
              f.artists = {a};
            }));
      case LibTab.check:
        return CheckTitlesView(section: s);
      case LibTab.library:
        break;
    }
    final key = '${Library.I.version}|$folder|${ss.sort}|${ss.sortDesc}|${ss.comicsFolderView}|${jsonEncode(f.toJson())}';
    if (key != _entriesKey) {
      _entries = Library.I.entries(s, folder: folder);
      _entriesKey = key;
    }
    final crumbs = s == Section.comics && ss.comicsFolderView ? _breadcrumbs() : null;
    if (_entries.isEmpty) {
      final hasAny = Library.I.titles(s).isNotEmpty;
      return Column(children: [
        if (crumbs != null) crumbs,
        Expanded(
          child: EmptyState(
            icon: hasAny ? Icons.filter_alt_off_outlined : Icons.menu_book_outlined,
            text: hasAny
                ? 'Nothing matches these filters.'
                : 'Your ${s.label.toLowerCase()} show up here after a scan.',
            action: hasAny
                ? Btn('Clear filters', onTap: () {
                    Library.I.filters[s] = LibFilter();
                    search.clear();
                    Library.I.changed();
                  })
                : Btn.primary('Scan ${s.label}', onTap: () => Library.I.scan(s)),
          ),
        ),
      ]);
    }
    final view = ss.listView ? _list() : _grid();
    return Column(children: [
      if (crumbs != null) crumbs,
      Expanded(
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
              _size(ss.tileSize - e.scrollDelta.dy / 4);
            }
          },
          child: view,
        ),
      ),
    ]);
  }

  Widget _breadcrumbs() {
    final parts = folder.isEmpty ? <String>[] : folder.split(p.separator);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        IconBtn(Icons.arrow_upward, tooltip: 'Up one folder (Backspace)', onTap: folder.isEmpty
            ? null
            : () => setState(() => folder = parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join(p.separator))),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() => folder = ''),
          child: Text('All comics', style: ts(c: folder.isEmpty ? tk.text : tk.sec, w: FontWeight.w600)),
        ),
        for (var i = 0; i < parts.length; i++) ...[
          Text('  ›  ', style: ts(c: tk.faint)),
          GestureDetector(
            onTap: () => setState(() => folder = parts.sublist(0, i + 1).join(p.separator)),
            child: Text(parts[i], style: ts(c: i == parts.length - 1 ? tk.text : tk.sec, w: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }

  void _tap(Entry e, int index) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl || shift || (Settings.I.clickAction == 'tick' && e is! FolderEntry)) {
      setState(() {
        if (shift && lastTickIndex != null) {
          final a = min(lastTickIndex!, index), b = max(lastTickIndex!, index);
          for (var i = a; i <= b; i++) {
            ticked.addAll(_entries[i].titles.map((t) => t.id));
          }
        } else {
          final ids = e.titles.map((t) => t.id);
          if (ids.every(ticked.contains)) {
            ticked.removeAll(ids);
          } else {
            ticked.addAll(ids);
          }
        }
        lastTickIndex = index;
      });
      return;
    }
    if (e is FolderEntry) {
      setState(() => folder = e.relPath);
      return;
    }
    // First click shows it in the side panel; clicking it again opens it.
    if (selected?.id == e.id) {
      _read(e);
    } else {
      setState(() => selected = e);
    }
  }

  /// The selected entry, refreshed from the latest list so it shows current data.
  Entry? _currentSelection() {
    final sel = selected;
    if (sel == null) return null;
    for (final e in _entries) {
      if (e.id == sel.id) return e;
    }
    return sel;
  }

  List<Title> _readingQueueFrom(Entry e, Title start) {
    if (e is TitleEntry) return _readingQueue(e);
    final ts_ = e.titles;
    final i = ts_.indexWhere((x) => x.id == start.id);
    return [...ts_.sublist(max(0, i)), ..._readingQueue(e).where((x) => !ts_.contains(x))];
  }

  void _read(Entry e) {
    if (e is FolderEntry) {
      setState(() => folder = e.relPath);
      return;
    }
    final queue = _readingQueue(e);
    final start = _continueTitle(e);
    openReader(context, start, context_: queue);
  }

  /// The order "next file" follows: the series, then the list it came from.
  List<Title> _readingQueue(Entry from) {
    final out = <Title>[];
    final i = _entries.indexWhere((e) => e.id == from.id);
    for (final e in [..._entries.sublist(max(0, i)), ..._entries.sublist(0, max(0, i))]) {
      if (e is FolderEntry) continue;
      out.addAll(e.titles);
    }
    return out;
  }

  Title _continueTitle(Entry e) {
    if (e is TitleEntry) return e.t;
    final ts_ = e.titles;
    final inProg = ts_.where((t) => t.inProgress).toList()..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    if (inProg.isNotEmpty) return inProg.first;
    return ts_.firstWhere((t) => !t.isRead, orElse: () => ts_.first);
  }

  Widget _grid() {
    final style = ss.gridStyle;
    Widget card(int i, double width) {
      final e = _entries[i];
      return CoverCard(
        entry: e,
        style: style,
        width: width,
        radius: ss.coverRadius,
        fill: ss.coverFill,
        selected: selected?.id == e.id,
        ticked: e is! FolderEntry && e.titles.every((t) => ticked.contains(t.id)),
        anyTicked: ticked.isNotEmpty,
        onTap: () => _tap(e, i),
        onMenu: (pos) => _cardMenu(e, pos),
        onTick: () {
          final ids = e.titles.map((t) => t.id);
          setState(() => ids.every(ticked.contains) ? ticked.removeAll(ids) : ticked.addAll(ids));
          lastTickIndex = i;
        },
      );
    }

    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final cols = max(1, ((c.maxWidth + gap) / (ss.tileSize + gap)).ceil());
      final cw = (c.maxWidth - gap * (cols - 1)) / cols;
      if (style == 'staggered') {
        return MasonryGridView.count(
          controller: scroll,
          crossAxisCount: cols,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          itemCount: _entries.length,
          itemBuilder: (_, i) => card(i, cw),
        );
      }
      final text = style == 'comfortable' ? CoverCard.textHeight(cw) : 0.0;
      return GridView.builder(
        controller: scroll,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          mainAxisExtent: (cw - 2) * 1.42 + 2 + text,
        ),
        itemCount: _entries.length,
        itemBuilder: (_, i) => card(i, cw),
      );
    });
  }

  Future<void> _cardMenu(Entry e, Offset at) async {
    if (e is FolderEntry) return;
    final t = e.cover;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        PopupMenuItem(value: 'read', child: Text(e.titles.any((x) => x.inProgress) ? 'Continue reading' : 'Read', style: ts())),
        PopupMenuItem(value: 'info', child: Text('Show details', style: ts())),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'adjust', child: Text('Adjust the cover…', style: ts())),
        PopupMenuItem(value: 'page', child: Text('Choose the cover page…', style: ts())),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'fav', child: Text(e.titles.every((x) => x.favourite) ? 'Not a favourite' : 'Favourite', style: ts())),
        PopupMenuItem(value: 'mark', child: Text(e.titles.every((x) => x.isRead) ? 'Mark unread' : 'Mark read', style: ts())),
      ],
    );
    if (!mounted) return;
    switch (v) {
      case 'read':
        _read(e);
      case 'info':
        setState(() => selected = e);
      case 'adjust':
        await adjustCover(context, t, ss.coverRadius);
      case 'page':
        await chooseCoverPage(context, t);
      case 'fav':
        Library.I.toggleFavourite(e.titles);
      case 'mark':
        Library.I.markRead(e.titles, !e.titles.every((x) => x.isRead));
    }
  }

  Widget _list() {
    final thumb = (ss.tileSize / 4).clamp(18.0, 160.0);
    Widget head(String label, String key, {double? w, bool flex = false}) {
      final active = ss.sort == key;
      final cell = GestureDetector(
        onTap: () {
          if (ss.sort == key) {
            ss.sortDesc = !ss.sortDesc;
          } else {
            ss.sort = key;
            ss.sortDesc = false;
          }
          Settings.I.save();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(children: [
            Flexible(child: Text(label, style: ts(size: 12, w: FontWeight.w600, c: tk.sec), overflow: TextOverflow.ellipsis)),
            if (active) Icon(ss.sortDesc ? Icons.arrow_drop_down : Icons.arrow_drop_up, size: 16, color: lk.acc),
          ]),
        ),
      );
      return flex ? Expanded(child: cell) : SizedBox(width: w, child: cell);
    }

    return Container(
      decoration: BoxDecoration(color: tk.field, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
      child: Column(children: [
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: tk.panel,
          child: Row(children: [
            const SizedBox(width: 28),
            SizedBox(width: thumb + 8),
            head('Title', 'title', flex: true),
            head('Artist', 'artist', w: 170),
            head('Pages', 'pages', w: 64),
            head('Size', 'size', w: 80),
            head('Rating', 'rating', w: 100),
            head('Read', 'readCount', w: 56),
            head('Last read', 'lastRead', w: 110),
            head('Progress', 'progress', w: 90),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: _entries.length,
            itemExtent: max(lk.hRow, thumb * 1.4 + 6),
            itemBuilder: (_, i) {
              final e = _entries[i];
              final t = e.cover;
              final isTicked = e is! FolderEntry && e.titles.every((x) => ticked.contains(x.id));
              final size = e.titles.fold<int>(0, (a, x) => a + x.size);
              final pages = e.titles.fold<int>(0, (a, x) => a + x.pages);
              final reads = e.titles.fold<int>(0, (a, x) => a + x.readCount);
              final last = e.titles.map((x) => x.lastReadAt).reduce(max);
              return Hoverable(
                builder: (h) => GestureDetector(
                  onTap: () => _tap(e, i),
                  onSecondaryTapDown: (d) => _cardMenu(e, d.globalPosition),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    color: isTicked || selected?.id == e.id ? lk.tint(tk.field, 0.17) : (h ? tk.raised : null),
                    child: Row(children: [
                      SizedBox(
                        width: 28,
                        child: e is FolderEntry
                            ? Icon(Icons.folder_outlined, size: 16, color: tk.sec)
                            : Checkbox(value: isTicked, onChanged: (_) {
                                final ids = e.titles.map((x) => x.id);
                                setState(() => isTicked ? ticked.removeAll(ids) : ticked.addAll(ids));
                              }),
                      ),
                      SizedBox(width: thumb + 8, child: Align(alignment: Alignment.centerLeft,
                          child: SizedBox(width: thumb, height: thumb * 1.4, child: CoverThumb(title: t)))),
                      Expanded(
                        child: Text(
                          e is GroupEntry ? '${e.name}  ·  ${e.readChapters}/${e.titles.length} chapters' : e.name,
                          style: ts(c: t.missing ? tk.faint : tk.text),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 170, child: Text(t.displayArtist ?? '', style: ts(c: tk.sec), overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 64, child: Text('$pages', style: ts(c: tk.sec, tab: true))),
                      SizedBox(width: 80, child: Text(humanSize(size), style: ts(c: tk.sec, tab: true))),
                      SizedBox(width: 100, child: t.rating > 0 && e is TitleEntry ? Stars(value: t.rating, size: 13) : const SizedBox()),
                      SizedBox(width: 56, child: Text(reads > 0 ? '×$reads' : '', style: ts(c: tk.sec, tab: true))),
                      SizedBox(width: 110, child: Text(last > 0 ? dateText(last) : '', style: ts(c: tk.sec, tab: true))),
                      SizedBox(width: 90, child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Progress(value: Library.I.entryProgress(e), height: 4),
                      )),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  static String _json(Map<String, dynamic> m) => jsonEncode(m);
  static Map _unjson(String s) => jsonDecode(s) as Map;
}

/// "Add to tag" menu for ticked or opened titles.
class TagMenu extends StatelessWidget {
  const TagMenu({super.key, required this.section, required this.titles});
  final Section section;
  final List<Title> titles;
  @override
  Widget build(BuildContext context) {
    final tags = Library.I.tags(section);
    return PopupMenuButton<int>(
      tooltip: '',
      onSelected: (id) async {
        if (id == -1) {
          final name = await ask(context, 'New tag', body: 'Tags group titles, like "To read" or "On hold".', confirmLabel: 'Create tag');
          if (name == null || name.isEmpty) return;
          final tag = Library.I.createTag(section, name);
          Library.I.addTag(tag, titles);
          toast('Added ${titles.length} to $name');
          return;
        }
        final tag = Library.I.tagById(section, id)!;
        final all = titles.every((t) => Library.I.tagsOf(t).contains(id));
        if (all) {
          Library.I.removeTag(tag, titles);
          toast('Removed ${titles.length} from ${tag.name}');
        } else {
          Library.I.addTag(tag, titles);
          toast('Added ${titles.length} to ${tag.name}');
        }
      },
      itemBuilder: (_) => [
        for (final t in tags)
          PopupMenuItem(
            value: t.id,
            child: Row(children: [
              Icon(titles.every((x) => Library.I.tagsOf(x).contains(t.id)) ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16, color: Color(t.color)),
              const SizedBox(width: 8),
              Text(t.name, style: ts()),
            ]),
          ),
        PopupMenuItem(value: -1, child: Text('New tag…', style: ts(c: lk.acc))),
      ],
      child: const IgnorePointer(child: Btn('Tags', icon: Icons.sell_outlined, dense: true, onTap: LibraryPageState._noop)),
    );
  }
}
