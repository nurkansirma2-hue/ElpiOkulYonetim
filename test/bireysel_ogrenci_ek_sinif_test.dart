import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_import_tanimi.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Bireysel öğrenci importunda açıkça seçilen ek sınıflar', () {
    late Database db;
    final factory = WindowsMemoryFactory();
    const yil = '2026/2027';

    ImportKaynakSatiri row(
      String id,
      String no, {
      String sinif = '9-A',
      String ad = 'Ayşe',
      String cinsiyet = 'Kız',
      String veliAdi = '',
      String veliTelefonu = '',
    }) => ImportKaynakSatiri(id, 'Test satırı $id', {
      'okulNo': no,
      'ad': ad,
      'soyad': 'Yılmaz',
      'sinif': sinif,
      'cinsiyet': cinsiyet,
      'veliAdi': veliAdi,
      'veliTelefonu': veliTelefonu,
    });

    Future<ImportOnIzleme> preview(List<ImportKaynakSatiri> rows) =>
        BireyselImportService.ortakOgrenciTumSinifOnIzlemeHazirla(rows);

    Future<ImportOzet> save(
      ImportOnIzleme p, {
      Set<String> normal = const {},
      Set<String> ekSiniflar = const {},
    }) => BireyselImportService.ortakOgrencileriKaydet(
      p,
      normal,
      ekSiniflar: ekSiniflar,
    );

    Future<Set<int>> izinler({int profilId = 1, String egitimYili = yil}) =>
        BireyselImportService.ogrenciEkSinifIdleriniGetir(
          db,
          profilId,
          egitimYili,
        );

    setUpAll(() async {
      databaseFactory = factory;
      db = await LocalDatabase.instance.database;
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Test Öğretmen',
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
      for (final kod in ['9-A', '10-B']) {
        await db.insert('SinifSube', {
          'SinifKodu': kod,
          'SinifSeviyesi': kod == '9-A' ? 9 : 10,
          'EgitimOgretimYili': yil,
          'OlusturmaTarihi': 'test',
        });
      }
      await db.insert('Ders', {
        'DersAdi': 'Matematik',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersSaati', {'SiraNo': 1});
      for (var id = 1; id <= 2; id++) {
        await db.insert('DersProgrami', {
          'SinifSubeId': id,
          'DersId': 1,
          'DersSaatiId': 1,
          'Gun': id == 1 ? 'Pazartesi' : 'Salı',
          'OgretmenProfilId': 1,
          'EgitimOgretimYili': yil,
          'OlusturmaTarihi': 'test',
        });
      }
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      await db.delete('OgrenciSinifKayit');
      await db.delete('Ogrenci');
      await db.delete('UygulamaAyarlari');
      await db.delete('SinifSube', where: 'SinifSubeId > 2');
      await db.delete('OgretmenProfil', where: 'OgretmenProfilId > 1');
      await db.update('OgretmenProfil', {'Aktif': 1, 'EgitimOgretimYili': yil});
      await db.update('DersProgrami', {'Aktif': 1});
      await db.update('SinifSube', {'Aktif': 1});
    });

    tearDownAll(() async => factory.db?.close());

    test(
      'Ön izleme yazmaz; ek sınıf özetinde yalnız benzersiz geçerli öğrenciler sayılır',
      () async {
        final before = await db.query('SinifSube');
        final p = await OgrenciImportTanimi.tanim.hazirla([
          row('normal', '101'),
          row('ek1', '201', sinif: '11-C'),
          row('tekrar', '00201', sinif: '11-C'),
          row('ek2', '202', sinif: '11-C'),
          row('hata', '203', sinif: '11-C', ad: ''),
          row('numara-hatasi', 'x', sinif: '12-D'),
          row('telefon-hatasi', '301', sinif: '12-D', veliTelefonu: 'abc'),
        ]);
        expect(p.engeller, isEmpty);
        expect(
          p.kayitlar.singleWhere((r) => r.id == '101').aktarilabilir,
          isTrue,
        );
        expect(BireyselImportService.ogrenciEkSinifOzeti(p), {'11-C': 2});
        expect(
          p.kayitlar.where(
            (r) => r.degerler['sinif'] == '11-C' && r.aktarilabilir,
          ),
          isEmpty,
        );
        expect(await db.query('Ogrenci'), isEmpty);
        expect(await db.query('OgrenciSinifKayit'), isEmpty);
        expect(await db.query('UygulamaAyarlari'), isEmpty);
        expect(await db.query('SinifSube'), before);
      },
    );

    test('Varsayılan aktarım yalnız normal seçimi kaydeder', () async {
      final p = await preview([
        row('normal', '101'),
        row('ek', '201', sinif: '11-C'),
      ]);
      final sonuc = await OgrenciImportTanimi.tanim.aktar(p, {'101'});
      expect(sonuc.eklenen, 1);
      expect(sonuc.atlanan, 1);
      expect((await db.query('Ogrenci')).single['OkulNo'], '101');
      expect(await izinler(), isEmpty);
      expect((await db.query('SinifSube')).length, 2);
    });

    test('Yalnız seçilen ek sınıf kaydolur; ders programı oluşmaz', () async {
      final program = await db.query('DersProgrami');
      final p = await preview([
        row('normal', '101'),
        row('ek1', '201', sinif: '11-C'),
        row('ek2', '202', sinif: '11-C'),
        row('secilmeyen', '301', sinif: '12-D'),
      ]);
      final sonuc = await save(p, normal: {'101'}, ekSiniflar: {'11-C'});
      expect(sonuc.eklenen, 3);
      expect(sonuc.atlanan, 1);
      expect(
        (await db.query('Ogrenci', orderBy: 'OkulNo')).map((r) => r['OkulNo']),
        ['101', '201', '202'],
      );
      final ek = (await db.query(
        'SinifSube',
        where: "SinifKodu = '11-C'",
      )).single;
      expect(await izinler(), {ek['SinifSubeId']});
      expect(await db.query('SinifSube', where: "SinifKodu = '12-D'"), isEmpty);
      expect(await db.query('DersProgrami'), program);
      expect(
        (await db.query('OgrenciSinifKayit', where: 'Aktif = 1')).length,
        3,
      );
    });

    test('Dosyada yalnız ek sınıf varsa açık seçimle aktarılabilir', () async {
      final p = await preview([row('ek', '201', sinif: '11-C')]);
      expect(p.engeller, isEmpty);
      expect(p.kayitlar.where((r) => r.aktarilabilir), isEmpty);
      expect(BireyselImportService.ogrenciEkSinifOzeti(p), {'11-C': 1});
      expect((await save(p, ekSiniflar: {'11-C'})).eklenen, 1);
      expect((await db.query('Ogrenci')).single['OkulNo'], '201');
    });

    test(
      'Özette olmayan sınıf ve normal seçimle ek öğrenci aktarılamaz',
      () async {
        final p = await preview([
          row('normal', '101'),
          row('ek', '201', sinif: '11-C'),
        ]);
        await expectLater(
          save(p, normal: {'101'}, ekSiniflar: {'12-D'}),
          throwsStateError,
        );
        await expectLater(save(p, normal: {'201'}), throwsStateError);
        await expectLater(save(p), throwsStateError);
        expect(await db.query('Ogrenci'), isEmpty);
        expect(await db.query('UygulamaAyarlari'), isEmpty);
        expect((await db.query('SinifSube')).length, 2);
      },
    );

    test(
      'Normal ve ek sınıfta aynı okul numarası çelişirse ikisi de kaydedilmez',
      () async {
        final p = await preview([
          row('normal-celiski', '101'),
          row('ek-celiski', '00101', sinif: '11-C'),
          row('normal-gecerli', '102'),
          row('ek-gecerli', '201', sinif: '11-C'),
        ]);
        expect(
          p.kayitlar
              .where((r) => r.degerler['okulNo'] == '101')
              .every((r) => r.durum == ImportDurumu.hatali),
          isTrue,
        );
        expect(BireyselImportService.ogrenciEkSinifOzeti(p), {'11-C': 1});
        await expectLater(
          save(p, normal: {'101'}, ekSiniflar: {'11-C'}),
          throwsStateError,
        );
        expect(await db.query('Ogrenci'), isEmpty);
        final sonuc = await save(p, normal: {'102'}, ekSiniflar: {'11-C'});
        expect(sonuc.eklenen, 2);
        expect(
          (await db.query(
            'Ogrenci',
            orderBy: 'OkulNo',
          )).map((r) => r['OkulNo']),
          ['102', '201'],
        );
      },
    );

    test('Yerelde numarası belirsiz ek öğrenci özete alınmaz', () async {
      for (final no in ['201', '00201']) {
        await db.insert('Ogrenci', {
          'OkulNo': no,
          'Ad': 'Mevcut',
          'Soyad': 'Öğrenci',
          'OlusturmaTarihi': 'test',
        });
      }
      final p = await preview([
        row('belirsiz', '201', sinif: '11-C'),
        row('gecerli', '202', sinif: '11-C'),
      ]);
      expect(BireyselImportService.ogrenciEkSinifOzeti(p), {'11-C': 1});
      expect((await save(p, ekSiniflar: {'11-C'})).eklenen, 1);
      expect((await db.query('Ogrenci')).length, 3);
      expect((await db.query('OgrenciSinifKayit')).length, 1);
    });

    test(
      'Tekrar aktarım mükerrer oluşturmaz; ek sınıf izinleri birleştirilir',
      () async {
        final first = [row('ek', '201', sinif: '11-C')];
        await save(await preview(first), ekSiniflar: {'11-C'});
        final students = await db.query('Ogrenci');
        final memberships = await db.query('OgrenciSinifKayit');
        final classes = await db.query('SinifSube');
        final again = await save(await preview(first), ekSiniflar: {'11-C'});
        expect(again.eklenen, 0);
        expect(again.guncellenen, 0);
        expect(again.atlanan, 1);
        expect(await db.query('Ogrenci'), students);
        expect(await db.query('OgrenciSinifKayit'), memberships);
        expect(await db.query('SinifSube'), classes);
        await save(
          await preview([row('ikinci', '301', sinif: '12-D')]),
          ekSiniflar: {'12-D'},
        );
        expect((await izinler()).length, 2);
        final ayarlar = await db.query(
          'UygulamaAyarlari',
          where: 'Anahtar = ?',
          whereArgs: ['ogrenci_ek_sinif:1:$yil'],
        );
        expect(ayarlar, hasLength(1));
        expect(
          jsonDecode(ayarlar.single['Deger'] as String),
          unorderedEquals(await izinler()),
        );
      },
    );

    test(
      'Ek sınıf güncellemesi boş cinsiyet ve veli bilgilerini silmez',
      () async {
        final ogrenciId = await db.insert('Ogrenci', {
          'OkulNo': '201',
          'Ad': 'Eski',
          'Soyad': 'Yılmaz',
          'Cinsiyet': 'Kız',
          'VeliAdi': 'Test Veli',
          'VeliTelefonu': '+905551112233',
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciSinifKayit', {
          'OgrenciId': ogrenciId,
          'SinifSubeId': 1,
          'EgitimOgretimYili': '2025/2026',
          'Aktif': 1,
          'OlusturmaTarihi': 'test',
        });
        final p = await preview([
          row('ek', '201', sinif: '11-C', ad: 'Yeni', cinsiyet: ''),
        ]);
        final sonuc = await save(p, ekSiniflar: {'11-C'});
        expect(sonuc.guncellenen, 1);
        final ogrenci = (await db.query('Ogrenci')).single;
        expect(ogrenci['OgrenciId'], ogrenciId);
        expect(ogrenci['Ad'], 'Yeni');
        expect(ogrenci['Cinsiyet'], 'Kız');
        expect(ogrenci['VeliAdi'], 'Test Veli');
        expect(ogrenci['VeliTelefonu'], '+905551112233');
        expect(
          (await db.query(
            'OgrenciSinifKayit',
            where: 'EgitimOgretimYili = ?',
            whereArgs: ['2025/2026'],
          )).single['Aktif'],
          1,
        );
      },
    );

    test('Ek sınıf izinleri başka profil ve eğitim yılına sızmaz', () async {
      await save(
        await preview([row('ek', '201', sinif: '11-C')]),
        ekSiniflar: {'11-C'},
      );
      expect(await izinler(), isNotEmpty);
      expect(await izinler(profilId: 2), isEmpty);
      expect(await izinler(egitimYili: '2027/2028'), isEmpty);
      final ayarlar = await db.query('UygulamaAyarlari');
      expect(ayarlar.map((r) => r['Anahtar']), ['ogrenci_ek_sinif:1:$yil']);
    });

    test(
      'Profil, yıl veya mod değişirse ek sınıf seçimi kaydedilmez',
      () async {
        final p = await preview([row('ek', '201', sinif: '11-C')]);
        await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
        await expectLater(save(p, ekSiniflar: {'11-C'}), throwsStateError);
        await db.update('OgretmenProfil', {'EgitimOgretimYili': yil});
        SharedPreferences.setMockInitialValues({'calisma_modu': 'okul'});
        await expectLater(save(p, ekSiniflar: {'11-C'}), throwsStateError);
        SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
        await db.insert('OgretmenProfil', {
          'AdSoyad': 'Başka Öğretmen',
          'EgitimOgretimYili': yil,
          'OlusturmaTarihi': 'test',
        });
        await expectLater(save(p, ekSiniflar: {'11-C'}), throwsStateError);
        expect(await db.query('Ogrenci'), isEmpty);
        expect(await db.query('UygulamaAyarlari'), isEmpty);
        expect((await db.query('SinifSube')).length, 2);
      },
    );

    test(
      'Normal sınıf programdan çıkarsa normal ve ek sınıf birlikte geri alınır',
      () async {
        final p = await preview([
          row('normal', '101'),
          row('ek', '201', sinif: '11-C'),
        ]);
        await db.update('DersProgrami', {'Aktif': 0}, where: 'SinifSubeId = 1');
        await expectLater(
          save(p, normal: {'101'}, ekSiniflar: {'11-C'}),
          throwsStateError,
        );
        expect(await db.query('Ogrenci'), isEmpty);
        expect(await db.query('OgrenciSinifKayit'), isEmpty);
        expect(await db.query('UygulamaAyarlari'), isEmpty);
        expect((await db.query('SinifSube')).length, 2);
      },
    );

    test(
      'Öğrenci yazımında SQLite hatası olursa yeni sınıf ve izin de geri alınır',
      () async {
        final p = await preview([
          row('normal', '101'),
          row('ek', '201', sinif: '11-C'),
        ]);
        await db.execute(
          "CREATE TRIGGER ek_sinif_test_hata BEFORE INSERT ON Ogrenci WHEN NEW.OkulNo = '201' BEGIN SELECT RAISE(ABORT, 'ek sınıf test hatası'); END",
        );
        try {
          await expectLater(
            save(p, normal: {'101'}, ekSiniflar: {'11-C'}),
            throwsStateError,
          );
          expect(await db.query('Ogrenci'), isEmpty);
          expect(await db.query('OgrenciSinifKayit'), isEmpty);
          expect(await db.query('UygulamaAyarlari'), isEmpty);
          expect((await db.query('SinifSube')).length, 2);
        } finally {
          await db.execute('DROP TRIGGER ek_sinif_test_hata');
        }
      },
    );

    test(
      'Özel okuyucu farklı sayfalardaki sınıf bloklarını aynı ek sınıf özetine taşır',
      () async {
        final excel = Excel.createExcel();
        final ilk = excel['İlk'];
        ilk.appendRow(['9. Sınıf A Şubesi']);
        ilk.appendRow(['Okul No', 'Adı', 'Soyadı', 'Cinsiyeti']);
        ilk.appendRow([101, 'Ayşe', 'Yılmaz', 'Kız']);
        ilk.appendRow(['11. Sınıf C Şubesi']);
        ilk.appendRow(['Okul No', 'Adı', 'Soyadı', 'Cinsiyeti']);
        ilk.appendRow([201, 'Ali', 'Yılmaz', 'Erkek']);
        final ikinci = excel['İkinci'];
        ikinci.appendRow(['11. Sınıf C Şubesi']);
        ikinci.appendRow(['Okul No', 'Adı', 'Soyadı', 'Cinsiyeti']);
        ikinci.appendRow([202, 'Veli', 'Yılmaz', 'Erkek']);
        ikinci.appendRow(['12. Sınıf D Şubesi']);
        ikinci.appendRow(['Okul No', 'Adı', 'Soyadı', 'Cinsiyeti']);
        ikinci.appendRow([301, 'Ada', 'Yılmaz', 'Kız']);
        final p = await OgrenciImportTanimi.tanim.ozelOku!(
          ImportDosya('siniflar.xlsx', Uint8List.fromList(excel.encode()!)),
        );
        expect(p.engeller, isEmpty);
        expect(BireyselImportService.ogrenciEkSinifOzeti(p), {
          '11-C': 2,
          '12-D': 1,
        });
        expect(await db.query('Ogrenci'), isEmpty);
        expect(
          (await save(p, normal: {'101'}, ekSiniflar: {'11-C'})).eklenen,
          3,
        );
        expect(
          (await db.query(
            'Ogrenci',
            orderBy: 'OkulNo',
          )).map((r) => r['OkulNo']),
          ['101', '201', '202'],
        );
      },
    );

    test(
      'Öğrenci alanı boş alt bilgiler atlanır; kısmi öğrenci ve geçersiz numara hataları korunur',
      () async {
        final excel = Excel.createExcel();
        final sheet = excel['Liste'];
        sheet.appendRow(['9. Sınıf A Şubesi']);
        sheet.appendRow([
          'Okul No',
          'Adı',
          'Soyadı',
          'Cinsiyeti',
          'Diğer Bilgi',
        ]);
        sheet.appendRow([101, 'Ayşe', 'Yılmaz', 'Kız']);
        sheet.appendRow(['', '', '', '', 'İmza', 42.5]);
        sheet.appendRow(['', '', '', 'Toplam', 24.0]);
        sheet.appendRow([303]);
        sheet.appendRow(['', 'Eksik']);
        sheet.appendRow(['', '', 'Eksik']);
        sheet.appendRow(['12abc345x678']);
        sheet.appendRow(['11. Sınıf C Şubesi']);
        sheet.appendRow([
          'Okul No',
          'Adı',
          'Soyadı',
          'Cinsiyeti',
          'Diğer Bilgi',
        ]);
        sheet.appendRow([201, 'Ali', 'Yılmaz', 'Erkek']);
        final p = await OgrenciImportTanimi.tanim.ozelOku!(
          ImportDosya('alt-bilgiler.xlsx', Uint8List.fromList(excel.encode()!)),
        );
        expect(p.engeller, isEmpty);
        final hatali = p.kayitlar.where((r) => r.durum == ImportDurumu.hatali);
        expect(hatali, hasLength(4));
        expect(
          hatali.every(
            (r) => r.mesajlar.any(
              (m) => m.contains('Okul no, ad, soyad veya cinsiyet hatalı'),
            ),
          ),
          isTrue,
        );
        expect(p.kayitlar.where((r) => r.aktarilabilir).map((r) => r.id), [
          '101',
        ]);
        expect(BireyselImportService.ogrenciEkSinifOzeti(p), {'11-C': 1});
        expect(await db.query('Ogrenci'), isEmpty);
        final sonuc = await save(p, normal: {'101'}, ekSiniflar: {'11-C'});
        expect(sonuc.eklenen, 2);
        expect(sonuc.hatali, 4);
        expect(
          (await db.query(
            'Ogrenci',
            orderBy: 'OkulNo',
          )).map((r) => r['OkulNo']),
          ['101', '201'],
        );
      },
    );

    const xlsDosyasi = String.fromEnvironment('IMPORT_ALL_CLASSES_XLS');
    test(
      'Gerçek e-Okul XLS raporunda program dışındaki sınıflar sayılarıyla okunur',
      () async {
        final p = await BireyselImportService.ortakOgrenciOzelOku(
          ImportDosya('tum-siniflar.xls', File(xlsDosyasi).readAsBytesSync()),
        );
        expect(p.engeller, isEmpty);
        final ozet = BireyselImportService.ogrenciEkSinifOzeti(p);
        expect(ozet, hasLength(23));
        expect(ozet.keys, isNot(contains('9-A')));
        expect(ozet.keys, isNot(contains('10-B')));
        bool ozelSinif(String kod) =>
            importNormalize(kod).replaceAll(' ', '').contains('otistikhafif');
        expect(ozet.keys.where(ozelSinif), hasLength(2));
        final normalSiniflar = p.kayitlar
            .where((r) => r.aktarilabilir)
            .map((r) => r.degerler['sinif'])
            .toSet();
        expect(normalSiniflar, {'9-A', '10-B'});
        expect({...normalSiniflar, ...ozet.keys}, hasLength(25));
        expect(ozet.values.every((n) => n > 0), isTrue);
        expect(await db.query('Ogrenci'), isEmpty);
        expect(await db.query('UygulamaAyarlari'), isEmpty);
        final secilen = ozet.keys.firstWhere(ozelSinif);
        final sonuc = await save(p, ekSiniflar: {secilen});
        expect(sonuc.eklenen, ozet[secilen]);
        expect(
          (await db.query(
            'SinifSube',
            where: 'SinifSubeId > 2',
          )).single['SinifKodu'],
          secilen,
        );
        expect((await db.query('DersProgrami')).length, 2);
      },
      skip: xlsDosyasi.isEmpty,
    );
  }, skip: !Platform.isWindows);
}
