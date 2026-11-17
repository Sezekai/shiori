import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'look.dart';
import '../core/settings.dart';

Tokens get tk => Look.I.t;
Look get lk => Look.I;

TextStyle ts({double? size, FontWeight? w, Color? c, bool mono = false, bool tab = false}) => TextStyle(
      fontSize: size ?? lk.fontSize,
      fontWeight: w,
      color: c ?? tk.text,
      fontFamily: mono ? 'JetBrains Mono' : (lk.font == 'Inter' ? 'Inter' : lk.font),
      fontFeatures: tab ? const [FontFeature.tabularFigures()] : null,
      height: 1.25,
    );

enum BtnKind { primary, normal, ghost, dangerGhost, danger }

class Btn extends StatefulWidget {
  const Btn(this.label,
      {super.key, this.onTap, this.icon, this.kind = BtnKind.normal, this.tooltip, this.dense = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final BtnKind kind;
  final String? tooltip;
  final bool dense;

  const Btn.primary(this.label, {super.key, this.onTap, this.icon, this.tooltip, this.dense = false})
      : kind = BtnKind.primary;
  const Btn.ghost(this.label, {super.key, this.onTap, this.icon, this.tooltip, this.dense = false})
      : kind = BtnKind.ghost;

  @override
  State<Btn> createState() => _BtnState();
}

class _BtnState extends State<Btn> {
  bool hover = false;
  bool focus = false;

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    final enabled = widget.onTap != null;
    Color fg;
    Color? bg;
    Gradient? grad;
    Border? border;
    switch (k) {
      case BtnKind.primary:
        grad = lk.grad;
        fg = lk.onAcc;
      case BtnKind.normal:
        bg = hover ? tk.raised2 : tk.raised;
        fg = tk.text;
        border = Border.all(color: tk.line);
      case BtnKind.ghost:
        bg = hover ? tk.raised : null;
        fg = tk.sec;
      case BtnKind.dangerGhost:
        bg = hover ? tk.danger.withValues(alpha: 0.1) : null;
        fg = tk.danger;
        border = Border.all(color: tk.danger.withValues(alpha: 0.4));
      case BtnKind.danger:
        bg = tk.danger;
        fg = Colors.white;
    }
    final child = Container(
      height: widget.dense ? lk.hControl - 4 : lk.hControl,
      padding: EdgeInsets.symmetric(horizontal: widget.label.isEmpty ? 6 : 10),
      decoration: BoxDecoration(
        color: bg,
        gradient: grad,
        border: focus ? Border.all(color: lk.outline, width: lk.outlineWidth) : border,
        borderRadius: BorderRadius.circular(lk.rControl),
        boxShadow: lk.buttons == 'glow' && k == BtnKind.primary
            ? [BoxShadow(color: lk.acc.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4))]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (widget.icon != null) Icon(widget.icon, size: 16, color: fg),
        if (widget.icon != null && widget.label.isNotEmpty) const SizedBox(width: 6),
        if (widget.label.isNotEmpty)
          Text(widget.label, style: ts(w: FontWeight.w600, c: fg), overflow: TextOverflow.ellipsis),
      ]),
    );
    Widget w = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => focus = v),
        onShowHoverHighlight: (v) => setState(() => hover = v),
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call())},
        child: GestureDetector(onTap: widget.onTap, child: child),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, {super.key, this.onTap, this.tooltip, this.active = false, this.color, this.size = 16});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) {
    return _Hover(
      builder: (h) => Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: Container(
              width: lk.hControl,
              height: lk.hControl,
              decoration: BoxDecoration(
                color: active ? lk.tint(tk.raised, 0.2) : (h ? tk.raised2 : null),
                borderRadius: BorderRadius.circular(lk.rControl),
              ),
              child: Icon(icon, size: size, color: color ?? (active ? lk.acc : tk.sec)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hover extends StatefulWidget {
  const _Hover({required this.builder});
  final Widget Function(bool hover) builder;
  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => h = true),
        onExit: (_) => setState(() => h = false),
        child: widget.builder(h),
      );
}

class Hoverable extends StatelessWidget {
  const Hoverable({super.key, required this.builder});
  final Widget Function(bool hover) builder;
  @override
  Widget build(BuildContext context) => _Hover(builder: builder);
}

/// Segmented control: a field-coloured track; the chosen segment is raised2.
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.value, required this.items, required this.onChanged});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: lk.hControl,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: tk.field, borderRadius: BorderRadius.circular(lk.rControl),
          border: Border.all(color: tk.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final it in items)
          GestureDetector(
            onTap: () => onChanged(it.$1),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: it.$1 == value ? tk.raised2 : null,
                  borderRadius: BorderRadius.circular(lk.rControl - 1),
                ),
                child: Text(it.$2,
                    style: ts(w: FontWeight.w600, c: it.$1 == value ? tk.text : tk.sec, size: lk.fontSize - 1)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A drop-down styled like the other controls.
class Drop<T> extends StatelessWidget {
  const Drop({super.key, required this.value, required this.items, required this.onChanged, this.width});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final label = items.where((e) => e.$1 == value).map((e) => e.$2).firstOrNull ?? '';
    return PopupMenuButton<T>(
      tooltip: '',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final it in items)
          PopupMenuItem<T>(
            value: it.$1,
            height: lk.hControl + 4,
            child: Text(it.$2, style: ts(c: it.$1 == value ? lk.acc : tk.text)),
          ),
      ],
      child: Container(
        height: lk.hControl,
        width: width,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(color: tk.raised, borderRadius: BorderRadius.circular(lk.rControl),
            border: Border.all(color: tk.line)),
        child: Row(mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max, children: [
          Flexible(child: Text(label, style: ts(), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 14, color: tk.sec),
        ]),
      ),
    );
  }
}

