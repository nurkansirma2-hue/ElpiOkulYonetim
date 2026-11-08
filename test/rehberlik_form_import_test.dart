import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/models/ogrenci_bilgi_formu.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_form_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final importer = RehberlikFormImport(
    okulNo: '00123',
    adSoyad: 'Örnek Öğrenci',
  );
  ImportKaynakSatiri row(String field, String value) {
    final i = ogrenciBilgiFormuSorulari.indexOf(field);
    return ImportKaynakSatiri('$i', field, {'alan': field, 'deger': value});
  }

  List<ImportKaynakSatiri> source({
    String name = 'Örnek Öğrenci',
    String no = '123',
  }) => [
    row('Adınız Soyadınız', name),
    row('Okul numaranız', no),
    row('Anne mesleği', 'Öğretmen'),
    row('Baba mesleği', ''),
  ];
  test('Başka öğrenciye ait veya eksik kimlik tüm seçimi engeller', () async {
    for (final rows in [
      source(name: 'Başka Öğrenci'),
      source(no: '124'),
      source()..removeAt(0),
    ]) {
      final p = await importer.hazirla(rows);
      expect(p.engeller, isNotEmpty);
      final session = ImportOturumu(p);
      session.topluSec(p.kayitlar, true);
      expect(session.secimler, isEmpty);
    }
  });
  test(
    'Doğru kimlikte boş cevap aktarılamaz ve OCR otomatik seçilmez',
    () async {
      final preview = await importer.hazirla(source());
      expect(preview.engeller, isEmpty);
      final session = ImportOturumu(preview);
      session.topluSec(
        preview.kayitlar.where((r) => r.durum == ImportDurumu.uygun),
        true,
      );
      expect(session.secimler, isEmpty);
      session.topluSec(preview.kayitlar, true);
      expect(session.secimler, hasLength(3));
      expect(preview.kayitlar.last.aktarilabilir, false);
    },
  );
  test(
    'Ön izleme düzeltmesi kimliği yeniden doğrular, alan adını değiştiremez',
    () async {
      final bad = await importer.hazirla(source(no: '999'));
      final def = importer.tanim((_) async => bad);
      final fixed = await def.duzenlemeHazirla!(bad, source());
      expect(fixed.engeller, isEmpty);
      final tampered = await importer.hazirla([
        ...source(),
        ImportKaynakSatiri(
          '${ogrenciBilgiFormuSorulari.indexOf('Veli mesleği')}',
          '',
          {'alan': 'Adınız Soyadınız', 'deger': 'Esnaf'},
        ),
      ]);
      expect(tampered.kayitlar.last.degerler['alan'], 'Veli mesleği');
      await expectLater(
        importer.hazirla([
          row('Adınız Soyadınız', 'A'),
          row('Adınız Soyadınız', 'B'),
        ]),
        throwsFormatException,
      );
    },
  );
  test('Basılı etiket cevap olarak kaydedilmez, cevap metni korunur', () {
    expect(
      RehberlikFormImport.temizle('Veli adı soyadı: Örnek Veli', [
        'Veli adı soyadı',
      ]),
      'Örnek Veli',
    );
    expect(
      RehberlikFormImport.temizle(
        'Sürekli bir hastalığınız var mı? Varsa nedir?\nYok',
        ['Sürekli bir hastalığınız var mı Varsa nedir'],
      ),
      'Yok',
    );
    expect(RehberlikFormImport.temizle('Öz', []), 'Öz');
    expect(RehberlikFormImport.temizle('Adresiniz:', ['Adresiniz']), '');
  });
  test(
    'Native OCR çıktısı tüm alanları kontrollü ön izlemeye dönüştürür',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(RehberlikFormImport.kanal, (
        call,
      ) async {
        expect(call.method, 'oku');
        final args = call.arguments as Map;
        expect(args['bytes'], [1, 2, 3]);
        expect(args['alanlar'], isNotEmpty);
        return {
          '${ogrenciBilgiFormuSorulari.indexOf('Adınız Soyadınız')}':
              'Örnek Öğrenci',
          '${ogrenciBilgiFormuSorulari.indexOf('Okul numaranız')}': '123',
          '${ogrenciBilgiFormuSorulari.indexOf('Veli mesleği')}':
              'Mesleği: Esnaf',
        };
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(RehberlikFormImport.kanal, null),
      );
      final preview = await importer.resimOku(
        ImportDosya('form.png', Uint8List.fromList([1, 2, 3])),
        [0, 0, 1, 0, 1, 1, 0, 1],
      );
      expect(preview.engeller, isEmpty);
      expect(preview.kayitlar, hasLength(ogrenciBilgiFormuSorulari.length));
      expect(
        preview.kayitlar
            .singleWhere((r) => r.degerler['alan'] == 'Veli mesleği')
            .degerler['deger'],
        'Esnaf',
      );
      expect(preview.kayitlar.where((r) => r.aktarilabilir), hasLength(3));
    },
  );
}
