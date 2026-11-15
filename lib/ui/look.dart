import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/paths.dart';

/// Colour tokens from DESIGN.md. Every colour on screen comes from here.
class Tokens {
  Color ground, rail, panel, raised, raised2, field, line, line2, text, sec, faint, stage;
  Color ok, warn, danger;
  Tokens({
    required this.ground,
    required this.rail,
    required this.panel,
    required this.raised,
    required this.raised2,
    required this.field,
    required this.line,
    required this.line2,
    required this.text,
    required this.sec,
    required this.faint,
    required this.stage,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  static const names = [
    'ground', 'rail', 'panel', 'raised', 'raised2', 'field', 'line', 'line2', 'text', 'sec', 'faint', 'stage',
  ];

  Color get(String n) => switch (n) {
        'ground' => ground,
        'rail' => rail,
        'panel' => panel,
        'raised' => raised,
        'raised2' => raised2,
        'field' => field,
        'line' => line,
        'line2' => line2,
        'text' => text,
        'sec' => sec,
        'faint' => faint,
        'stage' => stage,
        'ok' => ok,
        'warn' => warn,
        _ => danger,
      };

  void set(String n, Color c) {
    switch (n) {
      case 'ground': ground = c;
      case 'rail': rail = c;
      case 'panel': panel = c;
      case 'raised': raised = c;
      case 'raised2': raised2 = c;
      case 'field': field = c;
      case 'line': line = c;
      case 'line2': line2 = c;
      case 'text': text = c;
      case 'sec': sec = c;
      case 'faint': faint = c;
      case 'stage': stage = c;
      case 'ok': ok = c;
      case 'warn': warn = c;
      case 'danger': danger = c;
    }
  }

  Tokens copy() => Tokens(
        ground: ground, rail: rail, panel: panel, raised: raised, raised2: raised2, field: field,
        line: line, line2: line2, text: text, sec: sec, faint: faint, stage: stage, ok: ok,
        warn: warn, danger: danger);

  static Tokens fromHex(List<String> h, List<String> states) => Tokens(
        ground: hexColor(h[0]),
        rail: hexColor(h[1]),
        panel: hexColor(h[2]),
        raised: hexColor(h[3]),
        raised2: hexColor(h[4]),
        field: hexColor(h[5]),
        line: hexColor(h[6]),
        line2: hexColor(h[7]),
        text: hexColor(h[8]),
        sec: hexColor(h[9]),
        faint: hexColor(h[10]),
        stage: hexColor(h[11]),
        ok: hexColor(states[0]),
        warn: hexColor(states[1]),
        danger: hexColor(states[2]),
      );
}

Color hexColor(String h) {
  var s = h.replaceAll('#', '').trim();
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6) return const Color(0xFFFF00FF);
  return Color(int.parse('FF$s', radix: 16));
}

String colorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

const _darkStates = ['#52d39a', '#f2b64c', '#f0616d'];

final Map<String, Tokens Function()> backgroundPresets = {
  'Obsidian': () => Tokens.fromHex(['#0a0a0b', '#060607', '#111113', '#19191c', '#232327', '#070708',
    '#212125', '#2e2e33', '#ececee', '#a0a0a7', '#7d7d84', '#040405'], _darkStates),
  'Carbon': () => Tokens.fromHex(['#0d0d0d', '#080808', '#151515', '#1e1e1e', '#282828', '#0a0a0a',
    '#262626', '#333333', '#ededed', '#a3a3a3', '#808080', '#050505'], _darkStates),
  'Graphite': () => Tokens.fromHex(['#16171a', '#111214', '#1d1f23', '#26282d', '#30333a', '#121316',
    '#2c2f35', '#3a3e46', '#eceef2', '#a6aab3', '#858a94', '#0c0d0f'], _darkStates),
  'Midnight': () => Tokens.fromHex(['#0b0e14', '#080a0f', '#11151d', '#181d28', '#212837', '#080b10',
    '#222a38', '#2f394c', '#e8edf6', '#9ca6ba', '#7e889c', '#05070a'], _darkStates),
  'Ink blue': () => Tokens.fromHex(['#0a1020', '#070c18', '#101a30', '#17233f', '#1f2e52', '#070c18',
    '#22325a', '#2f4373', '#e6edfb', '#9fb0d4', '#8292b8', '#050812'], _darkStates),
  'Slate': () => Tokens.fromHex(['#12161b', '#0d1014', '#181e25', '#212931', '#2a343f', '#0e1216',
    '#283039', '#36414d', '#e7ecf1', '#a1acb8', '#828e9b', '#090c0f'], _darkStates),
  'Aubergine': () => Tokens.fromHex(['#130d17', '#0e0911', '#1b1220', '#25192c', '#302139', '#0e0912',
    '#2c1f34', '#3c2a47', '#f0e9f4', '#b3a2bd', '#9483a0', '#0a060c'], _darkStates),
  'Wine': () => Tokens.fromHex(['#150b0e', '#10080a', '#1d1014', '#28161c', '#341d25', '#10080b',
    '#301b22', '#43262f', '#f4e9ec', '#bca1a9', '#a0848c', '#0b0507'], _darkStates),
  'Forest': () => Tokens.fromHex(['#0b120e', '#080d0a', '#101a14', '#16231b', '#1d2d23', '#080d0a',
    '#1c2b22', '#28392e', '#e7f1ea', '#9fb5a6', '#81988a', '#050906'], _darkStates),
  'Deep teal': () => Tokens.fromHex(['#081214', '#060d0f', '#0d1b1e', '#132528', '#193034', '#060d0f',
    '#182d31', '#223e43', '#e4f2f3', '#9cb8bb', '#7e9a9e', '#040a0b'], _darkStates),
  'Mocha': () => Tokens.fromHex(['#14100d', '#0f0c0a', '#1c1713', '#26201a', '#302821', '#0f0c0a',
    '#2d261f', '#3d342b', '#f2ece6', '#b7aa9e', '#9a8d81', '#0a0806'], _darkStates),
  'Indigo': () => Tokens.fromHex(['#0e0f17', '#0a0b12', '#161826', '#1d2032', '#252942', '#0b0c13',
    '#2b3050', '#3a4170', '#e8eaf6', '#8d93b5', '#7c82a8', '#07080d'], ['#5be38a', '#ffbf5a', '#ff5f73']),
  'Daylight': () => Tokens.fromHex(['#f4f4f6', '#e9e9ed', '#ffffff', '#f0f0f3', '#e4e4ea', '#ffffff',
    '#dcdce2', '#c8c8d0', '#16161a', '#4a4a55', '#5f5f6a', '#e7e7ec'], ['#13804f', '#9a6400', '#c22b3a']),
  'Linen': () => Tokens.fromHex(['#f5f1ea', '#ebe5db', '#fbf8f3', '#efe9df', '#e4dccf', '#fffdf9',
    '#ddd4c5', '#c9bfae', '#1d1a15', '#4f483d', '#645c50', '#e8e1d5'], ['#2a7a4b', '#8f5d00', '#b5323b']),
};

final Map<String, List<String>> accentPresets = {
  'Lime → Teal': ['#b6f05a', '#2fd6b4'],
  'Violet → Blue': ['#9b6bff', '#4f8dff'],
  'Violet → Pink': ['#9b6bff', '#ff6fb1'],
  'Teal → Violet': ['#2fd6c0', '#8b7bff'],
  'Blue → Cyan': ['#4f7dff', '#35d2f2'],
  'Aqua → Lime': ['#3ee0d0', '#b6f05a'],
  'Mint → Sky': ['#6cf0b4', '#6cc4ff'],
  'Amber → Pink': ['#ffbf4a', '#ff6fa8'],
  'Coral → Orange': ['#ff6f6f', '#ffa24a'],
  'Sunset': ['#ff7a59', '#ff4f8b', '#9b6bff'],
  'Rose → Peach': ['#ff7aa8', '#ffb38a'],
  'Gold → Lime': ['#f2c94c', '#b6f05a'],
  'Aurora': ['#3ee0b0', '#4fa8ff', '#b07bff'],
  'Lime': ['#b6f05a'],
  'Teal': ['#2fd6b4'],
  'Blue': ['#4f8dff'],
  'Violet': ['#9b7bff'],
  'Green': ['#52d39a'],
  'Orange': ['#ffa24a'],
  'Pink': ['#ff6fb1'],
};

const categoryColors = [
  0xff9b86ff, 0xff2fe0c0, 0xffff6fb1, 0xffffbf5a, 0xff5aa8ff, 0xff5be38a, 0xffff8a5c, 0xffd07bff,
  0xff7fd4ff, 0xfff2e05a,
];

const systemFonts = ['Segoe UI', 'Segoe UI Variable', 'Bahnschrift', 'Aptos', 'Calibri', 'Satoshi'];
const bundledFonts = ['Inter'];

/// The Appearance state: current look, saved themes, stored in appearance.json.
class Look extends ChangeNotifier {
  Look._();
  static final Look I = Look._();

