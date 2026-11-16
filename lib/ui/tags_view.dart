import 'package:material_ui/material_ui.dart' hide Title;

import '../core/db.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'covers.dart';
import 'look.dart';
import 'widgets.dart';

/// Browse by tag. Tags can be dragged into order; titles inside a tag keep a
/// manual order (a queue) or use any sort.
class TagsView extends StatefulWidget {
  const TagsView({super.key, required this.section, required this.onOpen});
  final Section section;
  final ValueChanged<Entry> onOpen;
  @override
  State<TagsView> createState() => _TagsViewState();
}

class _TagsViewState extends State<TagsView> {
  int? selected;

  Section get s => widget.section;

  @override
  Widget build(BuildContext context) {
    final tags = Library.I.tags(s);
    if (tags.isEmpty) {
      return EmptyState(
        icon: Icons.sell_outlined,
        text: 'No tags yet. Tags group titles, like "To read" or "On hold".',
        action: Btn.primary('New tag', onTap: _newTag),
      );
    }
    final sel = tags.where((t) => t.id == selected).firstOrNull ?? tags.first;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 260,
        child: PanelBox(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Row(children: [
              Text('Tags', style: ts(w: FontWeight.w600)),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Sort tags',
                icon: Icon(Icons.sort, size: 16, color: tk.sec),
                onSelected: (v) {
                  final list = [...tags];
                  if (v == 'name') list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  if (v == 'count') {
                    list.sort((a, b) => Db.I.tagMembers(b.id).length.compareTo(Db.I.tagMembers(a.id).length));
                  }
                  for (var i = 0; i < list.length; i++) {
                    list[i].sortIndex = i;
                    Db.I.updateTag(list[i]);
                  }
                  Library.I.reloadTags(s);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'name', child: Text('Sort tags A–Z', style: ts())),
                  PopupMenuItem(value: 'count', child: Text('Sort tags by count', style: ts())),
                ],
              ),
              IconBtn(Icons.add, tooltip: 'New tag', onTap: _newTag),
            ]),
            const SizedBox(height: 4),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: tags.length,
                onReorder: (a, b) {
                  final list = [...tags];
                  if (b > a) b--;
                  list.insert(b, list.removeAt(a));
                  for (var i = 0; i < list.length; i++) {
                    list[i].sortIndex = i;
                    Db.I.updateTag(list[i]);
                  }
                  Library.I.reloadTags(s);
                },
                itemBuilder: (_, i) {
                  final t = tags[i];
                  final n = Db.I.tagMembers(t.id).length;
                  final active = t.id == sel.id;
                  return ReorderableDragStartListener(
                    key: ValueKey(t.id),
                    index: i,
                    child: GestureDetector(
                      onTap: () => setState(() => selected = t.id),
                      child: Container(
                        height: lk.hRow + 8,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: active ? lk.tint(tk.panel, 0.12) : null,
                          borderRadius: BorderRadius.circular(lk.rControl),
                        ),
                        child: Row(children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: Color(t.color), shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t.name, style: ts(w: active ? FontWeight.w600 : null), overflow: TextOverflow.ellipsis)),
                          Text('$n', style: ts(c: tk.faint, tab: true)),
                          Icon(Icons.drag_indicator, size: 14, color: tk.faint),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: _tagBody(sel)),
    ]);
  }

  void _newTag() async {
    final name = await ask(context, 'New tag', body: 'Tags group titles, like "To read" or "On hold".', confirmLabel: 'Create tag');
    if (name == null || name.isEmpty) return;
    final t = Library.I.createTag(s, name);
    setState(() => selected = t.id);
  }

  Widget _tagBody(Tag tag) {
    final ids = Db.I.tagMembers(tag.id);
    final members = ids.map(Library.I.byId).whereType<Title>().toList();
    final manual = tag.innerSort == 'manual';
    final entries = members.map<Entry>(TitleEntry.new).toList();
    if (!manual) {
      final key = tag.innerSort.replaceAll('-desc', '');
      Library.I.sortEntries(entries, key, tag.innerSort.endsWith('-desc'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(tag.color), shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(tag.name, style: ts(size: 15, w: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('${members.length} titles', style: ts(c: tk.sec)),
        const Spacer(),
        Text('Order', style: ts(c: tk.sec)),
        const SizedBox(width: 6),
        Drop<String>(
          value: tag.innerSort,
          items: [
            ('manual', 'Your order (drag)'),
            for (final e in sortKeys.entries) (e.key, e.value),
            for (final e in sortKeys.entries) ('${e.key}-desc', '${e.value}, reversed'),
          ],
          onChanged: (v) {
            tag.innerSort = v;
            Db.I.updateTag(tag);
            Library.I.reloadTags(s);
          },
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: '',
          icon: Icon(Icons.more_horiz, color: tk.sec, size: 18),
          onSelected: (v) async {
            if (v == 'rename') {
              final n = await ask(context, 'Rename tag', initial: tag.name, confirmLabel: 'Rename');
              if (n != null && n.isNotEmpty) {
                tag.name = n;
                Db.I.updateTag(tag);
                Library.I.reloadTags(s);
              }
            } else if (v.startsWith('color:')) {
              tag.color = int.parse(v.substring(6));
              Db.I.updateTag(tag);
              Library.I.reloadTags(s);
            } else if (v == 'delete') {
              if (!mounted) return;
              if (await confirm(context, 'Delete the tag "${tag.name}"?',
                  'The tag is removed from ${members.length} titles. The titles themselves stay.',
                  confirmLabel: 'Delete tag', danger: true)) {
                Db.I.deleteTag(tag.id);
                Library.I.reloadTags(s);
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'rename', child: Text('Rename…', style: ts())),
            for (final c in categoryColors)
              PopupMenuItem(
                value: 'color:$c',
                height: 28,
                child: Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(c == tag.color ? 'Colour (current)' : 'Colour', style: ts(c: tk.sec)),
                ]),
              ),
            PopupMenuItem(value: 'delete', child: Text('Delete tag…', style: ts(c: tk.danger))),
          ],
        ),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: members.isEmpty
            ? const EmptyState(icon: Icons.sell_outlined, text: 'Nothing in this tag yet. Tick titles in the library and use Tags to add them.')
            : manual
                ? ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: members.length,
                    onReorder: (a, b) {
                      final list = [...members];
                      if (b > a) b--;
                      list.insert(b, list.removeAt(a));
                      Db.I.reorderTag(tag.id, list.map((t) => t.id).toList());
                      Library.I.reloadTags(s);
                    },
                    itemBuilder: (_, i) {
                      final t = members[i];
                      return ReorderableDragStartListener(
                        key: ValueKey(t.id),
                        index: i,
                        child: Hoverable(
                          builder: (h) => GestureDetector(
                            onTap: () => widget.onOpen(TitleEntry(t)),
                            child: Container(
                              height: 64,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              color: h ? tk.raised : null,
                              child: Row(children: [
                                Text('${i + 1}', style: ts(c: tk.faint, tab: true)),
                                const SizedBox(width: 10),
                                SizedBox(width: 40, height: 56, child: CoverThumb(title: t)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(t.displayTitle, style: ts(w: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                    Text(t.displayArtist ?? '', style: ts(c: tk.faint, size: 12), overflow: TextOverflow.ellipsis),
                                  ]),
                                ),
                                if (t.rating > 0) Stars(value: t.rating, size: 13),
                                const SizedBox(width: 10),
                                SizedBox(width: 80, child: Progress(value: t.progress, height: 4)),
                                const SizedBox(width: 10),
                                IconBtn(Icons.close, tooltip: 'Remove from ${tag.name}', onTap: () => Library.I.removeTag(tag, [t])),
                                Icon(Icons.drag_indicator, size: 16, color: tk.faint),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: Settings.I.of(s).tileSize,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: Settings.I.of(s).tileSize / (Settings.I.of(s).tileSize * 1.42 + CoverCard.textHeight(Settings.I.of(s).tileSize)),
                    ),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => CoverCard(
                      entry: entries[i],
                      style: 'comfortable',
                      width: Settings.I.of(s).tileSize,
                      radius: Settings.I.of(s).coverRadius,
                      fill: Settings.I.of(s).coverFill,
                      selected: false,
                      ticked: false,
                      anyTicked: false,
                      onTap: () => widget.onOpen(entries[i]),
                      onTick: () {},
                    ),
                  ),
      ),
    ]);
  }
}

/// Every artist in the section, with counts and ratings.
class ArtistsView extends StatefulWidget {
  const ArtistsView({super.key, required this.section, required this.onPick});
  final Section section;
  final ValueChanged<String> onPick;
  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  String q = '';
  String sort = 'count';

  @override
  Widget build(BuildContext context) {
    final rows = <String, List<Title>>{};
    for (final t in Library.I.titles(widget.section)) {
      if (t.missing) continue;
      final a = t.displayArtist;
      if (a == null || a.isEmpty) continue;
      rows.putIfAbsent(a, () => []).add(t);
    }
    final list = rows.entries.where((e) => q.isEmpty || e.key.toLowerCase().contains(q.toLowerCase())).toList();
    double avg(List<Title> ts_) {
      final r = ts_.where((t) => t.rating > 0).map((t) => t.rating).toList();
      return r.isEmpty ? 0 : r.reduce((a, b) => a + b) / r.length;
    }

    switch (sort) {
      case 'name':
        list.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      case 'read':
        list.sort((a, b) => b.value.where((t) => t.isRead).length.compareTo(a.value.where((t) => t.isRead).length));
      case 'rating':
        list.sort((a, b) => avg(b.value).compareTo(avg(a.value)));
      default:
        list.sort((a, b) => b.value.length.compareTo(a.value.length));
    }
    return Column(children: [
      Row(children: [
        SizedBox(width: 320, child: Field(hint: 'Find an artist', icon: Icons.search, onChanged: (v) => setState(() => q = v))),
        const SizedBox(width: 8),
        Seg<String>(
          value: sort,
          items: const [('count', 'Most titles'), ('read', 'Most read'), ('rating', 'Best rated'), ('name', 'A–Z')],
          onChanged: (v) => setState(() => sort = v),
        ),
        const Spacer(),
        Text('${list.length} artists', style: ts(c: tk.sec)),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: tk.field, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
          child: ListView.builder(
            itemCount: list.length,
            itemExtent: lk.hRow + 10,
            itemBuilder: (_, i) {
              final e = list[i];
              final read = e.value.where((t) => t.isRead).length;
              final a = avg(e.value);
              return Hoverable(
                builder: (h) => GestureDetector(
                  onTap: () => widget.onPick(e.key),
                  child: Container(
                    color: h ? tk.raised : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Expanded(child: Text(e.key, style: ts(w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 100, child: Text('${e.value.length} titles', style: ts(c: tk.sec, tab: true))),
                      SizedBox(width: 100, child: Text('$read read', style: ts(c: tk.sec, tab: true))),
                      SizedBox(width: 110, child: a > 0 ? Stars(value: (a * 2).round() / 2, size: 13) : const SizedBox()),
                      SizedBox(width: 120, child: Progress(value: read / e.value.length, height: 4)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

/// Titles the parser wasn't sure about, for a quick fix.
class CheckTitlesView extends StatefulWidget {
  const CheckTitlesView({super.key, required this.section});
  final Section section;
  @override
  State<CheckTitlesView> createState() => _CheckTitlesViewState();
}

class _CheckTitlesViewState extends State<CheckTitlesView> {
  final Map<int, TextEditingController> _ctl = {};

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = Library.I.titles(widget.section).where((t) => t.needsCheck && !t.missing).toList()
      ..sort((a, b) => a.fileName.compareTo(b.fileName));
    if (list.isEmpty) {
      return const EmptyState(icon: Icons.task_alt, text: 'Nothing to check. Titles Shiori isn\'t sure about show up here.');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${list.length} titles where the English title might be split wrongly. Fix the title, or mark it as right.',
          style: ts(c: tk.sec)),
      const SizedBox(height: 8),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final t = list[i];
            final c = _ctl.putIfAbsent(t.id, () => TextEditingController(text: t.displayTitle));
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tk.line))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.fileName, style: ts(c: tk.faint, size: 12), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Field(controller: c),
                  ]),
                ),
                const SizedBox(width: 8),
                Btn('Looks right', onTap: () {
                  t.userTitle = c.text.trim() == t.title ? null : c.text.trim();
                  t.needsCheck = false;
                  Library.I.saveEdits(t);
                }),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
