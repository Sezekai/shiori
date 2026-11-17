import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/settings.dart';
import '../ui/covers.dart';
import '../ui/widgets.dart';
import 'm_reader.dart';
import 'mobile_app.dart';
import 'pc.dart';
import 'store.dart';

/// Phone-only filter on top of the shared ones.
final Map<Section, Tri> downloadedFilter = {for (final s in Section.values) s: Tri.any};

class MLibraryScreen extends StatefulWidget {
  const MLibraryScreen({super.key});
  @override
  State<MLibraryScreen> createState() => _MLibraryScreenState();
}

class _MLibraryScreenState extends State<MLibraryScreen> {
  Section get section => Section.values.byName(Settings.I.get<String>('m.section', Section.comics.name));
  final List<String> folders = []; // comics folder view: where we are
  bool searching = false;
  final search = TextEditingController();
  final Set<int> ticked = {};
  final ScrollController scroll = ScrollController();

  LibFilter get f => Library.I.filters[section]!;

  List<Entry> _entries() {
    var list = Library.I.entries(section, folder: folders.isEmpty ? '' : folders.last);
    final d = downloadedFilter[section]!;
    if (d != Tri.any) {
      list = list.where((e) {
        if (e is FolderEntry) return true;
        final any = e.titles.any(Store.I.isDownloaded);
        return d == Tri.yes ? any : !any;
      }).toList();
    }
    return list;
  }