  Tokens t = backgroundPresets['Obsidian']!();
  String background = 'Obsidian';
  List<Color> accent = [hexColor('#b6f05a'), hexColor('#2fd6b4')];
  double angle = 90;
  String onAccent = 'auto';
  String font = 'Inter';
  double fontSize = 13;
  double rControl = 6;
  double rPanel = 10;
  double hControl = 28;
  double hRow = 24;
  String buttons = 'flat';
  Color? outlineColour;
  double outlineWidth = 2;
  Color? highlightColour;
  String? activeTheme;
  List<Map<String, dynamic>> saved = [];

  Color get acc => accent.first;
  Color get outline => outlineColour ?? acc;
  Color get highlight => highlightColour ?? acc;

  Gradient get grad {
    final stops = accent.length == 1 ? [accent.first, accent.first] : accent;
    final rad = (angle - 90) * 3.14159265 / 180;
    final dx = _cos(rad), dy = _sin(rad);
    return LinearGradient(begin: Alignment(-dx, -dy), end: Alignment(dx, dy), colors: stops);
  }

  static double _cos(double r) => math.cos(r);
  static double _sin(double r) => math.sin(r);

  Color get onAcc {
    if (onAccent == 'dark') return const Color(0xFF0B0C0F);
    if (onAccent == 'light') return Colors.white;
    final darkOk = accent.every((c) => contrast(c, const Color(0xFF0B0C0F)) >= 4.5);
    if (darkOk) return const Color(0xFF0B0C0F);
    final lightScore = accent.map((c) => contrast(c, Colors.white)).reduce((a, b) => a < b ? a : b);
    final darkScore = accent.map((c) => contrast(c, const Color(0xFF0B0C0F))).reduce((a, b) => a < b ? a : b);
    return lightScore > darkScore ? Colors.white : const Color(0xFF0B0C0F);
  }

