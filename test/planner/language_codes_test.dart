import 'package:flutter_test/flutter_test.dart';
import 'package:offline_engine/planner.dart';

void main() {
  group('iso6392', () {
    test('every ISO 639-1 code has its three-letter form', () {
      expect(iso6392('es-419'), 'spa');
      expect(iso6392('tl'), 'tgl');
      expect(iso6392('sw'), 'swa');
      expect(iso6392('yo'), 'yor');
      expect(iso6392('ka-GE'), 'kat');
      expect(iso6392('kw'), 'cor');
    });

    test('withdrawn codes still read', () {
      expect(iso6392('iw'), 'heb');
      expect(iso6392('in'), 'ind');
      expect(iso6392('ji'), 'yid');
      expect(iso6392('mo'), 'ron');
    });

    test('bibliographic codes come out terminologic', () {
      expect(iso6392('fre'), 'fra');
      expect(iso6392('mao'), 'mri');
      expect(iso6392('chi'), 'zho');
    });

    test('three-letter codes pass through; nothing is und', () {
      expect(iso6392('fil'), 'fil');
      expect(iso6392('xx'), 'und');
      expect(iso6392(null), 'und');
    });
  });

  group('sameLanguage', () {
    test('however it is written', () {
      expect(sameLanguage('he', 'heb'), isTrue);
      expect(sameLanguage('iw', 'he-IL'), isTrue);
      expect(sameLanguage('tl', 'tgl'), isTrue);
    });

    test('a language outside the old short list now matches', () {
      expect(languageMatch('sw', 'sw-KE'), greaterThan(0));
    });
  });

  group('Chinese is told apart by script', () {
    test('a script or a country that writes it', () {
      expect(languageMatch('zh-Hant', 'zh-TW'), 2);
      expect(languageMatch('zh-HK', 'zh-Hant'), 2);
      expect(languageMatch('zh-Hans', 'zh-CN'), 2);
      expect(languageMatch('zh-Hans', 'zh-Hant'), 1);
    });

    test('without a variant, any Chinese', () {
      expect(languageMatch('zh-Hant', 'zh'), 1);
      expect(languageMatch('zh', 'zh-Hans'), 1);
    });

    test('the label says the script when the code does not', () {
      expect(trackLanguage('zh', '繁體中文'), 'zh-Hant');
      expect(trackLanguage('zh', 'Chinese (Simplified)'), 'zh-Hans');
      expect(trackLanguage(null, '简体中文'), 'zh-Hans');
    });
  });

  test('Spanish of the Americas is the Latin American dub', () {
    expect(languageMatch('es-MX', 'es-419'), 2);
    expect(languageMatch('es-ES', 'es-419'), 1);
    expect(trackLanguage('es', 'Español (Latino)'), 'es-419');
  });
}
