import 'dart:io';

import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../ui/widgets.dart';

/// Fingerprint, face or PIN, using the phone's own lock. Locks again after
/// you've been away from the app for the chosen time.
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.child});
  final Widget child;

  static bool get enabled => Settings.I.get<bool>('m.lock', false);
  /// Seconds away before it locks again (0 = straight away).
  static int get after => Settings.I.get<int>('m.lockAfter', 0);

  static Future<bool> check(String reason) async {
    if (!Platform.isAndroid) return true;
    try {
      return await LocalAuthPlatform.instance.authenticate(
        localizedReason: reason,
        authMessages: const [AndroidAuthMessages(signInTitle: 'Shiori')],
        options: const AuthenticationOptions(stickyAuth: true, useErrorDialogs: false),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> available() async {
    if (!Platform.isAndroid) return false;
    try {
      return await LocalAuthPlatform.instance.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool locked = AppLock.enabled;
  DateTime? leftAt;
  bool asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!AppLock.enabled || asking) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = leftAt == null ? 0 : DateTime.now().difference(leftAt!).inSeconds;
      leftAt = null;
      if (!locked && away >= AppLock.after) {
        setState(() => locked = true);
      }
      if (locked) _unlock();
    }
  }

  Future<void> _unlock() async {
    if (asking) return;
    asking = true;
    final ok = await AppLock.check('Unlock Shiori');
    asking = false;
    leftAt = null;
    if (ok && mounted) setState(() => locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Hidden, not removed, so the page you were on is still there after unlocking.
      Offstage(offstage: locked, child: TickerMode(enabled: !locked, child: widget.child)),
      if (locked)
        Positioned.fill(
          child: Material(
            color: tk.ground,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline, size: 48, color: lk.acc),
                const SizedBox(height: 14),
                Text('Shiori is locked', style: ts(size: 18, w: FontWeight.w700)),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Unlock')),
              ]),
            ),
          ),
        ),
    ]);
  }
}