  Color tint(Color surface, double amount) => Color.lerp(surface, highlight, amount)!;

  bool get isLight => t.ground.computeLuminance() > 0.5;

  Map<String, dynamic> toJson({String? name}) => {
        'version': 1,
        if (name != null) 'name': name,
        'background': {for (final n in Tokens.names) n: colorHex(t.get(n))},
        'states': {'ok': colorHex(t.ok), 'warn': colorHex(t.warn), 'danger': colorHex(t.danger)},
        'accent': {'stops': accent.map(colorHex).toList(), 'angle': angle, 'onAccent': onAccent},
        'font': {'family': font, 'size': fontSize},
        'corners': {'control': rControl, 'panel': rPanel},
        'density': {'control': hControl, 'row': hRow},
        'buttons': {'style': buttons},
        'outline': {'colour': outlineColour == null ? '' : colorHex(outlineColour!), 'width': outlineWidth},
        'highlight': {'colour': highlightColour == null ? '' : colorHex(highlightColour!)},
      };

  /// Reads a theme file. Missing or invalid values fall back to the default.
  void applyJson(Map m) {
    final d = backgroundPresets['Obsidian']!();
    Color c(Map? src, String k, Color fallback) {
      final v = src?[k];
      if (v is String && RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(v)) return hexColor(v);
      return fallback;
    }

    final bg = m['background'] as Map?;
    for (final n in Tokens.names) {
      t.set(n, c(bg, n, d.get(n)));
    }
    final st = m['states'] as Map?;
    t.ok = c(st, 'ok', d.ok);
    t.warn = c(st, 'warn', d.warn);
    t.danger = c(st, 'danger', d.danger);
    final a = m['accent'] as Map?;
    final stops = (a?['stops'] as List?)
            ?.whereType<String>()
            .where((s) => RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(s))
            .map(hexColor)
            .take(4)
            .toList() ??
        [];
    accent = stops.isEmpty ? [hexColor('#b6f05a'), hexColor('#2fd6b4')] : stops;
    angle = ((a?['angle'] as num?)?.toDouble() ?? 90).clamp(0, 360);
    onAccent = const ['auto', 'dark', 'light'].contains(a?['onAccent']) ? a!['onAccent'] as String : 'auto';
    final f = m['font'] as Map?;
    font = f?['family'] as String? ?? 'Inter';
    if (!bundledFonts.contains(font) && !systemFonts.contains(font)) font = 'Inter';
    fontSize = ((f?['size'] as num?)?.toDouble() ?? 13).clamp(11, 16);
    final co = m['corners'] as Map?;
    rControl = ((co?['control'] as num?)?.toDouble() ?? 6).clamp(0, 16);
    rPanel = ((co?['panel'] as num?)?.toDouble() ?? 10).clamp(0, 24);
    final de = m['density'] as Map?;
    hControl = ((de?['control'] as num?)?.toDouble() ?? 28).clamp(24, 44);
    hRow = ((de?['row'] as num?)?.toDouble() ?? 24).clamp(20, 40);
    buttons = (m['buttons'] as Map?)?['style'] == 'glow' ? 'glow' : 'flat';
    final o = m['outline'] as Map?;
    final oc = o?['colour'];
    outlineColour = oc is String && oc.isNotEmpty ? hexColor(oc) : null;
    outlineWidth = ((o?['width'] as num?)?.toDouble() ?? 2).clamp(1, 4);
    final h = (m['highlight'] as Map?)?['colour'];
    highlightColour = h is String && h.isNotEmpty ? hexColor(h) : null;
  }

