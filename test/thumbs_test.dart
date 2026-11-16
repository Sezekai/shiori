import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shiori/core/db.dart';
import 'package:shiori/core/library.dart';
import 'package:shiori/core/paths.dart';
import 'package:shiori/core/settings.dart';

void main() {
  test('covers are made and the queue finishes', () async {
    final dir = Directory.systemTemp.createTempSync('shiori');
    AppPaths.I = AppPaths.resolve();
    AppPaths.I.cache = '${dir.path}/root/Cache';
    AppPaths.I.ensureCache();
    Db.I = Db.open('${dir.path}/lib.db');
    final books = Directory('${dir.path}/books')..createSync();
    for (var b = 1; b <= 3; b++) {
      final arc = Archive();
      for (var i = 1; i <= 2; i++) {
        final im = img.Image(width: 300, height: 400);
        img.fill(im, color: img.ColorRgb8(20 * b, 90, 160));
        arc.addFile(ArchiveFile.bytes('p$i.jpg', img.encodeJpg(im)));
      }
      File('${books.path}/[A] Story Ch. $b.cbz').writeAsBytesSync(ZipEncoder().encodeBytes(arc));
    }
    Settings.I.of(Section.manga).folders = [books.path];
    Library.I.load();
    await Thumbs.I.loadIndex();
    Thumbs.I.encoder = (Uint8List b) async => Uint8List.fromList(img.encodeJpg(img.decodeImage(b)!));
    final titles = <Title>[];
    // Scan directly without the job queue.
    Library.I.scan(Section.manga);
    for (var i = 0; i < 100 && Library.I.titles(Section.manga).length < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    titles.addAll(Library.I.titles(Section.manga));
    expect(titles.length, 3);
    for (final t in titles) {
      final f = await Thumbs.I.get(t).timeout(const Duration(seconds: 10));
      expect(f, isNotNull);
    }
  });
}
