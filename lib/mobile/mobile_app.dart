import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/db.dart';
import '../core/jobs.dart';
import '../core/library.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import '../ui/look.dart';
import '../ui/widgets.dart';
import 'lock.dart';
import 'm_library.dart';
import 'm_more.dart';
import 'm_selftest.dart';
import 'pc.dart';
import 'store.dart';

const mobileVersion = String.fromEnvironment('SHIORI_VERSION', defaultValue: 'dev');

/// True on Android, or on the PC when testing the phone app.
bool get isMobile => Platform.isAndroid || Platform.environment['SHIORI_MOBILE'] == '1';

Future<void> runMobile({Widget? Function()? testHome}) async {
  WidgetsFlutterBinding.ensureInitialized();
  String data;
  final env = Platform.environment['SHIORI_DATA'];
  if (env != null && env.isNotEmpty) {
    data = env;
  } else {
    data = (await getApplicationSupportDirectory()).path;
  }
  AppPaths.I = AppPaths.at(data: data, cache: p.join(data, 'Cache'));
  AppLog.I.init(AppPaths.I.logs);
  AppLog.I.info('Shiori for Android $mobileVersion starting');
  FlutterError.onError = (d) => AppLog.I.error('Interface error', d.exception, d.stack);
  ui.PlatformDispatcher.instance.onError = (e, st) {
    AppLog.I.error('Unexpected error', e, st);
    return true;
  };

  Settings.I.load();
  final firstRun = !File(AppPaths.I.appearanceFile).existsSync();
  Look.I.load();
  if (firstRun) {
    // Bigger text and controls for fingers.
    Look.I.fontSize = 14.5;
    Look.I.hControl = 40;
    Look.I.hRow = 36;
  }
  Db.I = Db.open(AppPaths.I.db);
  Library.I.mobile = true;
  Library.I.load();
  await Thumbs.I.loadIndex();
  Store.I.init();
  Pc.I.start();
  Native.init();
  final selftest = Platform.environment['SHIORI_SELFTEST'] == '1';
  if (Platform.isLinux || Platform.isWindows) {
    // Testing on the PC: a phone-shaped window.
    await windowManager.ensureInitialized();
    final w = double.tryParse(Platform.environment['SHIORI_PHONE_W'] ?? '') ?? 412;
    final h = double.tryParse(Platform.environment['SHIORI_PHONE_H'] ?? '') ?? 900;
    await windowManager.setSize(Size(w, h));
  }
  runApp(RepaintBoundary(key: mShotKey, child: MobileApp(home: testHome?.call())));
  if (selftest) WidgetsBinding.instance.addPostFrameCallback((_) => mobileSelftest());
}

/// Talks to the Android side: volume keys and hiding the app in Recents.
class Native {
  static const channel = MethodChannel('shiori/native');
  static final volume = StreamController<String>.broadcast();

  static void init() {
    if (!Platform.isAndroid) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'volume') volume.add(call.arguments as String);
      return null;
    });
    setSecure(Settings.I.get<bool>('m.hideRecents', false));
  }

  static Future<void> setVolumeKeys(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod('volumeKeys', on);
    } catch (_) {}
  }

  static Future<void> setSecure(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod('secure', on);
    } catch (_) {}
  }

  static Future<String> deviceName() async {
    if (!Platform.isAndroid) return Platform.localHostname;
    try {
      return await channel.invokeMethod<String>('deviceName') ?? 'Android phone';
    } catch (_) {
      return 'Android phone';
    }
  }
}

class MobileApp extends StatelessWidget {
  const MobileApp({super.key, this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Look.I,
      builder: (_, _) => MaterialApp(
        navigatorKey: mNavKey,
        debugShowCheckedModeBanner: false,
        title: 'Shiori',
        theme: Look.I.theme().copyWith(
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: tk.rail,
                indicatorColor: lk.tint(tk.raised, 0.2),
                labelTextStyle: WidgetStatePropertyAll(ts(size: 12)),
                iconTheme: WidgetStateProperty.resolveWith(
                    (s) => IconThemeData(color: s.contains(WidgetState.selected) ? lk.acc : tk.sec)),
              ),
              appBarTheme: AppBarTheme(backgroundColor: tk.ground, foregroundColor: tk.text, elevation: 0, scrolledUnderElevation: 0),
              bottomSheetTheme: BottomSheetThemeData(backgroundColor: tk.panel, modalBackgroundColor: tk.panel),
              snackBarTheme: SnackBarThemeData(
                  backgroundColor: tk.raised2, contentTextStyle: ts(), behavior: SnackBarBehavior.floating),
            ),
        builder: (context, child) => AppLock(child: child ?? const SizedBox()),
        home: home ?? const MobileShell(),
      ),
    );
  }
}