  void _setSection(Section s) {
    Settings.I.put('m.section', s.name);
    setState(() {
      folders.clear();
      ticked.clear();
      search.text = f.search;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Library.I, Store.I, Thumbs.I, Settings.I]),
      builder: (context, _) {
        final list = _entries();
        final ticking = ticked.isNotEmpty;
        return PopScope(
          canPop: folders.isEmpty && !ticking && !searching,
          onPopInvokedWithResult: (did, _) {
            if (did) return;
            setState(() {
              if (ticking) {
                ticked.clear();
              } else if (searching) {
                searching = false;
              } else if (folders.isNotEmpty) {
                folders.removeLast();
              }
            });
          },
          child: Column(children: [
            ticking ? _tickBar(list) : _topBar(),
            if (!ticking) _sectionBar(),
            if (folders.isNotEmpty)
              ListTile(
                dense: true,
                leading: Icon(Icons.arrow_upward, color: tk.sec),
                title: Text(folders.last.isEmpty ? 'Top' : folders.last, style: ts(c: tk.sec), overflow: TextOverflow.ellipsis),
                onTap: () => setState(folders.removeLast),
              ),
            Expanded(
              child: list.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: () async {
                        if (await Pc.I.check()) Sync.queue();
                      },
                      child: _grid(list),
                    ),
            ),
          ]),
        );
      },
    );
  }

  Widget _empty() {
    final hasAny = Library.I.titles(section).isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.collections_bookmark_outlined, size: 44, color: tk.faint),
          const SizedBox(height: 10),
          Text(
              hasAny
                  ? 'Nothing matches the filters.'
                  : Pc.I.paired
                      ? 'No ${section.label.toLowerCase()} yet. Sync with the PC to bring the library over.'
                      : 'Connect to the PC to bring your library over.',
              textAlign: TextAlign.center,
              style: ts(c: tk.sec)),
          const SizedBox(height: 12),
          if (hasAny && !f.isEmpty)
            OutlinedButton(
                onPressed: () => setState(() {
                      Library.I.filters[section] = LibFilter();
                      downloadedFilter[section] = Tri.any;
                      search.clear();
                    }),
                child: const Text('Clear filters'))
          else if (!Pc.I.paired)
            FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectScreen())),
                child: const Text('Connect to PC'))
          else if (Pc.I.online)
            FilledButton(onPressed: Sync.queue, child: const Text('Sync now')),
        ]),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
        child: Row(children: [
          if (searching)
            Expanded(
              child: TextField(
                controller: search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search ${section.label.toLowerCase()}',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: tk.sec),
                ),
                onChanged: (v) => setState(() => f.search = v),
              ),
            )
          else ...[
            Text('Shiori', style: ts(size: 20, w: FontWeight.w800)),
            const SizedBox(width: 10),
            const ConnectionPill(),
            const Spacer(),
          ],
          IconButton(
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              searching = !searching;
              if (!searching) {
                search.clear();
                f.search = '';
              }
            }),
          ),
          IconButton(
            icon: Badge(isLabelVisible: !f.isEmpty || downloadedFilter[section] != Tri.any, child: const Icon(Icons.tune)),
            tooltip: 'Filter and sort',
            onPressed: () => _filters(context),
          ),
          IconButton(
            icon: const Icon(Icons.casino_outlined),
            tooltip: 'Random title',
            onPressed: () {
              final all = _entries().where((e) => e is! FolderEntry).toList();
              if (all.isEmpty) return;
              _open(all[Random().nextInt(all.length)]);
            },
          ),
        ]),
      );

  Widget _sectionBar() => SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final s in Section.values)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
              child: ChoiceChip(
                label: Text('${s.label}  ${Library.I.titles(s).where((t) => !t.missing).length}'),
                selected: s == section,
                onSelected: (_) => _setSection(s),
                showCheckmark: false,
              ),
            ),
        ]),
      );

  Widget _tickBar(List<Entry> list) {
    final ts_ = [for (final e in list) ...e.titles.where((t) => ticked.contains(t.id))];
    return Container(
      color: tk.panel,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.close), onPressed: () => setState(ticked.clear)),
        Expanded(child: Text('${ts_.length} ticked', style: ts(w: FontWeight.w700))),
        IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Tick all',
            onPressed: () => setState(() => ticked.addAll(list.expand((e) => e.titles).map((t) => t.id)))),
        IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark read',
            onPressed: () {
              Library.I.markRead(ts_, true);
              setState(ticked.clear);
            }),
        IconButton(
            icon: const Icon(Icons.remove_done),
            tooltip: 'Mark unread',
            onPressed: () {
              Library.I.markRead(ts_, false);
              setState(ticked.clear);
            }),
        IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: Pc.I.online
                ? () {
                    Store.I.download(ts_);
                    setState(ticked.clear);
                  }
                : null),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'fav':
                Library.I.toggleFavourite(ts_);
              case 'remove':
                Store.I.removeDownload(ts_);
              case 'tag':
                showTagSheet(context, section, ts_);
                return;
            }
            setState(ticked.clear);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'fav', child: Text('Favourite')),
            PopupMenuItem(value: 'tag', child: Text('Tags…')),
            PopupMenuItem(value: 'remove', child: Text('Remove downloads')),
          ],
        ),
      ]),
    );
  }

  Widget _grid(List<Entry> list) {
    return LayoutBuilder(builder: (context, c) {
      final tile = Settings.I.get<double>('m.tile', 118);
      const gap = 8.0;
      final cols = max(2, ((c.maxWidth - 16 + gap) / (tile + gap)).floor());
      final cw = (c.maxWidth - 16 - gap * (cols - 1)) / cols;
      return GridView.builder(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          mainAxisExtent: cw * 1.42 + 38,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _tile(list[i]),
      );
    });
  }

  Widget _tile(Entry e) {
    final ids = e.titles.map((t) => t.id);
    final isTicked = e is! FolderEntry && ids.every(ticked.contains);
    void tick() => setState(() => isTicked ? ticked.removeAll(ids) : ticked.addAll(ids));
    return GestureDetector(
      onTap: () => ticked.isNotEmpty && e is! FolderEntry ? tick() : _open(e),
      onLongPress: e is FolderEntry ? null : tick,
      child: MCover(entry: e, ticked: isTicked),
    );
  }

  void _open(Entry e) {
    if (e is FolderEntry) {
      setState(() => folders.add(e.relPath));
      scroll.jumpTo(0);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MTitleScreen(entry: e)));
  }

  Future<void> _filters(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final ss = Settings.I.of(section);
          Widget row(String label, Tri v, ValueChanged<Tri> on) => ListTile(
                dense: true,
                title: Text(label, style: ts()),
                trailing: SegmentedButton<Tri>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Tri.any, label: Text('Any')),
                    ButtonSegment(value: Tri.yes, label: Text('Yes')),
                    ButtonSegment(value: Tri.no, label: Text('No')),
                  ],
                  selected: {v},
                  onSelectionChanged: (x) {
                    on(x.first);
                    set(() {});
                    setState(() {});
                  },
                ),
              );
          final tags = Library.I.tags(section);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('Filter and sort', style: ts(size: 17, w: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                      onPressed: () {
                        Library.I.filters[section] = LibFilter();
                        downloadedFilter[section] = Tri.any;
                        set(() {});
                        setState(() {});
                      },
                      child: const Text('Reset')),
                ]),
              ),
              row('Read', f.read, (v) => f.read = v),
              row('In progress', f.inProgress, (v) => f.inProgress = v),
              row('Favourite', f.favourite, (v) => f.favourite = v),
              row('Rated', f.rated, (v) => f.rated = v),
              row('Downloaded', downloadedFilter[section]!, (v) => downloadedFilter[section] = v),
              if (section == Section.comics)
                SwitchListTile(
                  dense: true,
                  title: Text('Folder view', style: ts()),
                  value: ss.comicsFolderView,
                  onChanged: (v) {
                    ss.comicsFolderView = v;
                    Settings.I.save();
                    folders.clear();
                    set(() {});
                  },
                ),
              if (tags.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4), child: Text('Tags', style: ts(c: tk.sec))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in tags)
                      FilterChip(
                        label: Text(t.name),
                        selected: f.tags.contains(t.id),
                        avatar: CircleAvatar(backgroundColor: Color(t.color), radius: 5),
                        onSelected: (v) {
                          v ? f.tags.add(t.id) : f.tags.remove(t.id);
                          set(() {});
                          setState(() {});
                        },
                      ),
                  ]),
                ),
              ],
              Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text('Sort by', style: ts(c: tk.sec))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (k, label) in sortChoices)
                    ChoiceChip(
                      label: Text(label),
                      selected: ss.sort == k,
                      showCheckmark: false,
                      onSelected: (_) {
                        ss.sort = k;
                        Settings.I.save();
                        set(() {});
                      },
                    ),
                ]),
              ),
              SwitchListTile(
                dense: true,
                title: Text('Reverse order', style: ts()),
                value: ss.sortDesc,
                onChanged: (v) {
                  ss.sortDesc = v;
                  Settings.I.save();
                  set(() {});
                },
              ),
              Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Text('Cover size', style: ts(c: tk.sec))),
              Slider(
                value: Settings.I.get<double>('m.tile', 118),
                min: 80,
                max: 220,
                onChanged: (v) {
                  Settings.I.extra['m.tile'] = v;
                  Settings.I.changedQuiet();
                  set(() {});
                },
                onChangeEnd: (_) => Settings.I.save(),
              ),
            ]),
          );
        },
      ),
    );
  }
}