  void load() {
    try {
      final f = File(AppPaths.I.appearanceFile);
      if (!f.existsSync()) return;
      final m = jsonDecode(f.readAsStringSync()) as Map;
      if (m['current'] is Map) applyJson(m['current'] as Map);
      background = m['backgroundPreset'] as String? ?? background;
      activeTheme = m['activeTheme'] as String?;
      saved = ((m['themes'] as List?) ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {}
  }

  void save() {
    try {
      writeStringSafelySync(
          AppPaths.I.appearanceFile,
          const JsonEncoder.withIndent('  ').convert({
            'current': toJson(),
            'backgroundPreset': background,
            'activeTheme': activeTheme,
            'themes': saved,
          }));
    } catch (_) {}
    notifyListeners();
  }

  void changed() {
    activeTheme = null;
    save();
  }

  void resetToDefault() {
    applyJson({});
    background = 'Obsidian';
    activeTheme = null;
    save();
  }

  ThemeData theme() {
    final family = font == 'Inter' ? 'Inter' : font;
    final base = isLight ? ThemeData.light() : ThemeData.dark();
    final text = base.textTheme.apply(fontFamily: family, bodyColor: t.text, displayColor: t.text);
    return base.copyWith(
      scaffoldBackgroundColor: t.ground,
      canvasColor: t.panel,
      colorScheme: (isLight ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
        primary: acc,
        onPrimary: onAcc,
        secondary: acc,
        surface: t.panel,
        onSurface: t.text,
        error: t.danger,
      ),
      textTheme: text.copyWith(
        bodyMedium: TextStyle(fontFamily: family, fontSize: fontSize, color: t.text),
        bodySmall: TextStyle(fontFamily: family, fontSize: fontSize - 1, color: t.sec),
        titleMedium: TextStyle(fontFamily: family, fontSize: fontSize + 2, fontWeight: FontWeight.w700, color: t.text),
        labelLarge: TextStyle(fontFamily: family, fontSize: fontSize, fontWeight: FontWeight.w600, color: t.text),
      ),
      dividerColor: t.line,
      focusColor: tint(t.panel, 0.2),
      hoverColor: t.raised2,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: t.raised2, borderRadius: BorderRadius.circular(rControl),
            border: Border.all(color: t.line2)),
        textStyle: TextStyle(color: t.text, fontSize: fontSize - 1, fontFamily: family),
        waitDuration: const Duration(milliseconds: 500),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? acc : Colors.transparent),
        checkColor: WidgetStatePropertyAll(onAcc),
        side: BorderSide(color: t.line2, width: 1.5),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: acc,
        inactiveTrackColor: t.raised2,
        thumbColor: acc,
        overlayShape: SliderComponentShape.noOverlay,
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(t.line2),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rPanel), side: BorderSide(color: t.line2)),
        textStyle: TextStyle(color: t.text, fontSize: fontSize, fontFamily: family),
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: acc, selectionColor: tint(t.field, 0.35)),
    );
  }
}

double _lum(Color c) => c.computeLuminance();
double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
