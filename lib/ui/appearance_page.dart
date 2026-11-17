import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../core/paths.dart';
import 'look.dart';
import 'widgets.dart';

/// Appearance (DESIGN.md): themes, background, accent, font, shape, density.
class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});
  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  Look get l => Look.I;

  void _changed() {
    l.changed();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Look.I,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Appearance', style: ts(size: 15, w: FontWeight.w700)),
            const SizedBox(width: 10),
            Expanded(child: Text('Colours, font, corners and spacing. Themes move between your apps as theme files.', style: ts(c: tk.sec))),
            Btn('Reset to default', kind: BtnKind.dangerGhost, onTap: () async {
              if (await confirm(context, 'Reset the look?', 'Obsidian, Lime → Teal, Inter, standard corners and compact spacing come back. Saved themes stay.',
                  confirmLabel: 'Reset look')) {
                l.resetToDefault();
              }
            }),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 292, child: _themes()),
              const SizedBox(width: 8),
              Expanded(child: ListView(children: [_preview(), _sizes(), _background(), _accent(), _font(), _shape()])),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _themes() {
    Widget card(String name, Map<String, dynamic>? json, {bool builtIn = false}) {
      final active = builtIn ? l.activeTheme == null && l.background == 'Obsidian' : l.activeTheme == name;
      final bg = json?['background'] as Map?;
      final stops = ((json?['accent'] as Map?)?['stops'] as List?)?.cast<String>() ?? ['#b6f05a', '#2fd6b4'];
      Color c(String k, String d) => hexColor((bg?[k] as String?) ?? d);
      return GestureDetector(
        onTap: () {
          if (builtIn) {
            l.resetToDefault();
          } else {
            l.applyJson(json!);
            l.activeTheme = name;
            l.save();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tk.raised,
            borderRadius: BorderRadius.circular(lk.rControl + 2),
            border: Border.all(color: active ? lk.outline : tk.line, width: active ? lk.outlineWidth : 1),
          ),
          child: Row(children: [
            for (final col in [c('ground', '#0a0a0b'), c('panel', '#111113'), c('raised', '#19191c')])
              Container(width: 14, height: 22, color: col),
            Container(width: 22, height: 22, decoration: BoxDecoration(gradient: LinearGradient(colors: stops.map(hexColor).toList().length == 1 ? [hexColor(stops.first), hexColor(stops.first)] : stops.map(hexColor).toList()))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: ts(w: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(((json?['font'] as Map?)?['family'] as String?) ?? 'Inter', style: ts(c: tk.faint, size: 11.5)),
              ]),
            ),
            if (!builtIn)
              PopupMenuButton<String>(
                tooltip: '',
                icon: Icon(Icons.more_horiz, size: 16, color: tk.sec),
                onSelected: (v) => _themeAction(v, name),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rename', child: Text('Rename…', style: ts())),
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate', style: ts())),
                  if (l.activeTheme == name) PopupMenuItem(value: 'update', child: Text('Update with the current look', style: ts())),
                  PopupMenuItem(value: 'export', child: Text('Export…', style: ts())),
                  PopupMenuItem(value: 'delete', child: Text('Delete', style: ts(c: tk.danger))),
                ],
              ),
          ]),
        ),
      );
    }

    return PanelBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Themes', style: ts(w: FontWeight.w700)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(children: [
            card('Default', null, builtIn: true),
            for (final t in l.saved) card(t['name'] as String? ?? 'Theme', t),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Btn('Save as theme…', onTap: () async {
            final name = await ask(context, 'Save as theme', body: 'Saves the current look under a name.', confirmLabel: 'Save theme');
            if (name == null || name.isEmpty) return;
            l.saved.removeWhere((t) => t['name'] == name);
            l.saved.add(l.toJson(name: name));
            l.activeTheme = name;
            l.save();
          }),
          Btn('Import…', onTap: () async {
            final r = await FilePicker.pickFiles(dialogTitle: 'Import a theme file', type: FileType.custom, allowedExtensions: ['json']);
            final path = r.isEmpty ? null : r.single.path;
            if (path == null) return;
            try {
              final m = jsonDecode(await File(path).readAsString()) as Map;
              final name = (m['name'] as String?) ?? 'Imported theme';
              l.saved.removeWhere((t) => t['name'] == name);
              l.saved.add({...m.cast<String, dynamic>(), 'name': name});
              l.applyJson(m);
              l.activeTheme = name;
              l.save();
              toast('Imported "$name"');
            } catch (e) {
              toast('That file isn\'t a theme file Shiori can read', ToastKind.error);
            }
          }),
          Btn('Export…', onTap: () => _export(l.activeTheme ?? 'Shiori theme', l.toJson(name: l.activeTheme ?? 'Shiori theme'))),
        ]),
      ]),
    );
  }

  Future<void> _export(String name, Map<String, dynamic> json) async {
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(json)));
    final uri = await FilePicker.saveFile(dialogTitle: 'Export theme', fileName: '${safeFileName(name)}.theme.json', bytes: bytes);
    if (uri == null) return;
    toast('Theme exported');
  }

  void _themeAction(String v, String name) async {
    final i = l.saved.indexWhere((t) => t['name'] == name);
    if (i < 0) return;
    switch (v) {
      case 'rename':
        final n = await ask(context, 'Rename theme', initial: name, confirmLabel: 'Rename');
        if (n == null || n.isEmpty) return;
        l.saved[i]['name'] = n;
        if (l.activeTheme == name) l.activeTheme = n;
      case 'duplicate':
        l.saved.add({...l.saved[i], 'name': '$name copy'});
      case 'update':
        l.saved[i] = l.toJson(name: name);
      case 'export':
        await _export(name, l.saved[i]);
      case 'delete':
        if (!mounted) return;
        if (!await confirm(context, 'Delete the theme "$name"?', 'The current look stays as it is.', confirmLabel: 'Delete theme', danger: true)) return;
        l.saved.removeAt(i);
        if (l.activeTheme == name) l.activeTheme = null;
    }
    l.save();
  }

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(lk.rPanel), border: Border.all(color: tk.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: ts(w: FontWeight.w700)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _preview() => _section('Preview', [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Btn.primary('Main action', onTap: _noop),
          const Btn('Button', onTap: _noop),
          const Btn.ghost('Ghost', onTap: _noop),
          const Btn('Reset', kind: BtnKind.dangerGhost, onTap: _noop),
          Drop<int>(value: 1, items: const [(1, 'Drop-down'), (2, 'Other')], onChanged: (_) {}),
          Checkbox(value: true, onChanged: (_) {}),
          Seg<int>(value: 1, items: const [(1, 'All'), (2, 'Not read 8')], onChanged: (_) {}),
          const SizedBox(width: 180, child: Progress(value: 0.58)),
          Text('Done', style: ts(c: tk.ok, w: FontWeight.w600)),
          Text('Needs attention', style: ts(c: tk.warn, w: FontWeight.w600)),
          Text('Failed', style: ts(c: tk.danger, w: FontWeight.w600)),
          TagChip('To read', Color(categoryColors[0])),
          TagChip('On hold', Color(categoryColors[2])),
        ]),
      ]);

  static void _noop() {}

  Widget _background() => _section('Background', [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final name in backgroundPresets.keys)
            Pill(name, active: l.background == name, onTap: () {
              final t = backgroundPresets[name]!();
              l.t = t;
              l.background = name;
              if (name == 'Indigo') l.accent = [hexColor('#2fd6c0'), hexColor('#8b7bff')];
              _changed();
            }),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, children: [
          for (final n in [...Tokens.names, 'ok', 'warn', 'danger']) _colorField(n),
        ]),
        const SizedBox(height: 6),
        Text(
            'Text contrast on panels: ${contrast(tk.text, tk.panel).toStringAsFixed(1)} · secondary ${contrast(tk.sec, tk.panel).toStringAsFixed(1)} · faint ${contrast(tk.faint, tk.panel).toStringAsFixed(1)} (4.5 or more reads well)',
            style: ts(c: contrast(tk.faint, tk.panel) < 4.5 ? tk.warn : tk.faint, size: 12)),
      ]);

  Widget _colorField(String n) {
    final ctl = TextEditingController(text: colorHex(tk.get(n)));
    return SizedBox(
      width: 168,
      child: Row(children: [
        GestureDetector(
          onTap: () => _pick(n),
          child: Container(width: 22, height: 22, decoration: BoxDecoration(color: tk.get(n), border: Border.all(color: tk.line2), borderRadius: BorderRadius.circular(4))),
        ),
        const SizedBox(width: 6),
        SizedBox(width: 56, child: Text(n, style: ts(c: tk.sec, size: 12))),
        Expanded(
          child: Field(
            controller: ctl,
            mono: true,
            onSubmitted: (v) {
              if (RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(v.trim())) {
                tk.set(n, hexColor(v));
                _changed();
              }
            },
          ),
        ),
      ]),
    );
  }

  void _pick(String n) async {
    final swatches = [
      for (final p in backgroundPresets.values) p().get(n),
    ];
    final c = await showDialog<Color>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Colour for $n',
        body: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in swatches)
            GestureDetector(
              onTap: () => Navigator.pop(ctx, s),
              child: Container(width: 28, height: 28, decoration: BoxDecoration(color: s, border: Border.all(color: tk.line2), borderRadius: BorderRadius.circular(4))),
            ),
        ]),
        actions: [Btn('Cancel', onTap: () => Navigator.pop(ctx))],
      ),
    );
    if (c != null) {
      tk.set(n, c);
      _changed();
    }
  }

  Widget _accent() => _section('Accent', [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in accentPresets.entries)
            GestureDetector(
              onTap: () {
                l.accent = e.value.map(hexColor).toList();
                _changed();
              },
              child: Tooltip(
                message: e.key,
                child: Container(
                  width: 34,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: e.value.length == 1 ? [hexColor(e.value.first), hexColor(e.value.first)] : e.value.map(hexColor).toList()),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: l.accent.map(colorHex).join() == e.value.join() ? lk.outline : tk.line, width: 2),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text('Colours', style: ts(c: tk.sec)),
          const SizedBox(width: 8),
          for (var i = 0; i < l.accent.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 100,
                child: Field(
                  controller: TextEditingController(text: colorHex(l.accent[i])),
                  mono: true,
                  onSubmitted: (v) {
                    if (RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(v.trim())) {
                      l.accent[i] = hexColor(v);
                      _changed();
                    }
                  },
                ),
              ),
            ),
          if (l.accent.length < 4) IconBtn(Icons.add, tooltip: 'Add a colour', onTap: () {
            l.accent.add(l.accent.last);
            _changed();
          }),
          if (l.accent.length > 1) IconBtn(Icons.remove, tooltip: 'Remove a colour', onTap: () {
            l.accent.removeLast();
            _changed();
          }),
        ]),
        Row(children: [
          SizedBox(width: 120, child: Text('Direction ${l.angle.round()}°', style: ts(c: tk.sec))),
          SizedBox(width: 240, child: Slider(value: l.angle, min: 0, max: 360, onChanged: (v) {
            l.angle = v;
            _changed();
          })),
          const SizedBox(width: 16),
          Text('Text on the accent', style: ts(c: tk.sec)),
          const SizedBox(width: 8),
          Seg<String>(value: l.onAccent, items: const [('auto', 'Auto'), ('dark', 'Dark'), ('light', 'Light')], onChanged: (v) {
            l.onAccent = v;
            _changed();
          }),
          const SizedBox(width: 8),
          Builder(builder: (_) {
            final c = l.accent.map((a) => contrast(a, l.onAcc)).reduce((a, b) => a < b ? a : b);
            return Text('Contrast ${c.toStringAsFixed(1)}', style: ts(c: c < 4.5 ? tk.warn : tk.faint, size: 12));
          }),
        ]),
      ]);

  Widget _scaleRow(String label, String hint, double value, double lo, double hi, ValueChanged<double> on) => Row(children: [
        SizedBox(width: 150, child: Text(label, style: ts(c: tk.sec))),
        SizedBox(
          width: 280,
          child: Slider(
            value: value.clamp(lo, hi),
            min: lo,
            max: hi,
            divisions: ((hi - lo) / 0.05).round(),
            onChanged: (v) {
              on((v * 20).round() / 20);
              setState(() {});
            },
            onChangeEnd: (_) => _changed(),
          ),
        ),
        SizedBox(width: 56, child: Text('${(value * 100).round()}%', style: ts(tab: true, w: FontWeight.w600))),
        Expanded(child: Text(hint, style: ts(c: tk.faint, size: 12))),
      ]);

  Widget _sizes() => _section('Sizes', [
        _scaleRow('Main window', 'Everything in the window: text, icons, buttons, lists and dialogs.', l.uiScale, 0.8, 1.6,
            (v) => l.uiScale = v),
        _scaleRow('Reader controls', 'The bars, buttons and page number in the reader. Pages aren\'t affected.',
            l.readerScale, 0.8, 2.0, (v) => l.readerScale = v),
        Row(children: [
          SizedBox(width: 150, child: Text('Cover corners', style: ts(c: tk.sec))),
          SizedBox(
            width: 280,
            child: Slider(
              value: l.coverRadius.clamp(0, 24),
              min: 0,
              max: 24,
              divisions: 24,
              onChanged: (v) {
                l.coverRadius = v;
                setState(() {});
              },
              onChangeEnd: (_) => _changed(),
            ),
          ),
          SizedBox(width: 56, child: Text('${l.coverRadius.round()} px', style: ts(tab: true, w: FontWeight.w600))),
          Expanded(child: Text('Rounding on covers in the grid, panels and lists.', style: ts(c: tk.faint, size: 12))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Btn('Reset sizes', onTap: () {
            l.uiScale = 1;
            l.readerScale = 1;
            l.coverRadius = 6;
            _changed();
          }),
        ]),
      ]);

  Widget _font() => _section('Font', [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in [...bundledFonts, ...systemFonts])
            Pill(f, active: l.font == f, onTap: () {
              l.font = f;
              _changed();
            }),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('Text size', style: ts(c: tk.sec)),
          const SizedBox(width: 8),
          Seg<double>(value: l.fontSize, items: const [(12, '12'), (13, '13'), (14, '14'), (15, '15')], onChanged: (v) {
            l.fontSize = v;
            _changed();
          }),
          const SizedBox(width: 12),
          Text('System fonts show only if they\'re installed.', style: ts(c: tk.faint, size: 12)),
        ]),
      ]);

  Widget _shape() => _section('Shape, spacing and buttons', [
        Row(children: [
          SizedBox(width: 120, child: Text('Corners', style: ts(c: tk.sec))),
          Seg<String>(
            value: switch (l.rControl) { 0 => 'square', 3 => 'sharp', 6 => 'standard', 9 => 'soft', 14 => 'round', _ => '' },
            items: const [('square', 'Square'), ('sharp', 'Sharp'), ('standard', 'Standard'), ('soft', 'Soft'), ('round', 'Round')],
            onChanged: (v) {
              final (c, pnl) = switch (v) { 'square' => (0.0, 0.0), 'sharp' => (3.0, 5.0), 'soft' => (9.0, 14.0), 'round' => (14.0, 20.0), _ => (6.0, 10.0) };
              l.rControl = c;
              l.rPanel = pnl;
              _changed();
            },
          ),
        ]),
        Row(children: [
          SizedBox(width: 120, child: Text('Density', style: ts(c: tk.sec))),
          Seg<String>(
            value: switch (l.hControl) { 28 => 'compact', 32 => 'comfortable', 36 => 'roomy', _ => '' },
            items: const [('compact', 'Compact'), ('comfortable', 'Comfortable'), ('roomy', 'Roomy')],
            onChanged: (v) {
              final (c, r) = switch (v) { 'comfortable' => (32.0, 28.0), 'roomy' => (36.0, 32.0), _ => (28.0, 24.0) };
              l.hControl = c;
              l.hRow = r;
              _changed();
            },
          ),
        ]),
        Row(children: [
          SizedBox(width: 120, child: Text('Buttons', style: ts(c: tk.sec))),
          Seg<String>(value: l.buttons, items: const [('flat', 'Flat'), ('glow', 'Glow')], onChanged: (v) {
            l.buttons = v;
            _changed();
          }),
        ]),
        Row(children: [
          SizedBox(width: 120, child: Text('Outline width', style: ts(c: tk.sec))),
          Seg<double>(value: l.outlineWidth, items: const [(1, '1'), (2, '2'), (3, '3'), (4, '4')], onChanged: (v) {
            l.outlineWidth = v;
            _changed();
          }),
        ]),
      ]);
}
