import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'log.dart';

/// One piece of background work with trustworthy progress
/// (STANDARDS.md "Progress you can trust").
class Job {
  Job(this.name, this.run, {this.canPause = false});

  final String name;
  final Future<String?> Function(Job job) run;
  final bool canPause;

  String detail = '';
  int done = 0;
  int? total;
  String unit = '';
  DateTime? started;
  DateTime lastProgress = DateTime.now();
  bool cancelled = false;
  bool paused = false;
  Completer<void>? _resume;

  void progress(int done, {int? total, String? detail}) {
    if (done != this.done) lastProgress = DateTime.now();
    this.done = done;
    if (total != null) this.total = total;
    if (detail != null) this.detail = detail;
    Jobs.I._changed();
  }

  void setDetail(String d) {
    detail = d;
    Jobs.I._changed();
  }

  /// Call between steps: waits while paused; returns false when stopped.
  Future<bool> checkpoint() async {
    if (paused) {
      _resume ??= Completer<void>();
      Jobs.I._changed();
      await _resume!.future;
      _resume = null;
      lastProgress = DateTime.now();
    }
    return !cancelled;
  }

  Duration get elapsed => started == null ? Duration.zero : DateTime.now().difference(started!);

  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (done / t).clamp(0.0, 0.99);
  }

  Duration? get timeLeft {
    final t = total;
    if (t == null || t <= 0 || done <= 0) return null;
    final secs = elapsed.inMilliseconds / done * (t - done) / 1000;
    return Duration(seconds: secs.round());
  }

  bool get stalled => !paused && DateTime.now().difference(lastProgress).inSeconds >= 20;
}

class Jobs extends ChangeNotifier {
  Jobs._() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (current != null) notifyListeners();
    });
  }
  static final Jobs I = Jobs._();

  late final Timer _ticker;
  final Queue<Job> queue = Queue<Job>();
  Job? current;
  String lastResult = '';
  bool lastFailed = false;
  int finishedInRun = 0;
  int queuedInRun = 0;

  void _changed() => notifyListeners();

  /// Adds work to the queue; it never refuses because something is running.
  void add(Job job) {
    queue.add(job);
    queuedInRun++;
    notifyListeners();
    if (current == null) _next();
  }

  bool isQueued(String name) =>
      current?.name == name || queue.any((j) => j.name == name);

  Future<void> _next() async {
    if (queue.isEmpty) {
      current = null;
      queuedInRun = 0;
      finishedInRun = 0;
      notifyListeners();
      return;
    }
    final job = queue.removeFirst();
    current = job;
    job.started = DateTime.now();
    job.lastProgress = DateTime.now();
    notifyListeners();
    AppLog.I.info('Started: ${job.name}');
    try {
      final result = await job.run(job);
      final took = _fmt(job.elapsed);
      lastResult = job.cancelled
          ? 'Stopped: ${job.name} · work done so far is kept'
          : 'Finished: ${result ?? job.name} · took $took';
      lastFailed = false;
      AppLog.I.info(lastResult);
    } catch (e, st) {
      lastResult = 'Failed: ${job.name}. $e';
      lastFailed = true;
      AppLog.I.error('${job.name} failed', e, st);
    }
    finishedInRun++;
    await _next();
  }

  /// Stops the current item and empties the queue. Finished work is kept.
  void stop() {
    queue.clear();
    final c = current;
    if (c != null) {
      c.cancelled = true;
      if (c.paused) {
        c.paused = false;
        c._resume?.complete();
      }
    }
    notifyListeners();
  }

  void togglePause() {
    final c = current;
    if (c == null || !c.canPause) return;
    c.paused = !c.paused;
    if (!c.paused) c._resume?.complete();
    notifyListeners();
  }

  static String _fmt(Duration d) => formatDuration(d);

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

String humanLeft(Duration d) {
  if (d.inSeconds < 60) return 'about ${d.inSeconds < 5 ? 5 : d.inSeconds} s left';
  if (d.inMinutes < 60) return 'about ${d.inMinutes} min left';
  return 'about ${d.inHours} h ${d.inMinutes % 60} min left';
}

String humanSize(num bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String humanHours(int seconds) {
  if (seconds < 60) return '$seconds s';
  if (seconds < 3600) return '${seconds ~/ 60} min';
  final h = seconds / 3600;
  return h < 10 ? '${h.toStringAsFixed(1)} h' : '${h.round()} h';
}