/// Text box: a little taller than buttons, with the icon, text and hint on one centred line.
class Field extends StatefulWidget {
  const Field({super.key, this.controller, this.hint, this.onChanged, this.onSubmitted, this.focusNode,
      this.width, this.icon, this.autofocus = false, this.mono = false});
  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final double? width;
  final IconData? icon;
  final bool autofocus;
  final bool mono;

  static double get height => lk.hControl + 6;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final FocusNode _own = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _own;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Container(
        height: Field.height,
        width: widget.width,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tk.field,
          borderRadius: BorderRadius.circular(lk.rControl),
          border: Border.all(color: focused ? lk.outline : tk.line, width: focused ? lk.outlineWidth : 1),
        ),
        child: Row(children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 16, color: focused ? tk.sec : tk.faint),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: ts(mono: widget.mono),
              cursorColor: lk.acc,
              cursorHeight: lk.fontSize + 3,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: ts(c: tk.faint, mono: widget.mono)),
            ),
          ),
        ]),
      ),
    );
  }
}

class PanelBox extends StatelessWidget {
  const PanelBox({super.key, required this.child, this.padding = const EdgeInsets.all(10)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(lk.rPanel),
            border: Border.all(color: tk.line)),
        child: child,
      );
}

/// 24 px round pill, for filters.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.active = false, this.negative = false, this.onTap, this.onClose, this.color});
  final String label;
  final bool active;
  final bool negative;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? (negative ? tk.danger : lk.acc);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          height: 24,
          padding: EdgeInsets.only(left: 10, right: onClose == null ? 10 : 4),
          decoration: BoxDecoration(
            color: active ? Color.lerp(tk.raised, c, 0.2) : tk.raised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? c.withValues(alpha: 0.6) : tk.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (negative) Text('not ', style: ts(size: lk.fontSize - 1, c: tk.danger, w: FontWeight.w600)),
            Text(label, style: ts(size: lk.fontSize - 1, c: active ? tk.text : tk.sec, w: FontWeight.w600)),
            if (onClose != null)
              GestureDetector(onTap: onClose, child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.close, size: 13, color: tk.sec),
              )),
          ]),
        ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.name, this.color, {super.key, this.onTap, this.onRemove});
  final String name;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 20,
          padding: EdgeInsets.only(left: 8, right: onRemove == null ? 8 : 3),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.7))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: ts(size: lk.fontSize - 2, c: color, w: FontWeight.w600)),
            if (onRemove != null)
              GestureDetector(onTap: onRemove, child: Icon(Icons.close, size: 12, color: color)),
          ]),
        ),
      );
}

/// Half-star rating, 0.5 to 5. Tapping the current value clears it.
class Stars extends StatelessWidget {
  const Stars({super.key, required this.value, this.onChanged, this.size = 18});
  final double value;
  final ValueChanged<double>? onChanged;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        SizedBox(
          width: size,
          height: size,
          child: Stack(children: [
            Icon(
              value >= i ? Icons.star_rounded : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
              size: size,
              color: value >= i - 0.5 ? lk.acc : tk.faint,
            ),
            if (onChanged != null)
              Row(children: [
                Expanded(child: _starHit(i - 0.5)),
                Expanded(child: _starHit(i.toDouble())),
              ]),
          ]),
        ),
    ]);
  }

  Widget _starHit(double v) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged!(value == v ? 0 : v),
        ),
      );
}

