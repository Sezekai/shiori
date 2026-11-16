import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'covers.dart';
import 'library_page.dart';
import 'widgets.dart';

/// The details bar on the right of the library. "Expand" opens the full page.
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.entry,
    required this.onClose,
    required this.onExpand,
    required this.onRead,
    required this.onOpenArtist,
  });
  final Entry entry;
  final VoidCallback onClose;
  final VoidCallback onExpand;
  final void Function(Title t, int? page) onRead;
  final ValueChanged<String> onOpenArtist;

  static Title continueTitle(List<Title> ts_) {
    final inProg = ts_.where((t) => t.inProgress).toList()..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    if (inProg.isNotEmpty) return inProg.first;
    return ts_.firstWhere((t) => !t.isRead, orElse: () => ts_.first);
  }

  static String num(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final group = e is! TitleEntry;
    final t = group ? continueTitle(e.titles) : e.cover;
    final cover = e.cover;
    final tags = Library.I.tagsOf(t).map((id) => Library.I.tagById(t.section, id)).whereType<Tag>().toList();
    final ss = Settings.I.of(t.section);
    final readLabel = t.inProgress
        ? 'Continue${group && t.displayChapter != null ? ' ch. ${num(t.displayChapter!)}' : ''} · p${t.lastPage + 1}/${t.pages}'
        : (t.isRead && !group ? 'Read again' : 'Read${group && t.displayChapter != null ? ' ch. ${num(t.displayChapter!)}' : ''}');

    Widget row(String k, String? v, {VoidCallback? onTap}) => v == null || v.isEmpty
        ? const SizedBox()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 92, child: Text(k, style: ts(c: tk.faint, size: 12))),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  child: MouseRegion(
                    cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                    child: Text(v, style: ts(size: 12.5, c: onTap == null ? tk.text : lk.acc)),
                  ),
                ),
              ),
            ]),
          );

    return Container(
      width: 340,
      decoration: BoxDecoration(color: tk.panel, border: Border(left: BorderSide(color: tk.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tk.line))),
          child: Row(children: [
            Text('Details', style: ts(w: FontWeight.w600)),
            const Spacer(),
            IconBtn(Icons.open_in_full, tooltip: 'Open the full page', onTap: onExpand),
            IconBtn(Icons.close, tooltip: 'Close (mouse back)', onTap: onClose),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(14), children: [
            Center(
              child: GestureDetector(
                onTap: () => onRead(t, null),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(ss.coverRadius),
                    child: SizedBox(width: 200, height: 284, child: CoverThumb(title: cover)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(e.name, style: ts(size: lk.fontSize + 2, w: FontWeight.w700)),
            if (!group && t.altTitle != null) Text(t.altTitle!, style: ts(c: tk.sec, size: 12)),
            if (t.displayArtist != null)
              GestureDetector(
                onTap: () => onOpenArtist(t.displayArtist!),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(t.displayArtist!, style: ts(c: lk.acc)),
                ),
              ),
            const SizedBox(height: 12),
            Btn.primary(readLabel, icon: Icons.menu_book, onTap: () => onRead(t, null)),
            if (t.lastPage > 0 || (t.isRead && !group)) ...[
              const SizedBox(height: 6),
              Btn('Start from the beginning', onTap: () => onRead(t, 0)),
            ],
            const SizedBox(height: 12),
            if (!group)
              Row(children: [
                Stars(value: t.rating, size: 22, onChanged: (v) => Library.I.setRating(t, v)),
                const Spacer(),
                IconBtn(t.favourite ? Icons.favorite : Icons.favorite_border,
                    tooltip: 'Favourite', color: t.favourite ? const Color(0xFFFF6FB1) : null,
                    onTap: () => Library.I.toggleFavourite([t])),
              ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final g in tags) TagChip(g.name, Color(g.color), onRemove: () => Library.I.removeTag(g, [t])),
              TagMenu(section: t.section, titles: group ? e.titles : [t]),
              if (!group)
                Btn(t.isRead ? 'Mark unread' : 'Mark read', dense: true, onTap: () => Library.I.markRead([t], !t.isRead)),
            ]),
            const SizedBox(height: 12),
            if (group) ...[
              Text('${e.titles.length} ${e is FolderEntry ? 'files' : 'chapters'} · ${e.titles.where((x) => x.isRead).length} read',
                  style: ts(c: tk.sec, size: 12)),
              const SizedBox(height: 6),
              for (final c in e.titles.take(200)) _chapterRow(context, c, t),
              if (e.titles.length > 200) Text('Open the full page to see all ${e.titles.length}.', style: ts(c: tk.faint, size: 12)),
            ] else ...[
              row('Series', t.displaySeries != t.displayTitle ? t.displaySeries : null),
              row('Chapter', t.displayChapter == null ? null : num(t.displayChapter!)),
              row('Circle', t.circle),
              row('Parody', t.parody),
              row('Source', t.source),
              row('Language', t.language),
              row('Pages', t.unreadable ? 'Can\'t be read (the file looks damaged)' : '${t.pages}'),
              row('Size', humanSize(t.size)),
              row('Times read', t.readCount > 0 ? '${t.readCount}' : 'Not read yet'),
              row('Last read', t.lastReadAt > 0 ? dateText(t.lastReadAt) : null),
              row('Time reading', t.timeSpent > 0 ? humanHours(t.timeSpent) : null),
              row('Added', dateText(t.addedAt)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _chapterRow(BuildContext context, Title c, Title current) => Hoverable(
        builder: (h) => GestureDetector(
          onTap: () => onRead(c, null),
          onSecondaryTapDown: (d) async {
            final prev = Library.I.previousChapters(c);
            final v = await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, d.globalPosition.dx + 1, d.globalPosition.dy + 1),
              items: [
                PopupMenuItem(value: 'mark', child: Text(c.isRead ? 'Mark unread' : 'Mark read', style: ts())),
                if (prev.isNotEmpty) PopupMenuItem(value: 'prev', child: Text('Mark previous as read (${prev.length})', style: ts())),
              ],
            );
            if (v == 'mark') Library.I.markRead([c], !c.isRead);
            if (v == 'prev') Library.I.markRead(prev, true);
          },
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: c.id == current.id ? lk.tint(tk.panel, 0.12) : (h ? tk.raised : null),
              borderRadius: BorderRadius.circular(lk.rControl),
            ),
            child: Row(children: [
              SizedBox(
                width: 54,
                child: Text(c.displayChapter != null ? 'Ch. ${num(c.displayChapter!)}' : (c.orderPrefix != null ? '#${c.orderPrefix}' : ''),
                    style: ts(c: tk.faint, size: 12, tab: true)),
              ),
              Expanded(child: Text(c.displayTitle, style: ts(size: 12.5, c: c.isRead ? tk.faint : tk.text), overflow: TextOverflow.ellipsis)),
              if (c.inProgress) SizedBox(width: 36, child: Progress(value: c.progress, height: 3)),
              if (c.isRead) Icon(Icons.check, size: 14, color: tk.ok),
            ]),
          ),
        ),
      );
}
