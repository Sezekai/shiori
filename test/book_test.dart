import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shiori/core/archives.dart';

void main() {
  test('zip book opens and reads pages; info is read', () async {
    final dir = Directory.systemTemp.createTempSync('shiori');
    final arc = Archive();
    for (var i = 1; i <= 3; i++) {
      final im = img.Image(width: 600, height: 850);
      img.fill(im, color: img.ColorRgb8(20 * i, 90, 160));
      arc.addFile(ArchiveFile.bytes('p$i.jpg', img.encodeJpg(im)));
    }
    arc.addFile(ArchiveFile.bytes('__MACOSX/p1.jpg', [1, 2, 3]));
    final path = '${dir.path}/a.cbz';
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(arc));
    final info = inspectFile(path, null);
    expect(info.pages, 3);
    expect(info.kind, 'zip');
    final sw = Stopwatch()..start();
    final book = await Book.open(path, cacheDir: dir.path);
    expect(book.length, 3);
    final b = await book.page(0);
    expect(imageSize(b), (600, 850));
    final dec = img.decodeImage(b);
    expect(dec!.width, 600);
    print('took ${sw.elapsedMilliseconds} ms');
    book.close();
  });
}
