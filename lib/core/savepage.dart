import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'db.dart';
import 'log.dart';
import 'paths.dart';
import 'settings.dart';

/// One page (or half page) to save.
class PagePart {
  PagePart(this.page, this.bytes, this.ext, {this.half = 0});
  final int page; // 0-based
  final Uint8List bytes;
  final String ext; // from the archive entry, e.g. .jpg
  final int half; // 0 whole, 1 left half, 2 right half
}

String hashBytes(Uint8List b) => sha1.convert(b).toString();

String partHash(PagePart part) {
  final h = hashBytes(part.bytes);
  return part.half == 0 ? h : '$h#${part.half}';
}

String combinedHash(List<PagePart> parts) =>
    sha1.convert(parts.map(partHash).join('+').codeUnits).toString();

sealed class SaveResult {}

class Saved extends SaveResult {
  Saved(this.path);
  final String path;
}

class AlreadySaved extends SaveResult {
  AlreadySaved(this.at);
  final int at;
}

class SaveFailed extends SaveResult {
  SaveFailed(this.message);
  final String message;
}

/// Saves pages to the section's save folder. Never overwrites, and never
/// saves the same image twice, even after the saved files are moved away.
class PageSaver {
  static Future<SaveResult> save({
    required Title title,
    required List<PagePart> parts, // in the order they're shown, left to right
  }) async {
    final s = Settings.I;
    final ss = s.of(title.section);
    final hash = parts.length == 1 ? partHash(parts.first) : combinedHash(parts);
    final existing = Db.I.savedByHash(hash);
    if (existing != null) return AlreadySaved(existing.at);

    final folder = ss.saveFolder;
    if (folder.isEmpty) return SaveFailed('Choose a save folder for ${title.section.label} in Settings first.');
    final drive = p.rootPrefix(folder);
    if (drive.isNotEmpty && !Directory(drive).existsSync()) {
      return SaveFailed('The save folder\'s drive ($drive) isn\'t connected.');
    }
    try {
      await Directory(folder).create(recursive: true);
    } catch (e) {
      return SaveFailed('Couldn\'t create the save folder: $e');
    }

    final pagesSorted = parts.map((x) => x.page).toSet().toList()..sort();
    final pageLabel = pagesSorted.length == 1
        ? 'p${(pagesSorted.first + 1).toString().padLeft(3, '0')}'
        : 'p${(pagesSorted.first + 1).toString().padLeft(3, '0')}-${(pagesSorted.last + 1).toString().padLeft(3, '0')}';
    final halfLabel = parts.length == 1 && parts.first.half != 0 ? (parts.first.half == 1 ? ' (left half)' : ' (right half)') : '';
    var format = s.saveFormat;
    if (parts.length > 1 || parts.first.half != 0) {
      if (format == SaveFormat.original) format = SaveFormat.jpg; // combining needs re-encoding
    }
    final ext = switch (format) {
      SaveFormat.original => parts.first.ext.isEmpty ? '.jpg' : parts.first.ext.toLowerCase(),
      SaveFormat.jpg => '.jpg',
      SaveFormat.png => '.png',
    };
    final base = safeFileName('${title.displayTitle} - $pageLabel$halfLabel');
    final target = uniquePath(p.join(folder, '$base$ext'));

    try {
      Uint8List out;
      if (format == SaveFormat.original && parts.length == 1) {
        out = parts.first.bytes;
      } else {
        final quality = s.jpgQuality;
        final png = format == SaveFormat.png;
        final inputs = parts.map((x) => (x.bytes, x.half)).toList();
        out = await Isolate.run(() => _encode(inputs, png, quality));
      }
      await File(target).writeAsBytes(out, flush: true);
      Db.I.addSaved(title.id, pagesSorted.map((x) => x + 1).join('-'), hash, target, format.name);
      AppLog.I.info('Saved $target');
      return Saved(target);
    } catch (e) {
      AppLog.I.error('Couldn\'t save the page', e);
      return SaveFailed('Couldn\'t save the page: $e');
    }
  }

  static Uint8List _encode(List<(Uint8List, int)> inputs, bool png, int quality) {
    final images = <img.Image>[];
    for (final (bytes, half) in inputs) {
      var im = img.decodeImage(bytes);
      if (im == null) throw Exception('the image couldn\'t be read');
      if (half != 0) {
        final w = im.width ~/ 2;
        im = img.copyCrop(im, x: half == 1 ? 0 : im.width - w, y: 0, width: w, height: im.height);
      }
      images.add(im);
    }
    img.Image result;
    if (images.length == 1) {
      result = images.first;
    } else {
      final h = images.map((e) => e.height).reduce((a, b) => a > b ? a : b);
      final scaled = images.map((e) => e.height == h ? e : img.copyResize(e, height: h, interpolation: img.Interpolation.cubic)).toList();
      final w = scaled.fold<int>(0, (a, e) => a + e.width);
      result = img.Image(width: w, height: h, numChannels: 3);
      img.fill(result, color: img.ColorRgb8(255, 255, 255));
      var x = 0;
      for (final e in scaled) {
        img.compositeImage(result, e, dstX: x, dstY: 0);
        x += e.width;
      }
    }
    return png ? img.encodePng(result) : img.encodeJpg(result, quality: quality);
  }
}
