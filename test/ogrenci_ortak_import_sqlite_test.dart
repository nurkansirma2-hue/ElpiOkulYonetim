import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/ortak_import_service.dart';
import 'package:elpi_okul_yonetim/screens/admin_import_screen.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/services/ders_programi_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/yillik_plan_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/fotograf_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_yillik_plan_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_ders_programi_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yillik_plan_import_screen.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Gerçek SQLite üzerinde bireysel import', () {
    late Database db;
    final factory = WindowsMemoryFactory();
    const definition = OgrenciImportTanimi.tanim;
    ImportKaynakSatiri row(
      String no, {
      String name = 'Ayşe',
      String classroom = '9-A',
      String gender = 'Kız',
    }) => ImportKaynakSatiri(no, 'Satır $no', {
      'okulNo': no,
      'ad': name,
      'soyad': 'Yılmaz',
      'sinif': classroom,
      'cinsiyet': gender,
    });
    setUpAll(() async {
      FilePicker.platform = MemoryFilePicker('');
      databaseFactory = factory;
      db = await LocalDatabase.instance.database;
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Öğretmen',
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      for (final name in ['9-A', '10-B']) {
        await db.insert('SinifSube', {
          'SinifKodu': name,
          'SinifSeviyesi': name == '9-A' ? 9 : 10,
          'EgitimOgretimYili': '2026/2027',
          'OlusturmaTarihi': 'test',
        });
      }
      await db.insert('Ders', {
        'DersAdi': 'Matematik',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersSaati', {'SiraNo': 1});
      for (var i = 1; i <= 2; i++) {
        await db.insert('DersProgrami', {
          'SinifSubeId': i,
          'DersId': 1,
          'DersSaatiId': 1,
          'Gun': i == 1 ? 'Pazartesi' : 'Salı',
          'Baslangic': '08:00',
          'Bitis': '08:40',
          'OgretmenProfilId': 1,
          'EgitimOgretimYili': '2026/2027',
          'OlusturmaTarihi': 'test',
        });
      }
    });
    setUp(() async {
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      await db.delete('OgrenciSinifKayit');
      await db.delete('Ogrenci');
      await db.delete('UygulamaAyarlari');
      await db.delete('YillikPlanDetay');
      await db.delete('YillikPlan');
      await db.delete('CalismaTakvimiDetay');
      await db.delete('CalismaTakvimi');
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2026/2027'});
      await db.update('DersProgrami', {'Aktif': 1});
    });
    tearDownAll(() async {
      await factory.db?.close();
    });

    test(
      'Yalnız seçilen kayıt yazılır; dosyada olmayan öğrenci korunur',
      () async {
        await db.insert('Ogrenci', {
          'OkulNo': '999',
          'Ad': 'Mevcut',
          'Soyad': 'Öğrenci',
          'OlusturmaTarihi': 'test',
        });
        final preview = await definition.hazirla([
          row('101'),
          row('102'),
          row('x'),
        ]);
        final result = await definition.aktar(preview, {'101'});
        expect(result.eklenen, 1);
        expect(result.atlanan, 1);
        expect(result.hatali, 1);
        expect(
          (await db.query(
            'Ogrenci',
            orderBy: 'OkulNo',
          )).map((r) => r['OkulNo']),
          ['101', '999'],
        );
        expect((await db.query('OgrenciSinifKayit')).length, 1);
      },
    );
    test('Tekrar aktarım mükerrer oluşturmaz, değişmeyeni atlar', () async {
      var preview = await definition.hazirla([row('101')]);
      await definition.aktar(preview, {'101'});
      final before = await db.query('Ogrenci');
      preview = await definition.hazirla([row('101')]);
      final result = await definition.aktar(preview, {'101'});
      expect(result.eklenen, 0);
      expect(result.guncellenen, 0);
      expect(result.atlanan, 1);
      expect(await db.query('Ogrenci'), before);
    });
    test(
      'Yerelde aynı sayıya karşılık gelen iki numara ön izlemede engellenir',
      () async {
        for (final no in ['101', '00101']) {
          await db.insert('Ogrenci', {
            'OkulNo': no,
            'Ad': 'Ayşe',
            'Soyad': 'Yılmaz',
            'OlusturmaTarihi': 'test',
          });
        }
        final preview = await definition.hazirla([row('101')]);
        expect(preview.kayitlar.single.durum, ImportDurumu.hatali);
        await expectLater(definition.aktar(preview, {'101'}), throwsStateError);
        expect((await db.query('Ogrenci')).length, 2);
      },
    );
    test(
      'Güncelleme sınıf üyeliğini değiştirir; boş opsiyonel alanı silmez',
      () async {
        await definition.aktar(await definition.hazirla([row('101')]), {'101'});
        final result = await definition.aktar(
          await definition.hazirla([
            row('101', name: 'Ayşe Nur', classroom: '10-B', gender: ''),
          ]),
          {'101'},
        );
        expect(result.guncellenen, 1);
        final student = (await db.query('Ogrenci')).single;
        expect(student['Ad'], 'Ayşe Nur');
        expect(student['Cinsiyet'], 'Kız');
        final active = await db.query('OgrenciSinifKayit', where: 'Aktif = 1');
        expect(active.single['SinifSubeId'], 2);
        expect(
          (await db.query('OgrenciSinifKayit', where: 'Aktif = 0')).length,
          1,
        );
      },
    );
    test('Yıl ve çalışma modu değişince eski ön izleme kaydedilemez', () async {
      final preview = await definition.hazirla([row('101')]);
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
      await expectLater(definition.aktar(preview, {'101'}), throwsStateError);
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2026/2027'});
      SharedPreferences.setMockInitialValues({'calisma_modu': 'okul'});
      await expectLater(definition.aktar(preview, {'101'}), throwsStateError);
      expect(await db.query('Ogrenci'), isEmpty);
    });
    test('Ders programı kapsamı değişince aktarım durur', () async {
      final preview = await definition.hazirla([row('101')]);
      await db.update('DersProgrami', {'Aktif': 0});
      await expectLater(definition.aktar(preview, {'101'}), throwsStateError);
      expect(await db.query('Ogrenci'), isEmpty);
    });
    test(
      'İkinci kayıtta SQLite hatası olursa ilk kayıt ve üyelik de geri alınır',
      () async {
        final preview = await definition.hazirla([row('101'), row('202')]);
        await db.execute(
          "CREATE TRIGGER test_import_failure BEFORE INSERT ON Ogrenci WHEN NEW.OkulNo = '202' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
        );
        try {
          await expectLater(
            definition.aktar(preview, {'101', '202'}),
            throwsStateError,
          );
          expect(await db.query('Ogrenci'), isEmpty);
          expect(await db.query('OgrenciSinifKayit'), isEmpty);
        } finally {
          await db.execute('DROP TRIGGER test_import_failure');
        }
      },
    );
    test(
      'Ön izlemede olmayan ve hatalı kayıt kimlikleri kaydedilemez',
      () async {
        final preview = await definition.hazirla([row('101'), row('x')]);
        await expectLater(definition.aktar(preview, {}), throwsStateError);
        await expectLater(definition.aktar(preview, {'999'}), throwsStateError);
        await expectLater(
          definition.aktar(preview, {'hata:x'}),
          throwsStateError,
        );
        expect(await db.query('Ogrenci'), isEmpty);
      },
    );
    test(
      'Profiller mevcut SQLite ayarlarında saklanır ve geri okunur',
      () async {
        final table = ImportTablosu('Liste', [
          ['Numara', 'Ad', 'Soyad', 'Sınıf'],
        ]);
        final mapping = table.otomatikEsle(definition, 0);
        await OrtakImportService.profilKaydet(
          definition,
          table,
          0,
          mapping,
          'Benim listem',
        );
        await OrtakImportService.profilKaydet(
          definition,
          table,
          0,
          mapping,
          'Benim listem',
        );
        final profiles = await OrtakImportService.profilleriGetir(definition);
        expect(profiles.length, 1);
        expect(profiles.single.ad, 'Benim listem');
        expect(
          profiles.single.uygula(definition, [
            'Sınıf',
            'Ad',
            'Numara',
            'Soyad',
          ]),
          {'okulNo': 2, 'ad': 1, 'soyad': 3, 'sinif': 0},
        );
        final stored =
            (await db.query('UygulamaAyarlari')).single['Deger'] as String;
        expect(stored.contains('Ayşe'), isFalse);
      },
    );
    test(
      'Mevcut e-Okul sınıf başlığı okuyucusu ve seçili aktarım korunur',
      () async {
        final excel = Excel.createExcel();
        excel['Liste'].appendRow(['9. Sınıf A Şubesi']);
        excel['Liste'].appendRow(['Okul No', 'Adı', 'Soyadı', 'Cinsiyeti']);
        excel['Liste'].appendRow([101, 'Ayşe', 'Yılmaz', 'Kız']);
        excel['Liste'].appendRow([102, 'Ali', 'Yılmaz', 'Erkek']);
        final preview = await definition.ozelOku!(
          ImportDosya('liste.xlsx', Uint8List.fromList(excel.encode()!)),
        );
        expect(preview.engeller, isEmpty);
        expect(preview.kayitlar.length, 2);
        expect((await definition.aktar(preview, {'102'})).eklenen, 1);
        expect((await db.query('Ogrenci')).single['OkulNo'], '102');
      },
    );
    test('Eski eğitim yılının sınıf üyeliği korunur', () async {
      final result = await definition.aktar(
        await definition.hazirla([row('101')]),
        {'101'},
      );
      expect(result.eklenen, 1);
      final id = (await db.query('Ogrenci')).single['OgrenciId'];
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2025/2026',
        'Aktif': 1,
        'OlusturmaTarihi': 'test',
      });
      await definition.aktar(
        await definition.hazirla([row('101', classroom: '10-B')]),
        {'101'},
      );
      expect(
        (await db.query(
          'OgrenciSinifKayit',
          where: 'EgitimOgretimYili = ?',
          whereArgs: ['2025/2026'],
        )).single['Aktif'],
        1,
      );
    });

    test(
      'Birden fazla sınıf bloğunda ortak bilgiler kendi öğrencilerine uygulanır',
      () async {
        final excel = Excel.createExcel();
        final sheet = excel['Liste'];
        sheet.appendRow(['9. Sınıf A Şubesi (Bilişim)']);
        sheet.appendRow(['Sınıf Öğretmeni: Birinci Öğretmen']);
        sheet.appendRow(['Okul No', 'Adı', 'Soyadı']);
        sheet.appendRow([101, 'Ayşe', 'Yılmaz']);
        sheet.appendRow([102, 'Ali', 'Yılmaz']);
        sheet.appendRow(['10. Sınıf B Şubesi (Elektrik)']);
        sheet.appendRow(['Sınıf Öğretmeni:', 'İkinci Öğretmen']);
        sheet.appendRow(['Okul No', 'Adı', 'Soyadı']);
        sheet.appendRow([201, 'Veli', 'Yılmaz']);
        final file = ImportDosya(
          'blok.xlsx',
          Uint8List.fromList(excel.encode()!),
        );
        final tables = OrtakImportService.tablolariOku(file);
        expect(
          definition.ozelDuzeniTani!(tables.map((t) => t.satirlar).toList()),
          isTrue,
        );
        final preview = await definition.ozelOku!(file);
        expect(preview.engeller, isEmpty);
        expect(preview.kayitlar.length, 3);
        for (final record in preview.kayitlar) {
          final first = record.id != '201';
          expect(record.degerler['sinif'], first ? '9-A' : '10-B');
          expect(record.degerler['alan'], first ? 'Bilişim' : 'Elektrik');
          expect(
            record.degerler['rehberOgretmen'],
            first ? 'Birinci Öğretmen' : 'İkinci Öğretmen',
          );
        }
        expect((await definition.aktar(preview, {'102', '201'})).eklenen, 2);
        expect((await db.query('Ogrenci')).length, 2);
      },
    );

    test(
      'Tanınmayan bölüm uygun öğrencilerin seçimini ve aktarımını kilitlemez',
      () async {
        final excel = Excel.createExcel();
        excel['Liste'].appendRow(['9. Sınıf A Şubesi']);
        excel['Liste'].appendRow(['Okul No', 'Adı', 'Soyadı']);
        excel['Liste'].appendRow([101, 'Ayşe', 'Yılmaz']);
        excel['İkinci'].appendRow(['10. Sınıf B Şubesi']);
        excel['İkinci'].appendRow(['Okul No', 'Adıv', 'Soyadım']);
        excel['İkinci'].appendRow([201, 'Ali', 'Yılmaz']);
        final preview = await definition.ozelOku!(
          ImportDosya('liste.xlsx', Uint8List.fromList(excel.encode()!)),
        );
        expect(preview.engeller, isEmpty);
        expect(
          preview.kayitlar.where((r) => r.durum == ImportDurumu.hatali),
          isNotEmpty,
        );
        expect((await definition.aktar(preview, {'101'})).eklenen, 1);
        expect((await db.query('Ogrenci')).single['OkulNo'], '101');
      },
    );

    test(
      'Çelişkili numara aktarılmaz; bağımsız uygun öğrenci aktarılır',
      () async {
        final excel = Excel.createExcel();
        final sheet = excel['Liste'];
        sheet.appendRow(['9. Sınıf A Şubesi']);
        sheet.appendRow(['Okul No', 'Adı', 'Soyadı']);
        sheet.appendRow([101, 'Ayşe', 'Yılmaz']);
        sheet.appendRow([102, 'Veli', 'Yılmaz']);
        sheet.appendRow(['10. Sınıf B Şubesi']);
        sheet.appendRow(['Okul No', 'Adı', 'Soyadı']);
        sheet.appendRow([101, 'Ali', 'Yılmaz']);
        final preview = await definition.ozelOku!(
          ImportDosya('liste.xlsx', Uint8List.fromList(excel.encode()!)),
        );
        expect(preview.engeller, isEmpty);
        expect(
          preview.kayitlar.firstWhere((r) => r.id == '101').durum,
          ImportDurumu.hatali,
        );
        await expectLater(definition.aktar(preview, {'101'}), throwsStateError);
        expect((await definition.aktar(preview, {'102'})).eklenen, 1);
        expect((await db.query('Ogrenci')).single['OkulNo'], '102');
      },
    );

    test(
      'Özel başlıklar elle eşleştirilirken tüm sayfalar ve sınıf blokları korunur',
      () async {
        final tables = [
          ImportTablosu('Birinci', [
            ['9. Sınıf A Şubesi'],
            ['Okul No', 'Adı', 'Soyadı'],
            ['101', 'Ayşe', 'Yılmaz'],
          ]),
          ImportTablosu('İkinci', [
            ['10. Sınıf B Şubesi'],
            ['Numaram', 'Adıv', 'Soyadım'],
            ['201', 'Ali', 'Yılmaz'],
          ]),
        ];
        final sources = OrtakImportService.kaynaklariOku(
          definition,
          tables,
          tablo: 1,
          baslik: 1,
          esleme: {'okulNo': 0, 'ad': 1, 'soyad': 2},
        );
        final preview = await definition.hazirla(sources);
        expect(preview.engeller, isEmpty);
        expect(preview.kayitlar.map((r) => r.degerler['sinif']).toSet(), {
          '9-A',
          '10-B',
        });
        expect(
          (await definition.aktar(
            preview,
            preview.kayitlar.map((r) => r.id).toSet(),
          )).eklenen,
          2,
        );
      },
    );

    test(
      'Yıllık plan seçiminde yalnız seçilen haftalar ve bağlı takvim hazırlanır',
      () async {
        final module = YillikPlanImportTanimi.olustur('2026/2027');
        final preview = await module.hazirla([
          ImportKaynakSatiri('a', '1', {
            'hafta': '1',
            'tarih': '7-11 Eylül',
            'konu': 'Sayılar',
          }),
          ImportKaynakSatiri('b', '2', {
            'hafta': '2',
            'tarih': '14-18 Eylül',
            'konu': 'Kesirler',
          }),
        ]);
        expect(preview.engeller, isEmpty);
        final selected = YillikPlanImportTanimi.secimiUygula(
          ImportSecimi(ImportDosya('plan.csv', Uint8List(0)), preview, {
            'plan:1',
          }),
        );
        expect(selected.kayitlar.single.haftaNo, 2);
        expect(selected.calismaTakvimi.single.haftaNo, 2);
        await expectLater(module.aktar(preview, {'plan:1'}), throwsStateError);
        expect(await db.query('YillikPlanDetay'), isEmpty);
      },
    );

    test(
      'Seçili yıllık plan tekrar import edilir; seçilmeyen mevcut hafta korunur',
      () async {
        final p = BireyselYillikPlanService.eslenmisSatirlariOku([
          {'hafta': '1', 'tarih': '7-11 Eylül', 'konu': 'Sayılar'},
          {'hafta': '2', 'tarih': '14-18 Eylül', 'konu': 'Kesirler'},
        ], egitimOgretimYili: '2026/2027');
        await BireyselYillikPlanService.kaydet(
          dersId: 1,
          sinifSeviyesi: 9,
          ogretmenProfilId: 1,
          egitimOgretimYili: '2026/2027',
          onIzleme: p,
          mevcutKayitlariKoru: true,
        );
        final first = (await db.query(
          'YillikPlanDetay',
          where: 'HaftaNo = 1',
        )).single;
        final changed = BireyselYillikPlanService.eslenmisSatirlariOku([
          {'hafta': '2', 'tarih': '14-18 Eylül', 'konu': 'Yeni Kesirler'},
        ], egitimOgretimYili: '2026/2027');
        for (var i = 0; i < 2; i++) {
          await BireyselYillikPlanService.kaydet(
            dersId: 1,
            sinifSeviyesi: 9,
            ogretmenProfilId: 1,
            egitimOgretimYili: '2026/2027',
            onIzleme: changed,
            mevcutKayitlariKoru: true,
          );
        }
        expect((await db.query('YillikPlanDetay')).length, 2);
        expect(
          (await db.query('YillikPlanDetay', where: 'HaftaNo = 1')).single,
          first,
        );
        expect(
          (await db.query(
            'YillikPlanDetay',
            where: 'HaftaNo = 2',
          )).single['Konu'],
          'Yeni Kesirler',
        );
        expect((await db.query('CalismaTakvimiDetay')).length, 2);
        await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
        await expectLater(
          BireyselYillikPlanService.kaydet(
            dersId: 1,
            sinifSeviyesi: 9,
            ogretmenProfilId: 1,
            egitimOgretimYili: '2026/2027',
            onIzleme: changed,
            mevcutKayitlariKoru: true,
          ),
          throwsA(
            predicate(
              (e) => e.toString().contains('Öğretmen veya eğitim yılı değişti'),
            ),
          ),
        );
      },
    );

    test(
      'Program seçiminde ders, koordinatörlük ve şeflik ayrı korunur',
      () async {
        final module = DersProgramiImportTanimi.olustur(
          'Öğretmen',
          meslekPaketi: false,
        );
        final preview = await module.hazirla([
          ImportKaynakSatiri('a', '1', {
            'gun': 'Pazartesi',
            'dersSaatiNo': '1',
            'dersAdi': 'Matematik',
            'sinif': '9-A',
            'baslangic': '08:00',
            'bitis': '08:40',
          }),
          ImportKaynakSatiri('b', '2', {
            'gun': 'Salı',
            'dersSaatiNo': '2',
            'dersAdi': 'Koordinatörlük',
            'baslangic': '09:00',
            'bitis': '09:40',
          }),
          ImportKaynakSatiri('c', '3', {
            'gun': 'Yanlış',
            'dersSaatiNo': '0',
            'dersAdi': 'Matematik',
          }),
        ]);
        expect(
          preview.kayitlar.where((r) => r.durum == ImportDurumu.hatali).length,
          1,
        );
        final p = DersProgramiImportTanimi.secimiUygula(preview, {'ders:1'});
        expect(p.dersler.single.gorevMi, isTrue);
        expect(p.gunlukDersSaatAdaylari.single.gun, 'Salı');
        expect(
          () => DersProgramiImportTanimi.secimiUygula(preview, {'hata:c'}),
          throwsStateError,
        );
        await BireyselDersProgramiService.kaydet(
          ogretmenProfilId: 1,
          egitimOgretimYili: '2026/2027',
          baslangicTarihi: DateTime(2030, 1, 1),
          kayitlar: [
            BireyselDersProgramiKayitGirdisi(
              gun: p.dersler.single.gun,
              dersSaatiNo: 2,
              dersAdi: 'Koordinatörlük',
              sinif: '',
              baslangic: '09:00',
              bitis: '09:40',
              derslik: '',
            ),
          ],
        );
        expect(
          (await db.query('DersProgramiGorev')).single['GorevAdi'],
          'Koordinatörlük',
        );
      },
    );

    test(
      'Mevcut program dosyası ortak seçimde ders, görev, şeflik ve başlangıcı korur',
      () async {
        final file = ImportDosya(
          'Ders_Programi.xlsx',
          File('test/fixtures/Ders_Programi.xlsx').readAsBytesSync(),
        );
        final preview = await DersProgramiImportTanimi.olustur(
          'NURKAN SIRMA',
          meslekPaketi: true,
        ).ozelOku!(file);
        final all = preview.kayitlar
            .where((r) => r.aktarilabilir)
            .map((r) => r.id)
            .toSet();
        final selected = DersProgramiImportTanimi.secimiUygula(preview, all);
        expect(selected.dersler.length, 38);
        expect(selected.dersler.where((d) => d.gorevMi).length, 13);
        expect(selected.seflikSaatleri.length, 6);
        expect(selected.baslangicTarihi, DateTime(2026, 9, 14));
        final locked = DersProgramiImportTanimi.onIzlemeyeCevir(
          preview.veri as BireyselDersProgramiOnIzleme,
          meslekPaketi: false,
        );
        expect(
          locked.kayitlar
              .where((r) => r.id.startsWith('seflik:'))
              .every((r) => !r.aktarilabilir),
          isTrue,
        );
        expect(selected.gunlukDersSaatAdaylari.length, 44);
      },
    );

    test(
      'Word yıllık planın mevcut okuyucusu ortak önizleme ve seçimle çalışır',
      () async {
        final xml = utf8.encode(
          '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:t>9. SINIF MATEMATİK YILLIK PLANI</w:t></w:r></w:p><w:tbl>
        <w:tr><w:tc><w:p><w:r><w:t>Hafta</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Tarih</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Konu</w:t></w:r></w:p></w:tc></w:tr>
        <w:tr><w:tc><w:p><w:r><w:t>1. Hafta</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>7-11 Eylül</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Sayılar</w:t></w:r></w:p></w:tc></w:tr>
        </w:tbl></w:body></w:document>''',
        );
        final archive = Archive()
          ..addFile(ArchiveFile('word/document.xml', xml.length, xml));
        final file = ImportDosya(
          'plan.docx',
          Uint8List.fromList(ZipEncoder().encode(archive)!),
        );
        final preview = await YillikPlanImportTanimi.olustur(
          '2026/2027',
        ).ozelOku!(file);
        expect(preview.engeller, isEmpty);
        final selected = YillikPlanImportTanimi.secimiUygula(
          ImportSecimi(file, preview, {'plan:0'}),
        );
        expect(selected.tespitEdilenSinifSeviyesi, 9);
        expect(selected.kayitlar.single.konu, 'Sayılar');
        expect(selected.calismaTakvimi.single.baslangicTarihi, '2026-09-07');
      },
    );

    test('Fotoğraf adaptörü geçersiz seçimle SQLite kaydı yapmaz', () async {
      expect(FotografImportTanimi.tanim.yalnizOzelOkuyucu, isTrue);
      expect(FotografImportTanimi.tanim.uzantilar, {'xls'});
      await expectLater(
        FotografImportTanimi.tanim.aktar(
          ImportOnIzleme([
            ImportKaydi('101', 'Fotoğraf', {'okulNo': '101'}),
          ]),
          {'101'},
        ),
        throwsStateError,
      );
      expect(await db.query('OgrenciFotograf'), isEmpty);
    });

    Future<void> tapAsync(WidgetTester tester, Finder finder, {
      bool durulmasiniBekle = true,
    }) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          300,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(finder);
      if (durulmasiniBekle) await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(finder);
        // Yeni route kurulunca başlangıç dosyasının isolate okuması başlar.
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        // Diyalog kapanışı, kayıt Future'ları ve sonuç route'u ayrı karelerde ilerler.
        for (var kare = 0; kare < 4; kare++) {
          await tester.pump(const Duration(milliseconds: 350));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      if (durulmasiniBekle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 350));
      }
    }

    testWidgets(
      'Ortak ekran seçimi döndürür; program onayından önce kayıt yapılmaz',
      (tester) async {
        ImportSecimi? returned;
        final file = ImportDosya(
          'program.csv',
          Uint8List.fromList(
            utf8.encode(
              'Gün;Ders Saati No;Ders;Sınıf;Başlangıç;Bitiş\nPazartesi;1;Matematik;9-A;08:00;08:40\nSalı;2;Matematik;10-B;09:00;09:40',
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    returned = await Navigator.of(context).push<ImportSecimi>(
                      MaterialPageRoute(
                        builder: (_) => OrtakImportScreen(
                          tanim: DersProgramiImportTanimi.olustur(
                            'Öğretmen',
                            meslekPaketi: false,
                          ),
                          baslangicDosyasi: file,
                          secimleDon: true,
                        ),
                      ),
                    );
                  },
                  child: const Text('Başlat'),
                ),
              ),
            ),
          ),
        );
        await tapAsync(tester, find.text('Başlat'));
        await tapAsync(tester, find.text('Ön İzleme Hazırla'));
        await tapAsync(tester, find.text('Tüm Aktarılabilirleri Seç'));
        expect(
          find.text('2 Seçili Kaydı Onaya Gönder'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join('\n'),
        );
        await tapAsync(tester, find.text('2 Seçili Kaydı Onaya Gönder'));
        await tapAsync(tester, find.text('Seçimi Onayla ve Devam Et'));
        expect(returned!.secimler.length, 2);
        expect(
          DersProgramiImportTanimi.secimiUygula(
            returned!.onIzleme,
            returned!.secimler,
          ).dersler.length,
          2,
        );
        expect((await db.query('DersProgrami')).length, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Yıllık plan ortak ekranda tek onayla kaydedilir',
      (tester) async {
        final originalPicker = FilePicker.platform;
        final planExcel = Excel.createExcel();
        planExcel['Sheet1'].appendRow(['Hafta','Tarih','Konu']);
        planExcel['Sheet1'].appendRow([1,'7-11 Eylül','Sayılar']);
        planExcel['Sheet1'].appendRow([2,'14-18 Eylül','Kesirler']);
        FilePicker.platform = MemoryFilePicker(
          'Hafta;Tarih;Konu\n1;7-11 Eylül;Sayılar\n2;14-18 Eylül;Kesirler',
          veri: Uint8List.fromList(planExcel.encode()!), ad: 'plan.xlsx',
        );
        addTearDown(() => FilePicker.platform = originalPicker);
        await tester.pumpWidget(
          const MaterialApp(
            home: BireyselYillikPlanImportScreen(
              baslangicDersId: 1,
              baslangicSinifSeviyesi: 9,
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        await tapAsync(tester, find.text('Seçilen Derse Ait Yıllık Planı Seç'));
        await tapAsync(tester, find.text('Dosya Seç'));
        await tester.tap(find.text('Cihazımdan Seç'));
        await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
        await tester.pumpAndSettle();
        await tapAsync(tester, find.text('Ön İzleme Hazırla'));
        expect(find.text('Seçilenleri Onayla ve Kaydet'), findsOneWidget);
        await tapAsync(tester, find.text('Seçilenleri Onayla ve Kaydet'));
        expect(find.byType(OrtakImportScreen), findsOneWidget);
        expect(
          find.text('Yıllık Planı Onayla ve Kaydet'),
          findsOneWidget,
        );
        expect(await db.query('YillikPlanDetay'), isEmpty);
        await tapAsync(tester, find.text('Onayla ve Kaydet'),
          durulmasiniBekle: false);
        expect(find.byType(OrtakImportScreen), findsNothing);
        expect(find.text('Başka Yıllık Plan Yükle'), findsOneWidget);
        expect(await db.query('YillikPlanDetay'), hasLength(2));
        await tapAsync(tester, find.text('Başka Yıllık Plan Yükle'),
          durulmasiniBekle: false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Özel onay gizli ve uyarılı seçimleri korur; hata tekrar denenir',
        (tester) async {
      final onaylar = <ImportSecimi>[];
      final kayitlar = <ImportSecimi>[];
      ImportOzet? sonuc;
      final dosya = ImportDosya('secim.csv', Uint8List.fromList(utf8.encode(
        'Sınıf;Konu\n9-A;Birinci\n10-B;İkinci',
      )));
      final tanim = ImportTanimi(
        id: 'test_ozel_onay', ad: 'Özel Onay', aciklama: '',
        alanlar: const [
          ImportAlan('sinif', 'Sınıf', filtrelenebilir: true),
          ImportAlan('konu', 'Konu', zorunlu: true),
        ],
        hazirla: (rows) async => ImportOnIzleme(rows.map((r) => ImportKaydi(
          r.id, r.konum, r.degerler,
          durum: r.degerler['sinif'] == '10-B'
              ? ImportDurumu.uyarili : ImportDurumu.uygun,
        )).toList()),
        aktar: (_, _) async => throw StateError('Varsayılan aktar çağrılmamalı.'),
      );
      await tester.pumpWidget(MaterialApp(home: Builder(
        builder: (context) => Scaffold(body: FilledButton(
          child: const Text('Başlat'),
          onPressed: () async {
            sonuc = await Navigator.of(context).push<ImportOzet>(MaterialPageRoute(
              builder: (_) => OrtakImportScreen(
                tanim: tanim, baslangicDosyasi: dosya,
                secimOnayi: (context, secim, ortakOzet) async {
                  onaylar.add(secim);
                  expect(secim.secimler, hasLength(2));
                  expect(() => secim.secimler.add('sonradan'), throwsUnsupportedError);
                  return await showDialog<bool>(context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Özel Kaydı Onayla'),
                      content: Text(ortakOzet),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Vazgeç')),
                        FilledButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Özel Onayla ve Kaydet')),
                      ],
                    ),
                  ) ?? false;
                },
                secimiKaydet: (secim) async {
                  kayitlar.add(secim);
                  expect(secim.secimler, onaylar.last.secimler);
                  if (kayitlar.length == 1) throw StateError('Özel kayıt test hatası');
                  return ImportOzet(eklenen: secim.secimler.length,
                    guncellenen: 0, atlanan: 0, hatali: 0, mesaj: 'Kaydedildi');
                },
              ),
            ));
          },
        )),
      )));
      await tapAsync(tester, find.text('Başlat'));
      await tapAsync(tester, find.text('Ön İzleme Hazırla'));
      await tapAsync(tester, find.text('Tüm Aktarılabilirleri Seç'));
      final filtre = find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('filtre:sinif:'));
      await tapAsync(tester, filtre);
      await tapAsync(tester, find.text('9-A').last);
      await tapAsync(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      expect(find.textContaining('Filtreyle gizlenen seçili: 1'), findsOneWidget);
      expect(find.textContaining('Uyarılı seçili: 1'), findsOneWidget);
      await tapAsync(tester, find.text('Vazgeç'));
      expect(kayitlar, isEmpty);
      expect(sonuc, isNull);
      await tapAsync(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      await tapAsync(tester, find.text('Özel Onayla ve Kaydet'));
      expect(find.byType(OrtakImportScreen), findsOneWidget);
      expect(kayitlar, hasLength(1));
      expect(find.textContaining('Özel kayıt test hatası'), findsWidgets);
      expect(sonuc, isNull);
      await tapAsync(tester, find.text('Seçilenleri Onayla ve Kaydet'));
      expect(find.textContaining('Filtreyle gizlenen seçili: 1'), findsOneWidget);
      expect(find.textContaining('Uyarılı seçili: 1'), findsOneWidget);
      await tapAsync(tester, find.text('Özel Onayla ve Kaydet'));
      expect(find.byType(OrtakImportScreen), findsNothing);
      expect(sonuc?.eklenen, 2);
      expect(onaylar, hasLength(3));
      expect(kayitlar, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bireysel fotoğraf menüsü ortak import ekranını açar', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AdminImportScreen(bireyselFoto: true),
        ),
      );
      final screen = tester.widget<OrtakImportScreen>(
        find.byType(OrtakImportScreen),
      );
      expect(screen.tanim.id, 'bireysel_fotograf');
      expect(screen.kayitGorseli, isNotNull);
      expect(find.text('Import Klasöründen Dosya Seç'), findsNothing);
      expect(find.text('Belgelerimden Seç'), findsOneWidget);
      expect(find.text('Cihazdan Dosya Seç'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    const externalXls = String.fromEnvironment('IMPORT_XLS_TEST_FILE');
    test(
      'Gerçek XLS sınıf kolonu olmadan öğrenci önizlemesi oluşturur',
      () async {
        final extraIds = <int>[];
        for (final name in ['11-C', '12-C']) {
          final id = await db.insert('SinifSube', {
            'SinifKodu': name,
            'EgitimOgretimYili': '2026/2027',
            'OlusturmaTarihi': 'test',
          });
          extraIds.add(id);
          await db.insert('DersProgrami', {
            'SinifSubeId': id,
            'DersId': 1,
            'DersSaatiId': 1,
            'Gun': 'Çarşamba',
            'Baslangic': '08:00',
            'Bitis': '08:40',
            'OgretmenProfilId': 1,
            'EgitimOgretimYili': '2026/2027',
            'OlusturmaTarihi': 'test',
          });
        }
        try {
          final file = ImportDosya(
            'gercek.xls',
            File(externalXls).readAsBytesSync(),
          );
          final tables = await OrtakImportService.oku(file);
          expect(
            definition.ozelDuzeniTani!(tables.map((t) => t.satirlar).toList()),
            isTrue,
          );
          final preview = await definition.ozelOku!(file);
          expect(preview.engeller, isEmpty);
          expect(preview.kayitlar, isNotEmpty);
          expect(
            preview.kayitlar
                .where((r) => r.durum == ImportDurumu.uygun)
                .map((r) => r.degerler['sinif'])
                .toSet(),
            {'9-A', '10-B', '11-C', '12-C'},
          );
          expect(await db.query('Ogrenci'), isEmpty);
        } finally {
          for (final id in extraIds) {
            await db.delete(
              'DersProgrami',
              where: 'SinifSubeId = ?',
              whereArgs: [id],
            );
            await db.delete(
              'SinifSube',
              where: 'SinifSubeId = ?',
              whereArgs: [id],
            );
          }
        }
      },
      skip: externalXls.isEmpty,
    );

    testWidgets('Hatalı bölüm varken ekranda uygun kayıt seçilebilir', (
      tester,
    ) async {
      final excel = Excel.createExcel();
      excel['Liste'].appendRow(['9. Sınıf A Şubesi']);
      excel['Liste'].appendRow(['Okul No', 'Adı', 'Soyadı']);
      excel['Liste'].appendRow([101, 'Ayşe', 'Yılmaz']);
      excel['İkinci'].appendRow(['10. Sınıf B Şubesi']);
      excel['İkinci'].appendRow(['Okul No', 'Adıv', 'Soyadım']);
      excel['İkinci'].appendRow([201, 'Ali', 'Yılmaz']);
      final originalPicker = FilePicker.platform;
      FilePicker.platform = MemoryFilePicker(
        '',
        veri: Uint8List.fromList(excel.encode()!),
        ad: 'liste.xlsx',
      );
      addTearDown(() => FilePicker.platform = originalPicker);
      await tester.pumpWidget(
        const MaterialApp(home: AdminImportScreen()),
      );
      await tapAsync(tester, find.text('Cihazdan Dosya Seç'));
      await tapAsync(tester, find.text('Ön İzleme Hazırla'));
      await tapAsync(tester, find.text('Tüm Aktarılabilirleri Seç'));
      expect(find.text('1 Seçili Kaydı Aktar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(await db.query('Ogrenci'), isEmpty);
    });

    testWidgets('Yeni kart ortak ekranda kolon dışı zorunlu bilgiyi kullanır', (
      tester,
    ) async {
      final originalPicker = FilePicker.platform;
      FilePicker.platform = MemoryFilePicker('Gün: Pazartesi\nKonu\nToplantı');
      addTearDown(() => FilePicker.platform = originalPicker);
      List<ImportKaynakSatiri>? received;
      final module = ImportTanimi(
        id: 'test_kart',
        ad: 'Etkinlik',
        aciklama: '',
        alanlar: const [
          ImportAlan('konu', 'Konu', zorunlu: true),
          ImportAlan(
            'gun',
            'Gün',
            zorunlu: true,
            kolonDisiKapsam: ImportBilgiKapsami.blok,
          ),
        ],
        hazirla: (rows) async {
          received = rows;
          return ImportOnIzleme(
            rows.map((r) => ImportKaydi(r.id, r.konum, r.degerler)).toList(),
          );
        },
        aktar: (p, s) async => ImportOzet(
          eklenen: s.length,
          guncellenen: 0,
          atlanan: 0,
          hatali: 0,
          mesaj: 'Tamam',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: OrtakImportScreen(tanim: module)),
      );
      await tapAsync(tester, find.text('Cihazdan Dosya Seç'));
      await tapAsync(tester, find.text('Ön İzleme Hazırla'));
      expect(received!.single.degerler, {
        'konu': 'Toplantı',
        'gun': 'Pazartesi',
      });
      expect(find.text('1 Seçili Kaydı Aktar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Dar ekranda ortak öğrenci ekranı, filtre koruması ve onaylı aktarım',
      (tester) async {
        final originalPicker = FilePicker.platform;
        FilePicker.platform = MemoryFilePicker(
          'Okul No;Ad;Soyad;Sınıf;Cinsiyet\n101;Ayşe;Yılmaz;9-A;Kız\n102;Ali;Yılmaz;10-B;Erkek',
        );
        addTearDown(() {
          FilePicker.platform = originalPicker;
        });
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          const MaterialApp(home: AdminImportScreen()),
        );
        await tapAsync(tester, find.text('Cihazdan Dosya Seç'));
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Ön İzleme Hazırla'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tapAsync(tester, find.text('Ön İzleme Hazırla'));
        await tester.scrollUntilVisible(
          find.text('Tüm Aktarılabilirleri Seç'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tüm Aktarılabilirleri Seç'));
        await tester.pumpAndSettle();
        expect(find.text('2 Seçili Kaydı Aktar'), findsOneWidget);
        final classFilter = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('filtre:sinif:'),
        );
        await tester.ensureVisible(classFilter);
        await tester.pumpAndSettle();
        await tester.tap(classFilter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('9-A').last);
        await tester.pumpAndSettle();
        expect(find.text('2 Seçili Kaydı Aktar'), findsOneWidget);
        await tester.tap(find.text('2 Seçili Kaydı Aktar'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Filtreyle gizlenen seçili: 1'),
          findsOneWidget,
        );
        await tapAsync(tester, find.text('Onayla ve Aktar'));
        expect(find.text('Aktarım Tamamlandı'), findsOneWidget);
        expect((await db.query('Ogrenci')).length, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Profil kaydedilir ve tekrar dosya seçildiğinde otomatik tanınır',
      (tester) async {
        final originalPicker = FilePicker.platform;
        FilePicker.platform = MemoryFilePicker(
          'Okul No;Ad;Soyad;Sınıf\n101;Ayşe;Yılmaz;9-A',
        );
        addTearDown(() {
          FilePicker.platform = originalPicker;
        });
        await tester.pumpWidget(
          const MaterialApp(home: AdminImportScreen()),
        );
        await tapAsync(tester, find.text('Cihazdan Dosya Seç'));
        await tester.scrollUntilVisible(
          find.text('Eşleştirmeyi Profil Olarak Kaydet'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eşleştirmeyi Profil Olarak Kaydet'));
        await tester.pumpAndSettle();
        final input = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(input, 'Test Profilim');
        await tapAsync(tester, find.text('Kaydet'));
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Cihazdan Dosya Seç'),
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tapAsync(tester, find.text('Cihazdan Dosya Seç'));
        expect(
          find.text(
            'Test Profilim profili tanındı. Eşleştirmeyi kontrol edin.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Sınıf bloklu dosya kolon seçimi gerektirmeden otomatik tanınır',
      (tester) async {
        final excel = Excel.createExcel();
        excel['Liste'].appendRow(['9. Sınıf A Şubesi']);
        excel['Liste'].appendRow(['Sınıf Öğretmeni: Birinci Öğretmen']);
        excel['Liste'].appendRow(['Okul No', 'Adı', 'Soyadı']);
        excel['Liste'].appendRow([101, 'Ayşe', 'Yılmaz']);
        final originalPicker = FilePicker.platform;
        FilePicker.platform = MemoryFilePicker(
          '',
          veri: Uint8List.fromList(excel.encode()!),
          ad: 'blok.xlsx',
        );
        addTearDown(() => FilePicker.platform = originalPicker);
        await tester.pumpWidget(
          const MaterialApp(home: AdminImportScreen()),
        );
        await tapAsync(tester, find.text('Cihazdan Dosya Seç'));
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
        expect(find.text('Başlık satırı (1’den başlar)'), findsNothing);
        // Kullanıcı kolon görünümüne geçse de sınıfı kolon yapmaya zorlanmaz.
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse,
        );
        await tapAsync(tester, find.text('Ön İzleme Hazırla'));
        expect(find.text('0 Seçili Kaydı Aktar'), findsOneWidget);
        expect(await db.query('Ogrenci'), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }, skip: !Platform.isWindows);
}

class MemoryFilePicker extends FilePicker {
  MemoryFilePicker(this.text, {this.veri, this.ad = 'liste.csv'});
  final String text;
  final Uint8List? veri;
  final String ad;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final bytes = veri ?? Uint8List.fromList(utf8.encode(text));
    return FilePickerResult([
      PlatformFile(name: ad, size: bytes.length, bytes: bytes),
    ]);
  }
}
