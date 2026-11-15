import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import 'app.dart';
import 'library_page.dart';
import 'widgets.dart';

/// The title page: big cover, details, rating, favourite, tags, history, and
/// for a series its chapter list with select-and-mark.
class TitlePage extends StatefulWidget {
  const TitlePage({super.key, required this.entry, required this.onBack, required this.onOpenArtist});
  final Entry entry;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenArtist;
  @override
  State<TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends State<TitlePage> {
  final Set<int> ticked = {};
  int? lastTick;
  late Title current = widget.entry is GroupEntry ? _continue(widget.entry.titles) : widget.entry.cover;

  List<Title> get chapters => widget.entry.titles;
  bool get isGroup => widget.entry is GroupEntry || widget.entry is FolderEntry;

  static Title _continue(List<Title> ts_) {
    final inProg = ts_.where((t) => t.inProgress).toList()..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    if (inProg.isNotEmpty) return inProg.first;
    return ts_.firstWhere((t) => !t.isRead, orElse: () => ts_.first);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.onBack},
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: Library.I,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Btn.ghost('Back', icon: Icons.arrow_back, onTap: widget.onBack),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.entry.name, style: ts(size: 15, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 280,
                    child: Column(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(lk.rPanel),
                        child: AspectRatio(aspectRatio: 1 / 1.42, child: CoverThumb(title: widget.entry.cover, width: 280, fit: BoxFit.contain)),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: Btn.primary(_readLabel(), icon: Icons.menu_book, onTap: () => _read(current)),
                      ),
                      if (current.lastPage > 0 || current.isRead) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: Btn('Start from the beginning', onTap: () => _read(current, page: 0)),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: isGroup ? _groupBody() : _singleBody(current)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String _readLabel() {
    final t = current;
    final ch = isGroup && t.displayChapter != null ? ' chapter ${_num(t.displayChapter!)}' : '';
    if (t.inProgress) return 'Continue$ch · page ${t.lastPage + 1} of ${t.pages}';
    if (t.isRead && !isGroup) return 'Read again';
    return 'Read$ch';
  }

  static String _num(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();

  void _read(Title t, {int? page}) {
    final queue = isGroup ? chapters.sublist(chapters.indexOf(t)) : [t];
    openReader(context, t, context_: queue, startPage: page);
  }

  Widget _singleBody(Title t) {
    return ListView(children: [
      _details(t),
      const SizedBox(height: 16),
      _history(t),
    ]);
  }

  Widget _details(Title t) {
    final tags = Library.I.tagsOf(t).map((id) => Library.I.tagById(t.section, id)).whereType<Tag>().toList();
    Widget row(String k, String? v, {bool mono = false, VoidCallback? onTap}) => v == null || v.isEmpty
        ? const SizedBox()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 120, child: Text(k, style: ts(c: tk.faint))),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  child: MouseRegion(
                    cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                    child: SelectableText(v, style: ts(mono: mono, size: mono ? 12 : null, c: onTap == null ? tk.text : lk.acc)),
                  ),
                ),
              ),
            ]),
          );
    return PanelBox(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.displayTitle, style: ts(size: 15, w: FontWeight.w700)),
        if (t.altTitle != null) Text(t.altTitle!, style: ts(c: tk.sec)),
        const SizedBox(height: 10),
        Row(children: [
          Stars(value: t.rating, size: 22, onChanged: (v) => Library.I.setRating(t, v)),
          const SizedBox(width: 12),
          IconBtn(t.favourite ? Icons.favorite : Icons.favorite_border,
              tooltip: t.favourite ? 'Favourite' : 'Not a favourite',
              color: t.favourite ? const Color(0xFFFF6FB1) : null,
              onTap: () => Library.I.toggleFavourite([t])),
          const SizedBox(width: 8),
          TagMenu(section: t.section, titles: [t]),
          const SizedBox(width: 8),
          Btn(t.isRead ? 'Mark unread' : 'Mark read', dense: true, icon: t.isRead ? Icons.remove_done : Icons.done_all,
              onTap: () => Library.I.markRead([t], !t.isRead)),
          const SizedBox(width: 8),
          Btn('Edit details', dense: true, icon: Icons.edit_outlined, onTap: () => _edit(t)),
        ]),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in tags) TagChip(g.name, Color(g.color), onRemove: () => Library.I.removeTag(g, [t])),
          ]),
        ],
        const SizedBox(height: 12),
        row('Artist', t.displayArtist, onTap: t.displayArtist == null ? null : () => widget.onOpenArtist(t.displayArtist!)),
        row('Circle', t.circle),
        row('Series', t.displaySeries != t.displayTitle ? t.displaySeries : null),
        row('Chapter', t.displayChapter == null ? null : _num(t.displayChapter!)),
        row('Volume', t.volume),
        row('Year', t.year?.toString()),
        row('Parody', t.parody),
        row('Source', t.source),
        row('Event', t.event),
        row('Language', t.language),
        row('Other', t.extras),
        row('Pages', '${t.pages}'),
        row('Size', humanSize(t.size)),
        row('Added', dateText(t.addedAt)),
        row('Times read', t.readCount > 0 ? '${t.readCount}${t.manualRead ? ' (marked by hand)' : ''}' : 'Not read yet'),
        row('First finished', t.firstCompletedAt > 0 ? dateText(t.firstCompletedAt) : null),
        row('Last finished', t.lastCompletedAt > 0 ? dateText(t.lastCompletedAt) : null),
        row('Time reading', t.timeSpent > 0 ? humanHours(t.timeSpent) : null),
        row('Progress', t.pages > 0 ? 'Page ${t.lastPage + 1} of ${t.pages}' : null),
        row('File', t.path, mono: true),
        const SizedBox(height: 8),
        Row(children: [
          Btn.ghost('Show in folder', icon: Icons.folder_open_outlined, onTap: () {
            if (Platform.isWindows) Process.run('explorer.exe', ['/select,', t.path]);
          }),
          Btn.ghost('Copy path', icon: Icons.copy, onTap: () {
            Clipboard.setData(ClipboardData(text: t.path));
            toast('Path copied');
          }),
          Btn.ghost('Choose cover page', icon: Icons.image_outlined, onTap: () async {
            final v = await ask(context, 'Cover page', body: 'Which page should be the cover? (1 to ${t.pages})',
                initial: '${t.coverPage + 1}', confirmLabel: 'Use this page');
            final n = int.tryParse(v ?? '');
            if (n == null) return;
            t.coverPage = (n - 1).clamp(0, t.pages > 0 ? t.pages - 1 : 0);
            Library.I.saveEdits(t);
          }),
        ]),
      ]),
    );
  }

  Future<void> _edit(Title t) async {
    final title = TextEditingController(text: t.displayTitle);
    final artist = TextEditingController(text: t.displayArtist ?? '');
    final series = TextEditingController(text: t.displaySeries);
    final chapter = TextEditingController(text: t.displayChapter == null ? '' : _num(t.displayChapter!));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AppDialog(
        title: 'Edit details',
        width: 520,
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (label, ctl) in [('Title', title), ('Artist', artist), ('Series', series), ('Chapter', chapter)])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 88, child: Text(label, style: ts(c: tk.sec))),
                Expanded(child: Field(controller: ctl)),
              ]),
            ),
          Text('Your edits are kept, and a rescan never overwrites them. Same series and artist = one series card.',
              style: ts(c: tk.faint, size: 12)),
        ]),
        actions: [
          Btn('Undo my edits', onTap: () {
            t.userTitle = null;
            t.userArtist = null;
            t.userSeries = null;
            t.userChapter = null;
            Navigator.pop(c, true);
          }),
          Btn('Cancel', onTap: () => Navigator.pop(c, false)),
          Btn.primary('Save details', onTap: () {
            String? v(TextEditingController x, String? orig) => x.text.trim().isEmpty || x.text.trim() == orig ? null : x.text.trim();
            t.userTitle = v(title, t.title);
            t.userArtist = v(artist, t.artist);
            t.userSeries = v(series, t.seriesBase);
            final ch = double.tryParse(chapter.text.trim());
            t.userChapter = ch == t.chapter ? null : ch;
            t.needsCheck = false;
            Navigator.pop(c, true);
          }),
        ],
      ),
    );
    if (ok == true) Library.I.saveEdits(t);
  }

  Widget _history(Title t) {
    final sessions = Db.I.sessions(titleId: t.id);
    final comps = Db.I.completions(titleId: t.id);
    return PanelBox(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('History', style: ts(w: FontWeight.w700)),
        const SizedBox(height: 8),
        if (sessions.isEmpty && comps.isEmpty) Text('Not opened yet.', style: ts(c: tk.faint)),
        for (final c in comps.where((c) => c.$4 == 'yacreader' || c.$3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
                '${c.$4 == 'yacreader' ? 'Read · from YACReader' : 'Marked read by hand'} · ${c.$2 > 0 ? dateText(c.$2) : 'date unknown'}',
                style: ts(c: tk.sec)),
          ),
        for (final s in sessions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 170, child: Text('${dateText(s.startedAt)}, ${timeText(s.startedAt)}', style: ts(tab: true))),
              SizedBox(width: 90, child: Text(humanHours(s.activeSeconds), style: ts(c: tk.sec, tab: true))),
              SizedBox(width: 160, child: Text('p${s.fromPage + 1} → p${s.toPage + 1} · ${s.pagesSeen} pages', style: ts(c: tk.sec, tab: true))),
              if (s.completed) Text('Finished', style: ts(c: tk.ok, w: FontWeight.w600)),
              const Spacer(),
              Text(s.device, style: ts(c: tk.faint)),
            ]),
          ),
      ]),
    );
  }

  Widget _groupBody() {
    final list = chapters;
    final tickedTitles = list.where((t) => ticked.contains(t.id)).toList();
    final reads = list.where((t) => t.isRead).length;
    final first = list.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PanelBox(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.entry.name, style: ts(size: 15, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              '${first.displayArtist != null ? '${first.displayArtist} · ' : ''}${list.length} ${widget.entry is FolderEntry ? 'files' : 'chapters'} · $reads read · '
              '${humanSize(list.fold<int>(0, (a, t) => a + t.size))}',
              style: ts(c: tk.sec)),
          const SizedBox(height: 8),
          Row(children: [
            Btn('Favourite all', dense: true, icon: Icons.favorite_border, onTap: () => Library.I.toggleFavourite(list)),
            const SizedBox(width: 6),
            TagMenu(section: first.section, titles: list),
            if (first.displayArtist != null) ...[
              const SizedBox(width: 6),
              Btn.ghost('More by ${first.displayArtist}', dense: true, onTap: () => widget.onOpenArtist(first.displayArtist!)),
            ],
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      if (tickedTitles.isNotEmpty)
        Container(
          height: lk.hControl + 10,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: lk.tint(tk.panel, 0.12),
            borderRadius: BorderRadius.circular(lk.rPanel),
            border: Border.all(color: lk.acc.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Text('${tickedTitles.length} ticked', style: ts(w: FontWeight.w600)),
            const SizedBox(width: 10),
            Btn('Mark read', dense: true, icon: Icons.done_all, onTap: () => Library.I.markRead(tickedTitles, true)),
            const SizedBox(width: 6),
            Btn('Mark unread', dense: true, icon: Icons.remove_done, onTap: () => Library.I.markRead(tickedTitles, false)),
            const Spacer(),
            Btn.ghost('Tick all', dense: true, onTap: () => setState(() => ticked.addAll(list.map((t) => t.id)))),
            Btn.ghost('Clear ticks', dense: true, onTap: () => setState(ticked.clear)),
          ]),
        ),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: tk.field, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final t = list[i];
              final isTicked = ticked.contains(t.id);
              return Hoverable(
                builder: (h) => GestureDetector(
                  onTap: () {
                    if (HardwareKeyboard.instance.isShiftPressed && lastTick != null) {
                      final a = lastTick! < i ? lastTick! : i, b = lastTick! < i ? i : lastTick!;
                      setState(() => ticked.addAll(list.sublist(a, b + 1).map((x) => x.id)));
                    } else if (HardwareKeyboard.instance.isControlPressed) {
                      setState(() => isTicked ? ticked.remove(t.id) : ticked.add(t.id));
                    } else {
                      setState(() => current = t);
                    }
                    lastTick = i;
                  },
                  onDoubleTap: () => _read(t),
                  onSecondaryTapDown: (d) => _menu(t, d.globalPosition),
                  child: Container(
                    height: lk.hRow + 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isTicked ? lk.tint(tk.field, 0.17) : (t.id == current.id ? lk.tint(tk.field, 0.09) : (h ? tk.raised : null)),
                      border: t.id == current.id ? Border.all(color: lk.outline, width: 1) : null,
                    ),
                    child: Row(children: [
                      Checkbox(value: isTicked, onChanged: (_) => setState(() {
                            isTicked ? ticked.remove(t.id) : ticked.add(t.id);
                            lastTick = i;
                          })),
                      SizedBox(
                          width: 70,
                          child: Text(
                              t.displayChapter != null ? 'Ch. ${_num(t.displayChapter!)}' : (t.orderPrefix != null ? '#${t.orderPrefix}' : '${i + 1}'),
                              style: ts(c: tk.sec, tab: true))),
                      Expanded(
                        child: Text(t.displayTitle,
                            style: ts(c: t.isRead ? tk.faint : tk.text, w: t.inProgress ? FontWeight.w600 : null),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (t.favourite) const Icon(Icons.favorite, size: 13, color: Color(0xFFFF6FB1)),
                      if (t.rating > 0) Padding(padding: const EdgeInsets.only(left: 8), child: Stars(value: t.rating, size: 12)),
                      SizedBox(width: 70, child: Text('${t.pages} p', textAlign: TextAlign.right, style: ts(c: tk.faint, tab: true))),
                      const SizedBox(width: 10),
                      SizedBox(width: 80, child: Progress(value: t.progress, height: 4)),
                      const SizedBox(width: 6),
                      SizedBox(
                          width: 20,
                          child: t.isRead ? Icon(Icons.check, size: 15, color: tk.ok) : const SizedBox()),
                      IconBtn(Icons.more_horiz, tooltip: 'More', onTap: () {
                        final box = context.findRenderObject() as RenderBox?;
                        _menu(t, box == null ? Offset.zero : box.localToGlobal(Offset(box.size.width - 40, 120.0 + i * (lk.hRow + 20))));
                      }),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(height: 190, child: SingleChildScrollView(child: _details(current))),
    ]);
  }

  void _menu(Title t, Offset at) async {
    final prev = Library.I.previousChapters(t);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        PopupMenuItem(value: 'read', child: Text('Read', style: ts())),
        PopupMenuItem(value: 'mark', child: Text(t.isRead ? 'Mark unread' : 'Mark read', style: ts())),
        if (prev.isNotEmpty)
          PopupMenuItem(value: 'prev', child: Text('Mark previous as read (${prev.length})', style: ts())),
        PopupMenuItem(value: 'fav', child: Text(t.favourite ? 'Not a favourite' : 'Favourite', style: ts())),
      ],
    );
    switch (v) {
      case 'read':
        _read(t);
      case 'mark':
        Library.I.markRead([t], !t.isRead);
      case 'prev':
        Library.I.markRead(prev, true);
        toast('Marked ${prev.length} earlier chapters as read');
      case 'fav':
        Library.I.toggleFavourite([t]);
    }
  }
}