final GlobalKey<NavigatorState> mNavKey = GlobalKey<NavigatorState>();

void mToast(String text) {
  final ctx = mNavKey.currentContext;
  if (ctx == null) return;
  ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});
  /// Which bottom tab is showing.
  static final ValueNotifier<int> tab = ValueNotifier(0);
  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int get tab => MobileShell.tab.value;
  StreamSubscription? _saves;

  @override
  void initState() {
    super.initState();
    Sync.saveResults.addListener(_onSaves);
    MobileShell.tab.addListener(_onTab);
    if (!Pc.I.paired && Library.I.titles(Section.comics).isEmpty && Library.I.titles(Section.manga).isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectScreen(first: true)));
      });
    }
  }

  void _onSaves() {
    final r = Sync.saveResults.value;
    final saved = r.where((x) => x['result'] == 'saved').length;
    final dup = r.where((x) => x['result'] == 'duplicate').length;
    if (saved > 0) mToast('$saved waiting page${saved == 1 ? '' : 's'} saved on the PC');
    if (dup > 0) mToast('$dup waiting page${dup == 1 ? ' is a duplicate' : 's are duplicates'}. See More → Waiting to save.');
  }

  @override
  void dispose() {
    Sync.saveResults.removeListener(_onSaves);
    MobileShell.tab.removeListener(_onTab);
    _saves?.cancel();
    super.dispose();
  }

  void _onTab() => setState(() {});
  void go(int i) => MobileShell.tab.value = i;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: tab, children: const [
          MLibraryScreen(),
          MHistoryScreen(),
          MStatsScreen(),
          MMoreScreen(),
        ]),
      ),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const JobBar(),
        NavigationBar(
          selectedIndex: tab,
          height: 62,
          onDestinationSelected: go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Stats'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ]),
    );
  }
}

/// The task running now: bar, percentage, time taken, time left, and what
/// it's doing, so you can see it's really moving. Tap to stop it.
class JobBar extends StatelessWidget {
  const JobBar({super.key, this.always = false});
  final bool always;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Jobs.I,
      builder: (context, _) {
        final j = Jobs.I.current;
        if (j == null) return const SizedBox();
        return JobProgress(job: j, queued: Jobs.I.queue.length);
      },
    );
  }
}

class JobProgress extends StatelessWidget {
  const JobProgress({super.key, required this.job, this.queued = 0, this.compact = false});
  final Job job;
  final int queued;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final f = job.fraction;
    final left = job.timeLeft;
    return Container(
      color: tk.panel,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text(job.name, style: ts(w: FontWeight.w600, size: 13), overflow: TextOverflow.ellipsis)),
              Text(f == null ? '' : '${(f * 100).floor()}%', style: ts(tab: true, w: FontWeight.w700, c: lk.acc)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: f, minHeight: 5, backgroundColor: tk.raised2, color: lk.acc),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (job.detail.isNotEmpty) job.detail,
                formatDuration(job.elapsed),
                if (left != null) '${formatDuration(left)} left',
                if (job.stalled) 'no progress for ${DateTime.now().difference(job.lastProgress).inSeconds}s',
                if (queued > 0) '$queued more waiting',
              ].join(' · '),
              style: ts(size: 12, c: job.stalled ? tk.warn : tk.sec, tab: true),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.close, color: tk.sec),
          tooltip: 'Stop',
          onPressed: () => Jobs.I.cancel(job),
        ),
      ]),
    );
  }
}

/// "Connected to PC" / "Offline", always in view.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Pc.I,
      builder: (context, _) {
        final (label, color, icon) = switch (Pc.I.state) {
          PcState.online => ('Connected to PC', tk.ok, Icons.wifi),
          PcState.connecting => ('Connecting…', tk.sec, Icons.wifi_find),
          PcState.offline => ('Offline', tk.warn, Icons.wifi_off),
          PcState.unpaired => ('Not paired', tk.faint, Icons.link_off),
        };
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(label, style: ts(size: 12, c: color, w: FontWeight.w600)),
            ]),
          ),
        );
      },
    );
  }
}