class Progress extends StatelessWidget {
  const Progress({super.key, required this.value, this.height = 6});
  final double? value; // null = sliding bar
  final double height;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: tk.raised2,
        child: value == null
            ? const _Sliding()
            : FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value!.clamp(0.0, 1.0),
                child: DecoratedBox(decoration: BoxDecoration(gradient: lk.grad)),
              ),
      ),
    );
  }
}

class _Sliding extends StatefulWidget {
  const _Sliding();
  @override
  State<_Sliding> createState() => _SlidingState();
}

class _SlidingState extends State<_Sliding> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (_, _) => FractionallySizedBox(
          alignment: Alignment(-1.4 + 2.8 * c.value, 0),
          widthFactor: 0.3,
          child: DecoratedBox(decoration: BoxDecoration(gradient: lk.grad)),
        ),
      );
}

// ---------------- dialogs and toasts ----------------

Future<bool> confirm(BuildContext context, String title, String body,
    {String confirmLabel = 'OK', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (c) => AppDialog(
      title: title,
      body: Text(body, style: ts(c: tk.sec)),
      actions: [
        Btn(confirmLabel, kind: danger ? BtnKind.danger : BtnKind.primary, onTap: () => Navigator.pop(c, true)),
        Btn('Cancel', onTap: () => Navigator.pop(c, false)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> ask(BuildContext context, String title, {String? body, String initial = '', String confirmLabel = 'OK'}) async {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (c) => AppDialog(
      title: title,
      focusActions: false,
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (body != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(body, style: ts(c: tk.sec))),
        Field(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v.trim())),
      ]),
      actions: [
        Btn.primary(confirmLabel, onTap: () => Navigator.pop(c, ctl.text.trim())),
        Btn('Cancel', onTap: () => Navigator.pop(c)),
      ],
    ),
  );
}

/// Every dialog: the first button starts selected, ← → (and Tab) move
/// between buttons, Enter or Space presses the selected one, Esc closes.
class AppDialog extends StatefulWidget {
  const AppDialog({super.key, required this.title, required this.body, required this.actions, this.width = 440,
      this.focusActions = true});
  final String title;
  final Widget body;
  final List<Widget> actions;
  final double width;
  /// False when a text box should have the keyboard instead.
  final bool focusActions;
  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  final FocusScopeNode _buttons = FocusScopeNode(debugLabel: 'dialog buttons');
  late final FocusHighlightStrategy _was = FocusManager.instance.highlightStrategy;

  @override
  void initState() {
    super.initState();
    // Show which button is selected even if the dialog was opened with the mouse.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    if (widget.focusActions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _buttons.requestFocus();
        _buttons.nextFocus();
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.highlightStrategy = _was;
    _buttons.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: tk.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(lk.rPanel), side: BorderSide(color: tk.line2)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.width),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: ts(size: lk.fontSize + 2, w: FontWeight.w700)),
            const SizedBox(height: 10),
            Flexible(child: widget.body),
            const SizedBox(height: 16),
            Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousFocusIntent(),
                SingleActivator(LogicalKeyboardKey.arrowRight): NextFocusIntent(),
                SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
                SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
              },
              child: FocusScope(
                node: _buttons,
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    for (var i = 0; i < widget.actions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: FocusTraversalOrder(order: NumericFocusOrder(i.toDouble()), child: widget.actions[i]),
                      ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

enum ToastKind { ok, error, info }

class Toasts extends ChangeNotifier {
  Toasts._();
  static final Toasts I = Toasts._();
  final List<(String, ToastKind, int)> items = [];
  int _id = 0;
  void show(String msg, [ToastKind kind = ToastKind.ok]) {
    final id = ++_id;
    items.add((msg, kind, id));
    notifyListeners();
    Timer(Duration(seconds: msg.length > 60 ? 7 : 4), () {
      items.removeWhere((e) => e.$3 == id);
      notifyListeners();
    });
  }
}

void toast(String msg, [ToastKind kind = ToastKind.ok]) => Toasts.I.show(msg, kind);

class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Toasts.I,
      builder: (_, _) => Positioned(
        right: 16,
        bottom: 52,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final t in Toasts.I.items)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: tk.panel,
                borderRadius: BorderRadius.circular(lk.rPanel),
                border: Border.all(color: tk.line2),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  switch (t.$2) {
                    ToastKind.ok => Icons.check_circle_outline,
                    ToastKind.error => Icons.error_outline,
                    ToastKind.info => Icons.info_outline,
                  },
                  size: 16,
                  color: switch (t.$2) {
                    ToastKind.ok => tk.ok,
                    ToastKind.error => tk.danger,
                    ToastKind.info => lk.acc,
                  },
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(t.$1, style: ts())),
              ]),
            ),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28, color: tk.faint),
          const SizedBox(height: 10),
          Text(text, style: ts(c: tk.sec), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ]),
      );
}