const sortChoices = [
  ('title', 'Title'),
  ('artist', 'Artist'),
  ('added', 'Date added'),
  ('lastRead', 'Last read'),
  ('rating', 'Rating'),
  ('readCount', 'Times read'),
  ('progress', 'Progress'),
  ('pages', 'Pages'),
  ('size', 'Size'),
  ('random', 'Random'),
];

/// A cover in the phone grid: title under it, progress line, and badges for
/// downloaded, favourite and unread chapters.
class MCover extends StatelessWidget {
  const MCover({super.key, required this.entry, this.ticked = false});
  final Entry entry;
  final bool ticked;
  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e is FolderEntry) {
      return Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: tk.line)),
            child: Center(child: Icon(Icons.folder_outlined, size: 40, color: tk.sec)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(height: 32, child: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(size: 12))),
      ]);
    }
    final t = e.cover;
    final downloaded = e.titles.where(Store.I.isDownloaded).length;
    final progress = Library.I.entryProgress(e);
    final unread = e is GroupEntry ? e.titles.where((x) => !x.isRead).length : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ticked ? lk.acc : Colors.transparent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(fit: StackFit.expand, children: [
              CoverThumb(title: t, fill: Settings.I.of(t.section).coverFill),
              if (ticked) Container(color: lk.acc.withValues(alpha: 0.25)),
              Positioned(
                left: 4,
                top: 4,
                child: Row(children: [
                  if (unread > 0) _badge('$unread', lk.acc, onAcc: true),
                  if (downloaded > 0) _badge(e is GroupEntry ? '↓$downloaded' : '↓', tk.ok),
                ]),
              ),
              if (t.favourite && e is TitleEntry)
                const Positioned(right: 4, top: 4, child: Icon(Icons.favorite, size: 16, color: Color(0xFFFF6FB1))),
              if (ticked) Positioned(right: 4, bottom: 6, child: Icon(Icons.check_circle, color: lk.acc)),
              if (Settings.I.progressLine && progress > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: Colors.black38, color: lk.acc),
                ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 32,
        child: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(size: 12, w: FontWeight.w600)),
      ),
    ]);
  }

  Widget _badge(String s, Color c, {bool onAcc = false}) => Container(
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        child: Text(s, style: ts(size: 11, w: FontWeight.w700, c: onAcc ? lk.onAcc : Colors.black)),
      );
}

