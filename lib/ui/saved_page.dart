import 'dart:io';

import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/library.dart';
import '../core/settings.dart';
import 'app.dart';
import 'widgets.dart';

/// Everything saved from the reader, so the same page is never saved twice.
class SavedPagesPage extends StatefulWidget {
  const SavedPagesPage({super.key});
  @override
  State<SavedPagesPage> createState() => _SavedPagesPageState();
}

class _SavedPagesPageState extends State<SavedPagesPage> {
  Section section = Nav.I.section;

  @override
  Widget build(BuildContext context) {
    final list = Db.I.savedPages(section);
    final folder = Settings.I.of(section).saveFolder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Saved pages', style: ts(size: 15, w: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Pages you saved. Shiori remembers them even after you move the files, so nothing is saved twice.',
                  style: ts(c: tk.sec), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        PanelBox(
          child: Row(children: [
            Seg<Section>(
              value: section,
              items: [for (final s in Section.values) (s, s.label)],
              onChanged: (v) => setState(() => section = v),
            ),
            const SizedBox(width: 12),
            Text('Saves to', style: ts(c: tk.sec)),
            const SizedBox(width: 6),
            Expanded(child: Text(folder, style: ts(mono: true, size: 12), overflow: TextOverflow.ellipsis)),
            Btn('Open folder', icon: Icons.folder_open_outlined, onTap: () {
              if (Platform.isWindows && Directory(folder).existsSync()) Process.run('explorer.exe', [folder]);
            }),
            const SizedBox(width: 6),
            Btn('Change in Settings', onTap: () => Nav.I.go(PageId.settings)),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(icon: Icons.bookmark_border, text: 'No saved pages yet. Press P in the reader to save a page.')
              : ListView.builder(
                  itemCount: list.length,
                  itemExtent: lk.hRow + 16,
                  itemBuilder: (_, i) {
                    final sp = list[i];
                    final t = Library.I.byId(sp.titleId);
                    final exists = File(sp.path).existsSync();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tk.line))),
                      child: Row(children: [
                        SizedBox(width: 110, child: Text(dateText(sp.at), style: ts(c: tk.sec, tab: true))),
                        Expanded(child: Text(t?.displayTitle ?? 'Removed title', style: ts(), overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 90, child: Text('p${sp.pages}', style: ts(c: tk.sec, tab: true))),
                        SizedBox(
                            width: 320,
                            child: Text(exists ? p.basename(sp.path) : '${p.basename(sp.path)} (moved)',
                                style: ts(c: exists ? tk.sec : tk.faint, size: 12, mono: true), overflow: TextOverflow.ellipsis)),
                        Btn.ghost('Forget this save', dense: true, onTap: () async {
                          if (await confirm(context, 'Forget this save?',
                              'Shiori will let you save this page again. The saved image itself isn\'t touched.',
                              confirmLabel: 'Forget save')) {
                            Db.I.forgetSaved(sp.id);
                            setState(() {});
                          }
                        }),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