class Banner1 extends StatelessWidget {
  const Banner1({super.key, required this.icon, required this.lead, required this.text, this.action});
  final IconData icon;
  final String lead;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Color.lerp(tk.panel, lk.acc, 0.06),
          borderRadius: BorderRadius.circular(lk.rPanel),
          border: Border.all(color: lk.acc.withValues(alpha: 0.26)),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: lk.acc),
          const SizedBox(width: 8),
          Text(lead, style: ts(w: FontWeight.w600)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: ts(c: tk.sec), overflow: TextOverflow.ellipsis)),
          if (action != null) action!,
        ]),
      );
}

String dateText(int epochSec) {
  if (epochSec <= 0) return 'date unknown';
  final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String timeText(int epochSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}


/// Draws everything inside at [scale]: text, icons and spacing grow together.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < 0.001) return child;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth / scale, h = c.maxHeight / scale;
      final mq = MediaQuery.of(context);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: w,
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: MediaQuery(data: mq.copyWith(size: Size(w, h)), child: SizedBox(width: w, height: h, child: child)),
          ),
        ),
      );
    });
  }
}

/// A thin handle to drag a panel or column wider or narrower.
class DragHandle extends StatelessWidget {
  const DragHandle({super.key, required this.onDrag, this.onEnd, this.width = 6, this.line = true});
  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd;
  final double width;
  final bool line;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) => onEnd?.call(),
          child: SizedBox(
            width: width,
            child: line ? Center(child: Container(width: 1, color: tk.line)) : null,
          ),
        ),
      );
}

/// One column of a list view.
class Col {
  const Col(this.key, this.label, this.width, {this.min = 40, this.sort, this.right = false});
  final String key;
  final String label;
  final double width;
  final double min;
  final String? sort; // sort key, when clicking the header sorts
  final bool right;
}

/// Columns whose widths can be dragged and are remembered (Settings.widths).
/// Columns keep their widths when the window is wide, so a row's details
/// stay close together instead of spreading across the screen.
class ColumnSet {
  const ColumnSet(this.table, this.cols);
  final String table;
  final List<Col> cols;

  double w(Col c) => Settings.I.width('$table.${c.key}', c.width).clamp(c.min, 2400);

  Widget header({String? sort, bool desc = false, ValueChanged<String>? onSort, double leading = 0}) {
    return ListenableBuilder(
      listenable: Settings.I,
      builder: (_, _) => Container(
        height: 30,
        decoration: BoxDecoration(color: tk.panel, border: Border(bottom: BorderSide(color: tk.line))),
        child: Row(children: [
          SizedBox(width: leading),
          for (final c in cols) ...[
            SizedBox(
              width: w(c) - 6,
              child: GestureDetector(
                onTap: c.sort == null || onSort == null ? null : () => onSort(c.sort!),
                child: MouseRegion(
                  cursor: c.sort == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: Padding(
                    padding: EdgeInsets.only(right: c.right ? 4 : 0),
                    child: Row(mainAxisAlignment: c.right ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
                    Flexible(
                        child: Text(c.label,
                            style: ts(size: 12, w: FontWeight.w600, c: tk.sec), overflow: TextOverflow.ellipsis)),
                    if (c.sort != null && c.sort == sort)
                      Icon(desc ? Icons.arrow_drop_down : Icons.arrow_drop_up, size: 16, color: lk.acc),
                  ]),
                  ),
                ),
              ),
            ),
            DragHandle(
              onDrag: (dx) => Settings.I.setWidth('$table.${c.key}', (w(c) + dx).clamp(c.min, 2400)),
              onEnd: Settings.I.save,
            ),
          ],
        ]),
      ),
    );
  }

  /// Cells in the same widths as the header. Pass one widget per column.
  Widget row(List<Widget> cells, {double leading = 0}) => Row(children: [
        SizedBox(width: leading),
        for (var i = 0; i < cols.length; i++)
          SizedBox(
            width: w(cols[i]),
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Align(alignment: cols[i].right ? Alignment.centerRight : Alignment.centerLeft, child: cells[i]),
            ),
          ),
      ]);
}

/// Row background: every other row a shade lighter, plus hover and selection.
Color? rowColor(int i, {bool hover = false, bool selected = false, bool cursor = false}) {
  if (selected) return lk.tint(tk.field, 0.17);
  if (cursor) return lk.tint(tk.field, 0.1);
  if (hover) return tk.raised;
  return i.isOdd ? Color.lerp(tk.field, tk.raised, 0.45) : null;
}