/// A title or series: cover, read button, details, chapters, downloads.
class MTitleScreen extends StatefulWidget {
  const MTitleScreen({super.key, required this.entry});
  final Entry entry;
  @override
  State<MTitleScreen> createState() => _MTitleScreenState();
}

class _MTitleScreenState extends State<MTitleScreen> {
  final Set<int> ticked = {};

  List<Title> get chapters {
    // Re-read from the library so changes show straight away.
    final ids = widget.entry.titles.map((t) => t.id).toSet();
    final fresh = [for (final id in ids) Library.I.byId(id)].whereType<Title>().toList();
    fresh.sort(Library.chapterOrder);
    return fresh;
  }

  Title get next {
    final list = chapters;
    return list.firstWhere((t) => t.inProgress, orElse: () => list.firstWhere((t) => !t.isRead, orElse: () => list.first));
  }

  void _read(Title t, {int? page}) => openMobileReader(context, t, chapters, page: page);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Library.I, Store.I, Jobs.I, Pc.I]),
      builder: (context, _) {
        final list = chapters;
        if (list.isEmpty) return const Scaffold(body: Center(child: Text('This title is gone')));
        final isGroup = list.length > 1;
        final t = isGroup ? next : list.first;
        final wide = MediaQuery.of(context).size.width > 700;
        final ticking = ticked.isNotEmpty;
        final header = _header(t, list, isGroup);
        return PopScope(
          canPop: !ticking,
          onPopInvokedWithResult: (did, _) {
            if (!did) setState(ticked.clear);
          },
          child: Scaffold(
            appBar: ticking
                ? AppBar(
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(ticked.clear)),
                    title: Text('${ticked.length} ticked', style: ts(size: 17, w: FontWeight.w700)),
                    actions: [
                      IconButton(
                          icon: const Icon(Icons.select_all),
                          onPressed: () => setState(() => ticked.addAll(list.map((x) => x.id)))),
                      IconButton(
                          icon: const Icon(Icons.done_all),
                          onPressed: () {
                            Library.I.markRead(list.where((x) => ticked.contains(x.id)), true);
                            setState(ticked.clear);
                          }),
                      IconButton(
                          icon: const Icon(Icons.remove_done),
                          onPressed: () {
                            Library.I.markRead(list.where((x) => ticked.contains(x.id)), false);
                            setState(ticked.clear);
                          }),
                      IconButton(
                          icon: const Icon(Icons.download_outlined),
                          onPressed: Pc.I.online
                              ? () {
                                  Store.I.download(list.where((x) => ticked.contains(x.id)));
                                  setState(ticked.clear);
                                }
                              : null),
                      IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove downloads',
                          onPressed: () {
                            Store.I.removeDownload(list.where((x) => ticked.contains(x.id)));
                            setState(ticked.clear);
                          }),
                    ],
                  )
                : AppBar(
                    title: Text(widget.entry.name, style: ts(size: 16, w: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    actions: const [Padding(padding: EdgeInsets.only(right: 10), child: ConnectionPill())],
                  ),
            body: SafeArea(
              top: false,
              child: wide && isGroup
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 380, child: ListView(padding: const EdgeInsets.all(14), children: header)),
                      VerticalDivider(width: 1, color: tk.line),
                      Expanded(child: ListView(children: _chapterRows(list))),
                    ])
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header)),
                      if (isGroup) ..._chapterRows(list),
                    ]),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _header(Title t, List<Title> list, bool isGroup) {
    final first = list.first;
    final job = Jobs.I.current;
    final downloading = job != null && job.name == Store.I.jobNameFor(t) ? job : null;
    final queued = Jobs.I.isQueued(Store.I.jobNameFor(t));
    final downloadedCount = list.where(Store.I.isDownloaded).length;
    final readable = Pc.I.online || Store.I.isDownloaded(t) || _cached(t);
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(aspectRatio: 1 / 1.42, child: CoverThumb(title: isGroup ? first : t))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isGroup ? widget.entry.name : t.displayTitle, style: ts(size: 17, w: FontWeight.w700)),
            if (t.altTitle != null && !isGroup) Text(t.altTitle!, style: ts(c: tk.faint, size: 12)),
            if (t.displayArtist != null) ...[
              const SizedBox(height: 4),
              Text(t.displayArtist!, style: ts(c: lk.acc, w: FontWeight.w600)),
            ],
            const SizedBox(height: 6),
            Text(
              isGroup
                  ? '${list.length} chapters · ${list.where((x) => x.isRead).length} read'
                  : '${t.pages} pages · ${humanSize(t.size)}${t.readCount > 0 ? ' · read ×${t.readCount}' : ''}',
              style: ts(c: tk.sec, size: 13),
            ),
            if (!isGroup && t.lastReadAt > 0) Text('Last read ${dateText(t.lastReadAt)}', style: ts(c: tk.faint, size: 12)),
            if (downloadedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(Icons.download_done, size: 15, color: tk.ok),
                  const SizedBox(width: 4),
                  Text(isGroup ? '$downloadedCount downloaded' : 'Downloaded', style: ts(c: tk.ok, size: 12)),
                ]),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: readable ? () => _read(t) : null,
          icon: const Icon(Icons.menu_book),
          label: Text(!readable
              ? 'Connect to the PC or download to read'
              : isGroup
                  ? '${t.inProgress ? 'Continue' : 'Read'} ${t.displayChapter != null ? 'chapter ${_num(t.displayChapter!)}' : t.displayTitle}'
                  : t.inProgress
                      ? 'Continue from page ${t.lastPage + 1}'
                      : t.isRead
                          ? 'Read again'
                          : 'Read'),
        ),
      ),
      if (!isGroup && t.inProgress)
        TextButton(onPressed: readable ? () => _read(t, page: 0) : null, child: const Text('Start from the beginning')),
      if (downloading != null) ...[
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: JobProgress(job: downloading)),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (!isGroup)
          if (Store.I.isDownloaded(t))
            OutlinedButton.icon(
                onPressed: () => Store.I.removeDownload([t]), icon: const Icon(Icons.delete_outline), label: const Text('Remove download'))
          else
            OutlinedButton.icon(
                onPressed: Pc.I.online && !queued ? () => Store.I.download([t]) : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(queued ? 'Waiting to download' : 'Download')),
        if (isGroup)
          OutlinedButton.icon(
              onPressed: Pc.I.online ? () => Store.I.download(list.where((x) => !x.isRead)) : null,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download unread')),
        IconButton.outlined(
          icon: Icon(list.every((x) => x.favourite) ? Icons.favorite : Icons.favorite_border, color: const Color(0xFFFF6FB1)),
          tooltip: 'Favourite',
          onPressed: () => Library.I.toggleFavourite(isGroup ? list : [t]),
        ),
        IconButton.outlined(
          icon: const Icon(Icons.sell_outlined),
          tooltip: 'Tags',
          onPressed: () => showTagSheet(context, t.section, isGroup ? list : [t]),
        ),
        if (!isGroup)
          IconButton.outlined(
            icon: Icon(t.isRead ? Icons.remove_done : Icons.done_all),
            tooltip: t.isRead ? 'Mark unread' : 'Mark read',
            onPressed: () => Library.I.markRead([t], !t.isRead),
          ),
      ]),
      if (!isGroup) ...[
        const SizedBox(height: 10),
        Stars(value: t.rating, size: 30, onChanged: (v) => Library.I.setRating(t, v)),
      ],
      if (Library.I.tagsOf(t).isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in Library.I.tagsOf(t))
            if (Library.I.tagById(t.section, id) case final tag?)
              Chip(
                label: Text(tag.name),
                avatar: CircleAvatar(backgroundColor: Color(tag.color), radius: 5),
                visualDensity: VisualDensity.compact,
              ),
        ]),
      ],
      if (!isGroup) ...[
        const SizedBox(height: 12),
        for (final (k, v) in [
          if (t.circle != null) ('Circle', t.circle!),
          if (t.parody != null) ('Parody', t.parody!),
          if (t.event != null) ('Event', t.event!),
          if (t.language != null) ('Language', t.language!),
          if (t.timeSpent > 0) ('Time spent', humanHours(t.timeSpent)),
          ('File', p.basename(t.fileName)),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 96, child: Text(k, style: ts(c: tk.faint, size: 13))),
              Expanded(child: Text(v, style: ts(size: 13))),
            ]),
          ),
      ],
    ];
  }

  /// Read recently while connected, so its pages are still on the phone.
  bool _cached(Title t) => File(p.join(Store.I.streamCache, t.uid, 'pages.txt')).existsSync();

  List<Widget> _chapterRows(List<Title> list) => [
        for (final (i, c) in list.indexed)
          ListTile(
            onTap: () => ticked.isNotEmpty
                ? setState(() => ticked.contains(c.id) ? ticked.remove(c.id) : ticked.add(c.id))
                : (Pc.I.online || Store.I.isDownloaded(c))
                    ? _read(c)
                    : mToast('Connect to the PC or download this chapter to read it'),
            onLongPress: () => setState(() => ticked.contains(c.id) ? ticked.remove(c.id) : ticked.add(c.id)),
            selected: ticked.contains(c.id),
            selectedTileColor: lk.tint(tk.ground, 0.12),
            tileColor: i.isOdd ? tk.panel.withValues(alpha: 0.5) : null,
            leading: SizedBox(
              width: 38,
              height: 54,
              child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CoverThumb(title: c)),
            ),
            title: Text(
              c.displayChapter != null ? 'Chapter ${_num(c.displayChapter!)}' : c.displayTitle,
              style: ts(c: c.isRead ? tk.faint : tk.text, w: c.inProgress ? FontWeight.w700 : FontWeight.w500),
            ),
            subtitle: Text(
              [
                '${c.pages} pages',
                if (c.inProgress) 'page ${c.lastPage + 1}',
                if (c.lastReadAt > 0) dateText(c.lastReadAt),
              ].join(' · '),
              style: ts(c: tk.sec, size: 12),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (Store.I.isDownloaded(c)) Icon(Icons.download_done, size: 18, color: tk.ok),
              if (Jobs.I.isQueued(Store.I.jobNameFor(c))) Icon(Icons.downloading, size: 18, color: tk.sec),
              if (c.isRead) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.check, size: 18, color: tk.ok)),
            ]),
          ),
      ];
}

String _num(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();

Future<void> showTagSheet(BuildContext context, Section s, List<Title> ts_) async {
  final name = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => ListenableBuilder(
      listenable: Library.I,
      builder: (c, _) {
        final tags = Library.I.tags(s);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom + 16, left: 16, right: 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tags', style: ts(size: 17, w: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final tag in tags)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: ts_.every((t) => Library.I.tagsOf(t).contains(tag.id)),
                title: Row(children: [
                  CircleAvatar(backgroundColor: Color(tag.color), radius: 6),
                  const SizedBox(width: 10),
                  Text(tag.name, style: ts()),
                ]),
                onChanged: (v) => v == true ? Library.I.addTag(tag, ts_) : Library.I.removeTag(tag, ts_),
              ),
            Row(children: [
              Expanded(child: TextField(controller: name, decoration: const InputDecoration(hintText: 'New tag'))),
              TextButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) return;
                  final tag = Library.I.createTag(s, name.text.trim());
                  Library.I.addTag(tag, ts_);
                  name.clear();
                },
                child: const Text('Add'),
              ),
            ]),
          ]),
        );
      },
    ),
  );
}
