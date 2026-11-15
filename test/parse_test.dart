import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/core/parse.dart';

void main() {
  group('manga names', () {
    test('circle, artist, gallery id', () {
      final r = parseManga(
          '[Grand Plié. (Erohamuchan)] Chikubi Kando Chousa, Hajimemasu[English][Digital](528009).cbz');
      expect(r.circle, 'Grand Plié.');
      expect(r.artist, 'Erohamuchan');
      expect(r.galleryId, '528009');
      expect(r.language, 'English');
      expect(r.title, 'Chikubi Kando Chousa, Hajimemasu');
    });

    test('magazine source and chapter', () {
      final r = parseManga(
          '[Hazakura Satsuki] Stranded on a Desert Island Ch.3 (Dascomi Vol.17).cbz');
      expect(r.artist, 'Hazakura Satsuki');
      expect(r.source, 'Dascomi Vol.17');
      expect(r.chapter, 3);
      expect(r.seriesBase, 'Stranded on a Desert Island');
    });

    test('gallery id in dashes and underscores', () {
      final r = parseManga('[Aoin] 9s2b - [_246692_].cbz');
      expect(r.galleryId, '246692');
      expect(r.title, '9s2b');
      final r2 = parseManga('[Ra] Moe Syoujyo Ryouiki - [.54245.].cbz');
      expect(r2.galleryId, '54245');
    });

    test('event prefix and parody', () {
      final r = parseManga(
          '(C90) [mon-petit (Mon-petit)] 1-kai 2-man de Dou How about 20,000 yen for one time (Kuromukuro) [English] [Gagak_Ireng].cbz');
      expect(r.event, 'C90');
      expect(r.parody, 'Kuromukuro');
      expect(r.artist, 'Mon-petit');
      expect(r.extras, contains('Gagak_Ireng'));
    });

    test('two titles with underscore separator', () {
      final r = parseManga(
          '[Zonda] Fellatio Kenkyuubu Ch. 2 _ Blowjob Research Club Ch. 2 - [_370619_].cbz');
      expect(r.title, 'Blowjob Research Club Ch. 2');
      expect(r.altTitle, 'Fellatio Kenkyuubu Ch. 2');
      expect(r.chapter, 2);
      expect(r.seriesBase, 'Blowjob Research Club');
    });

    test('romaji and english run together', () {
      final r = parseManga(
          '[Toilet Komoru] Mujintou no Ono-san Ono-san on an uninhabited island [English] [Gagak_Ireng].cbz');
      expect(r.title.toLowerCase(), contains('island'));
      expect(r.altTitle, isNotNull);
      expect(r.altTitle!.toLowerCase(), startsWith('mujintou'));
    });

    test('plain english title is left alone', () {
      final r = parseManga('[Azumi Kyohei] Hungry Girlfriend (Comic Bavel 2025-01).cbz');
      expect(r.title, 'Hungry Girlfriend');
      expect(r.altTitle, isNull);
      expect(r.source, 'Comic Bavel 2025-01');
    });

    test('trailing number is a chapter', () {
      final r = parseManga('[8cm (Hassen)] Girlfriend in Too Deep 2.cbz');
      expect(r.chapter, 2);
      expect(r.seriesBase, 'Girlfriend in Too Deep');
      final first = parseManga('[8cm (Hassen)] Girlfriend in Too Deep.cbz');
      expect(first.seriesKey, r.seriesKey);
    });

    test('zenpen is part 1', () {
      final r = parseManga('[Eba] Kooni no Henpou Zenpen (decensored).cbz');
      expect(r.chapter, 1);
      expect(r.seriesBase, 'Kooni no Henpou');
    });

    test('chinese part is moved out', () {
      final r = parseManga(
          '[Arimura Daikon] Papa No Koto Suki Ni Naru Toka Arienai - 我怎麼可能會喜歡上爸爸 (Comic Anthurium 2024-01) [Chinese] [Digital](487732).cbz');
      expect(r.title, 'Papa No Koto Suki Ni Naru Toka Arienai');
      expect(r.language, 'Chinese');
    });
  });

  test('double space separates titles', () {
    final r = parseManga('[Yd] Murasaki No Yume  Purple Dream - [485637].cbz');
    expect(r.title, 'Purple Dream');
    expect(r.altTitle, 'Murasaki No Yume');
  });

  test('curly tags, stray brackets, underscores as question marks', () {
    final r = parseManga(
        '[Galactic Syatem Pride (B-Ginga)] Saimin Yami Beit - Shady Hypno Part Time Job (Blue Archive) [English] {Doujins.Com}(572340)).cbz');
    expect(r.galleryId, '572340');
    expect(r.parody, 'Blue Archive');
    expect(r.artist, 'B-Ginga');
    final q = parseManga("[35 Machi] What's Wrong With Making Love With A Slutty Virgin Demon Lord_ (Isekairakuten Vol.27).cbz");
    expect(q.title, endsWith('Lord?'));
  });

  test('malformed leading artist', () {
    final r = parseManga('(Anzayuu)] Sweet Life in Another World 3.cbz');
    expect(r.artist, 'Anzayuu');
    expect(r.chapter, 3);
  });

  group('comic names', () {
    test('underscored issue with year', () {
      final r = parseComic(
          'Ultimate_Spider-Man_068_(2005)_(digital)_(Son_of_Ultron-Empire).cbr');
      expect(r.seriesBase, 'Ultimate Spider-Man');
      expect(r.chapter, 68);
      expect(r.year, 2005);
    });
    test('reading order prefix', () {
      final r = parseComic('042 - Spider-Woman 009.cbr');
      expect(r.order, 42);
      expect(r.seriesBase, 'Spider-Woman');
      expect(r.chapter, 9);
    });
    test('volume and issue', () {
      final r = parseComic('The Amazing Spider-Man v1 - 217.cbz');
      expect(r.volume, '1');
      expect(r.chapter, 217);
      expect(r.seriesBase, 'The Amazing Spider-Man');
    });
    test('series key groups issues', () {
      expect(parseComic('Invincible 010 (2004) (Digital) (Fawkes-Empire).cbr').seriesKey,
          parseComic('Invincible 011 (2004) (Digital).cbr').seriesKey);
    });
  });

  test('natural order', () {
    final l = ['10. X', '2. X', '1. X', '042 - a', '043 - a', '041 - b'];
    l.sort(naturalCompare);
    expect(l, ['1. X', '2. X', '10. X', '041 - b', '042 - a', '043 - a']);
  });
}
