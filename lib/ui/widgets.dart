import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'look.dart';

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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
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

class Field extends StatelessWidget {
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
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: lk.hControl,
      width: width,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: ts(mono: mono),
        textAlignVertical: TextAlignVertical.center,
        cursorColor: lk.acc,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: ts(c: tk.faint),
          prefixIcon: icon == null ? null : Icon(icon, size: 16, color: tk.faint),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          filled: true,
          fillColor: tk.field,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(lk.rControl),
              borderSide: BorderSide(color: tk.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(lk.rControl),
              borderSide: BorderSide(color: lk.outline, width: lk.outlineWidth)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(lk.rControl)),
        ),
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
        Btn('Cancel', onTap: () => Navigator.pop(c, false)),
        Btn(confirmLabel, kind: danger ? BtnKind.danger : BtnKind.primary, onTap: () => Navigator.pop(c, true)),
      ],
      onEnter: () => Navigator.pop(c, true),
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
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (body != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(body, style: ts(c: tk.sec))),
        Field(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v.trim())),
      ]),
      actions: [
        Btn('Cancel', onTap: () => Navigator.pop(c)),
        Btn.primary(confirmLabel, onTap: () => Navigator.pop(c, ctl.text.trim())),
      ],
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.body, required this.actions, this.width = 440, this.onEnter});
  final String title;
  final Widget body;
  final List<Widget> actions;
  final double width;
  final VoidCallback? onEnter;
  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (onEnter != null) const SingleActivator(LogicalKeyboardKey.enter): onEnter!,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: tk.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(lk.rPanel), side: BorderSide(color: tk.line2)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: ts(size: lk.fontSize + 2, w: FontWeight.w700)),
                const SizedBox(height: 10),
                Flexible(child: body),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
                ]),
              ]),
            ),
          ),
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