/// Finding the PC and pairing with the 6-digit code.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.first = false});
  final bool first;
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<FoundPc>? found;
  bool searching = false;
  FoundPc? chosen;
  final code = TextEditingController();
  final address = TextEditingController();
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (!Pc.I.paired) _search();
  }

  Future<void> _search() async {
    setState(() {
      searching = true;
      error = null;
    });
    final f = await Pc.I.discover();
    if (!mounted) return;
    setState(() {
      found = f;
      searching = false;
      if (f.length == 1) chosen = f.first;
    });
  }

  Future<void> _pair() async {
    FoundPc? target = chosen;
    if (target == null && address.text.trim().isNotEmpty) {
      final parts = address.text.trim().split(':');
      target = FoundPc(parts[0], parts[0], parts.length > 1 ? int.tryParse(parts[1]) ?? 47811 : 47811);
    }
    if (target == null) {
      setState(() => error = 'Pick your PC, or type its address.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final err = await Pc.I.pair(target.host, target.port, code.text.replaceAll(' ', ''), await Native.deviceName());
    if (!mounted) return;
    setState(() {
      busy = false;
      error = err;
    });
    if (err == null) {
      Sync.queue();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.first ? 'Welcome to Shiori' : 'Connect to PC', style: ts(size: 17, w: FontWeight.w700))),
      body: ListenableBuilder(
        listenable: Listenable.merge([Pc.I, Jobs.I]),
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          if (Pc.I.paired) ...[
            _card([
              Row(children: [
                Icon(Icons.computer, color: lk.acc),
                const SizedBox(width: 10),
                Expanded(child: Text(Pc.I.pcName, style: ts(size: 16, w: FontWeight.w700))),
                const ConnectionPill(),
              ]),
              const SizedBox(height: 6),
              Text('${Pc.I.host}:${Pc.I.port}', style: ts(c: tk.sec, mono: true, size: 12)),
              Text(Pc.I.lastSync > 0 ? 'Last synced ${dateText(Pc.I.lastSync)} at ${timeText(Pc.I.lastSync)}' : 'Not synced yet',
                  style: ts(c: tk.sec)),
              if (Pc.I.lastError != null) Text(Pc.I.lastError!, style: ts(c: tk.warn)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: Pc.I.online && !Jobs.I.isQueued(Sync.jobName) ? Sync.queue : null,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Pc.I.check();
                    if (mounted && !Pc.I.online) mToast('Can\'t reach ${Pc.I.pcName}. Is Shiori open there, on the same WiFi?');
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
                TextButton(
                  onPressed: () async {
                    final ok = await mConfirm(context, 'Forget ${Pc.I.pcName}?',
                        'The phone keeps its library copy and downloads. You\'ll need to pair again to connect.', 'Forget');
                    if (ok) Pc.I.forget();
                  },
                  child: Text('Forget this PC', style: ts(c: tk.danger)),
                ),
              ]),
            ]),
            const JobBar(),
          ] else ...[
            Text(
                'Shiori on the phone reads your library from the PC over your home WiFi, downloads titles to read anywhere, and sends your reading back.',
                style: ts(c: tk.sec)),
            const SizedBox(height: 14),
            _card([
              Text('1. On the PC', style: ts(w: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Open Shiori → Settings → Phone. Tick "Let the phone app connect", then press "Pair a phone".', style: ts(c: tk.sec)),
            ]),
            _card([
              Row(children: [
                Expanded(child: Text('2. Pick your PC', style: ts(w: FontWeight.w700))),
                if (searching)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  TextButton(onPressed: _search, child: const Text('Look again')),
              ]),
              if (found != null && found!.isEmpty && !searching)
                Text('No PC found on this WiFi. Check the phone connection is on in Shiori\'s settings on the PC, or type its address below.',
                    style: ts(c: tk.sec)),
              for (final f in found ?? <FoundPc>[])
                RadioListTile<FoundPc>(
                  value: f,
                  groupValue: chosen,
                  onChanged: (v) => setState(() => chosen = v),
                  title: Text(f.name, style: ts(w: FontWeight.w600)),
                  subtitle: Text(f.host, style: ts(c: tk.sec, size: 12)),
                  contentPadding: EdgeInsets.zero,
                ),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'Or the PC\'s address (e.g. 192.168.1.20)'),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() => chosen = null),
              ),
            ]),
            _card([
              Text('3. Type the code shown on the PC', style: ts(w: FontWeight.w700)),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                maxLength: 7,
                style: ts(size: 26, tab: true, w: FontWeight.w700),
                decoration: const InputDecoration(hintText: '123 456', counterText: ''),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: ts(c: tk.danger))),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: busy ? null : _pair, child: Text(busy ? 'Pairing…' : 'Pair')),
              ),
            ]),
            if (widget.first)
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
          ],
        ]),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tk.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: tk.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

Future<bool> mConfirm(BuildContext context, String title, String body, String yes) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: tk.panel,
      title: Text(title, style: ts(size: 17, w: FontWeight.w700)),
      content: Text(body, style: ts(c: tk.sec)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
      ],
    ),
  );
  return r == true;
}
