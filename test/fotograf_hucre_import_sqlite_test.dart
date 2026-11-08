import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_import_tanimi.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final factory = WindowsMemoryFactory();
  late Database db;
  late ImportDosya dosya;
  late BireyselFotoExcelDosyasi excel;
  const yil = '2026/2027';
  const siniflar = ['9-C', '9-D', '10-D', '11-C', '11-D', '12-D'];

  setUpAll(() async {
    databaseFactory = factory;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Test Öğretmeni',
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Bilişim', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    for (final sinif in siniflar) {
      final id = await db.insert('SinifSube', {
        'SinifKodu': sinif,
        'SinifSeviyesi': int.parse(sinif.split('-').first),
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': id,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'Baslangic': '08:00',
        'Bitis': '08:40',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
    }
    // Mevcut örnek yalnız bellekte okunur; öğrenci bilgileri çıktıya yazılmaz.
    dosya = ImportDosya(
      '9.xls',
      File('assets/baslangic_belgeleri/9.xls').readAsBytesSync(),
    );
    excel = await BireyselImportService.fotoExcelOku(dosya.bytes);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await db.delete('OgrenciFotograf');
    await db.delete('OgrenciSinifKayit');
    await db.delete('Ogrenci');
    await db.delete('UygulamaAyarlari');
    await db.delete('OgretmenProfil', where: 'OgretmenProfilId <> 1');
    await db.delete('SinifSube', where: 'SinifSubeId > 6');
    await db.update('SinifSube', {'Aktif': 1, 'EgitimOgretimYili': yil});
    await db.update('OgretmenProfil', {'EgitimOgretimYili': yil, 'Aktif': 1});
    await db.update('DersProgrami', {'Aktif': 1});
  });
  tearDownAll(() async => factory.db?.close());

  Map<String, String> ikiSinif() => {
    excel.hucreler[0].id: '9-C',
    excel.hucreler[1].id: '9-D',
  };

  Future<int> kayitliOgrenci(
    int hucre,
    String sinif, {
    String? okulNo,
    String? ad,
    String? soyad,
    bool uyelik = true,
    bool aktif = true,
    bool uyelikAktif = true,
  }) async {
    var sinifRows = await db.query(
      'SinifSube',
      where: 'SinifKodu = ?',
      whereArgs: [sinif],
    );
    if (sinifRows.isEmpty) {
      await db.insert('SinifSube', {
        'SinifKodu': sinif,
        'SinifSeviyesi': int.parse(sinif.split('-').first),
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
      sinifRows = await db.query(
        'SinifSube',
        where: 'SinifKodu = ?',
        whereArgs: [sinif],
      );
    }
    final h = excel.hucreler[hucre];
    final id = await db.insert('Ogrenci', {
      'OkulNo': okulNo ?? h.okulNo,
      'Ad': ad ?? h.ad,
      'Soyad': soyad ?? h.soyad,
      'Cinsiyet': 'Erkek',
      'Aktif': aktif ? 1 : 0,
      'OlusturmaTarihi': 'öğrenci importundan',
    });
    if (uyelik) {
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': sinifRows.single['SinifSubeId'],
        'EgitimOgretimYili': yil,
        'Aktif': uyelikAktif ? 1 : 0,
        'OlusturmaTarihi': 'öğrenci importundan',
      });
    }
    return id;
  }

  Future<Map<String, Object>> ogrenciTablolari() async => {
    'Ogrenci': await db.query('Ogrenci', orderBy: 'OgrenciId'),
    'OgrenciSinifKayit': await db.query(
      'OgrenciSinifKayit',
      orderBy: 'OgrenciSinifKayitId',
    ),
    'SinifSube': await db.query('SinifSube', orderBy: 'SinifSubeId'),
  };

  ImportDosya tekrarliDosya() {
    // C8'in metin bağlantısı bellekte A8'e çevrilir; gerçek XLS korunur.
    final bytes = Uint8List.fromList(dosya.bytes);
    final data = ByteData.sublistView(bytes);
    int kayitKonumu(int col) {
      final konumlar = <int>[];
      for (var p = 0; p + 14 <= bytes.length; p++) {
        if (data.getUint16(p, Endian.little) == 0xfd &&
            data.getUint16(p + 2, Endian.little) == 10 &&
            data.getUint16(p + 4, Endian.little) == 7 &&
            data.getUint16(p + 6, Endian.little) == col) {
          konumlar.add(p);
        }
      }
      expect(konumlar, hasLength(1));
      return konumlar.single;
    }

    final ilk = kayitKonumu(0), ikinci = kayitKonumu(2);
    data.setUint32(
      ikinci + 10,
      data.getUint32(ilk + 10, Endian.little),
      Endian.little,
    );
    return ImportDosya('tekrar.xls', bytes);
  }

  test('Fotoğraflı XLS öğrenci hücrelerinin gerçek adreslerini korur', () {
    expect(excel.sayfalar, hasLength(1));
    expect(excel.hucreler.length, greaterThan(2));
    expect(excel.hucreler[0].id, '0:7:0'); // A8
    expect(excel.hucreler[1].id, '0:7:2'); // C8
    expect(
      excel.hucreler.map((h) => h.id).toSet().length,
      excel.hucreler.length,
    );
    expect(
      excel.hucreler.every((h) => h.fotoVerisi?.isNotEmpty ?? false),
      isTrue,
    );
  });

  test('Fotoğraf importundan önce kayıtlı öğrenci listesi gerekir', () async {
    await expectLater(
      BireyselImportService.ortakFotoOzelOku(dosya),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'uyarı',
          contains('Öğrenci'),
        ),
      ),
    );
    await expectLater(
      BireyselImportService.ortakFotoOzelOku(dosya, sinifHucreleri: ikiSinif()),
      throwsStateError,
    );
    expect(await db.query('Ogrenci'), isEmpty);
    expect(await db.query('OgrenciFotograf'), isEmpty);
  });

  test(
    'Dosya sınıfı yerine kayıtlı listeyle otomatik eşleşir ve yalnız seçilen fotoğraf yazılır',
    () async {
      final ilk = await kayitliOgrenci(0, '9-C');
      final ikinci = await kayitliOgrenci(1, '9-D');
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isEmpty);
      expect(preview.kayitlar, hasLength(2));
      expect(preview.kayitlar.map((k) => k.degerler['sinif']).toSet(), {
        '9-C',
        '9-D',
      });
      final p = preview.veri! as BireyselFotoOnIzleme;
      expect(p.kayitlar.map((k) => k.ogrenciId).toSet(), {ilk, ikinci});
      expect(await ogrenciTablolari(), once);
      final result = await BireyselImportService.ortakFotograflariKaydet(
        preview,
        {excel.hucreler[0].okulNo},
      );
      expect(result.eklenen, 1); // Öğrenci sayılmaz; yalnız fotoğraf eklenir.
      expect(result.guncellenen, 0);
      expect((await db.query('OgrenciFotograf')).single['OgrenciId'], ilk);
      expect(await ogrenciTablolari(), once);
      expect(result.atlanan, preview.onceAtlanan + 1);
    },
  );

  test(
    'Numara başındaki sıfır ve Türkçe adın harf/boşluk farkları mevcut kimliği korur',
    () async {
      final h = excel.hucreler[0];
      final id = await kayitliOgrenci(
        0,
        '9-C',
        okulNo: '000${h.okulNo}',
        ad: '  ${h.ad.toLowerCase().replaceAll('ı', 'i')}  ',
        soyad: ' ${h.soyad.toLowerCase()} ',
      );
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isEmpty);
      final p = preview.veri! as BireyselFotoOnIzleme;
      expect(p.kayitlar.single.ogrenciId, id);
      final sonuc = await BireyselImportService.ortakFotograflariKaydet(
        preview,
        {preview.kayitlar.single.id},
      );
      expect(sonuc.eklenen, 1);
      expect((await db.query('OgrenciFotograf')).single['OgrenciId'], id);
      expect(await ogrenciTablolari(), once);
    },
  );

  test(
    'Eşleşmeyen isim, üyelik, pasif öğrenci ve izinsiz sınıf geçerli eşleşmeyi engellemez',
    () async {
      final ilk = await kayitliOgrenci(0, '9-C');
      await kayitliOgrenci(1, '9-D', ad: 'Farklı Kayıt');
      await kayitliOgrenci(2, '10-D', uyelik: false);
      await kayitliOgrenci(3, '11-C', aktif: false);
      await kayitliOgrenci(4, '11-D', uyelikAktif: false);
      await kayitliOgrenci(5, '9-Z');
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isEmpty);
      expect(preview.kayitlar, hasLength(1));
      expect((preview.veri! as BireyselFotoOnIzleme).uyarilar, isNotEmpty);
      final sonuc = await BireyselImportService.ortakFotograflariKaydet(
        preview,
        {preview.kayitlar.single.id},
      );
      expect(sonuc.eklenen, 1);
      expect((await db.query('OgrenciFotograf')).single['OgrenciId'], ilk);
      expect(await ogrenciTablolari(), once);
    },
  );

  test(
    'Hiçbir fotoğraf kayıtlı öğrencinin adıyla eşleşmezse kaydetme engellenir',
    () async {
      await kayitliOgrenci(0, '9-C', ad: 'Farklı Kayıt');
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isNotEmpty);
      expect(preview.kayitlar, isEmpty);
      await expectLater(
        BireyselImportService.ortakFotograflariKaydet(preview, {
          excel.hucreler[0].okulNo,
        }),
        throwsStateError,
      );
      expect(await db.query('OgrenciFotograf'), isEmpty);
    },
  );

  test(
    'Elle seçilen hücrelerin yalnız mevcut sınıf ve öğrenci eşleşmeleri kullanılır',
    () async {
      final ilk = await kayitliOgrenci(0, '9-C');
      await kayitliOgrenci(1, '9-D');
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(
        dosya,
        sinifHucreleri: ikiSinif(),
      );
      expect(preview.engeller, isEmpty);
      expect(preview.kayitlar, hasLength(2));
      final result = await BireyselImportService.ortakFotograflariKaydet(
        preview,
        {excel.hucreler[0].okulNo},
      );
      expect(result.eklenen, 1);
      expect((await db.query('OgrenciFotograf')).single['OgrenciId'], ilk);
      expect(await ogrenciTablolari(), once);
    },
  );

  test('Boş veya dosyada öğrenci olmayan hücre seçimi reddedilir', () async {
    await kayitliOgrenci(0, '9-C');
    await expectLater(
      BireyselImportService.ortakFotoOzelOku(dosya, sinifHucreleri: {}),
      throwsStateError,
    );
    await expectLater(
      BireyselImportService.ortakFotoOzelOku(
        dosya,
        sinifHucreleri: {'0:0:0': '9-C'},
      ),
      throwsFormatException,
    );
    expect(await db.query('OgrenciFotograf'), isEmpty);
  });

  test(
    'Elle yanlış sınıf atanırsa mevcut üyelik taşınmaz ve kısmi kayıt da engellenir',
    () async {
      await kayitliOgrenci(0, '9-C');
      await kayitliOgrenci(1, '9-D');
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(
        dosya,
        sinifHucreleri: {
          excel.hucreler[0].id: '9-C',
          excel.hucreler[1].id: '10-D',
        },
      );
      expect(preview.engeller, isNotEmpty);
      await expectLater(
        BireyselImportService.ortakFotograflariKaydet(preview, {
          excel.hucreler[0].okulNo,
        }),
        throwsStateError,
      );
      expect(await ogrenciTablolari(), once);
      expect(await db.query('OgrenciFotograf'), isEmpty);
    },
  );

  test(
    'Elle seçilmiş isim uyuşmazlığı veya kayıtsız öğrenci yeni öğrenci oluşturmaz',
    () async {
      await kayitliOgrenci(0, '9-C', ad: 'Farklı Kayıt');
      final once = await ogrenciTablolari();
      for (final index in [0, 1]) {
        final preview = await BireyselImportService.ortakFotoOzelOku(
          dosya,
          sinifHucreleri: {excel.hucreler[index].id: '9-C'},
        );
        expect(preview.engeller, isNotEmpty);
        expect((preview.veri! as BireyselFotoOnIzleme).kaydedilebilir, isFalse);
      }
      expect(await ogrenciTablolari(), once);
      expect(await db.query('OgrenciFotograf'), isEmpty);
    },
  );

  test(
    'Kaynakta tekrarlanan numara otomatik atlanır, elle seçimde belirsizlik reddedilir',
    () async {
      await kayitliOgrenci(0, '9-C');
      final guvenliId = await kayitliOgrenci(2, '10-D');
      final degisik = tekrarliDosya();
      final preview = await BireyselImportService.ortakFotoOzelOku(degisik);
      expect(preview.engeller, isEmpty);
      expect(preview.kayitlar, hasLength(1));
      expect(
        (preview.veri! as BireyselFotoOnIzleme).kayitlar.single.ogrenciId,
        guvenliId,
      );
      await expectLater(
        BireyselImportService.ortakFotoOzelOku(
          degisik,
          sinifHucreleri: {excel.hucreler[1].id: '9-C'},
        ),
        throwsFormatException,
      );
      final degisikExcel = await BireyselImportService.fotoExcelOku(
        degisik.bytes,
      );
      expect(
        degisikExcel.hucreler.take(2).every((h) => h.fotoVerisi == null),
        isTrue,
      );
      await BireyselImportService.ortakFotograflariKaydet(preview, {
        preview.kayitlar.single.id,
      });
      expect(
        (await db.query('OgrenciFotograf')).single['OgrenciId'],
        guvenliId,
      );
    },
  );

  test(
    'Kayıtlı listede sayısal aynı numara iki öğrencideyse fotoğraf yanlış kimliğe yazılmaz',
    () async {
      await kayitliOgrenci(0, '9-C');
      await kayitliOgrenci(0, '9-D', okulNo: '00${excel.hucreler[0].okulNo}');
      final guvenliId = await kayitliOgrenci(2, '10-D');
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isEmpty);
      expect(preview.kayitlar, hasLength(1));
      await BireyselImportService.ortakFotograflariKaydet(preview, {
        preview.kayitlar.single.id,
      });
      expect(
        (await db.query('OgrenciFotograf')).single['OgrenciId'],
        guvenliId,
      );
      expect(await ogrenciTablolari(), once);
      final manual = await BireyselImportService.ortakFotoOzelOku(
        dosya,
        sinifHucreleri: {excel.hucreler[0].id: '9-C'},
      );
      expect(manual.engeller, isNotEmpty);
    },
  );

  test(
    'Aynı öğrenci iki güncel sınıfa üyeyse numara eşleşmesi belirsiz kalır',
    () async {
      final ilk = await kayitliOgrenci(0, '9-C');
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': ilk,
        'SinifSubeId': 2,
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
      final guvenliId = await kayitliOgrenci(2, '10-D');
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isEmpty);
      expect(
        (preview.veri! as BireyselFotoOnIzleme).kayitlar.single.ogrenciId,
        guvenliId,
      );
    },
  );

  test(
    'Kullanıcının onayladığı ek sınıfın öğrencisiyle de otomatik fotoğraf eşleşir',
    () async {
      final h = excel.hucreler[0];
      final ogrenciPreview =
          await BireyselImportService.ortakOgrenciTumSinifOnIzlemeHazirla([
            ImportKaynakSatiri('ek', 'Test satırı', {
              'okulNo': h.okulNo,
              'ad': h.ad,
              'soyad': h.soyad,
              'sinif': '9-Z',
            }),
          ]);
      await BireyselImportService.ortakOgrencileriKaydet(
        ogrenciPreview,
        {},
        ekSiniflar: {'9-Z'},
      );
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isEmpty);
      expect(preview.kayitlar.single.degerler['sinif'], '9-Z');
      expect(
        await BireyselImportService.fotoImportSiniflariniGetir(),
        contains('9-Z'),
      );
      expect(
        (await BireyselImportService.ortakFotograflariKaydet(preview, {
          preview.kayitlar.single.id,
        })).eklenen,
        1,
      );
      expect(await ogrenciTablolari(), once);
    },
  );

  test(
    'Ek sınıf izni ön izlemeden sonra kaldırılırsa fotoğraf kaydedilemez',
    () async {
      final h = excel.hucreler[0];
      final p = await BireyselImportService.ortakOgrenciTumSinifOnIzlemeHazirla(
        [
          ImportKaynakSatiri('ek', 'Test satırı', {
            'okulNo': h.okulNo,
            'ad': h.ad,
            'soyad': h.soyad,
            'sinif': '9-Z',
          }),
        ],
      );
      await BireyselImportService.ortakOgrencileriKaydet(
        p,
        {},
        ekSiniflar: {'9-Z'},
      );
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      expect(preview.engeller, isEmpty);
      await db.delete('UygulamaAyarlari');
      final once = await ogrenciTablolari();
      await expectLater(
        BireyselImportService.ortakFotograflariKaydet(preview, {
          preview.kayitlar.single.id,
        }),
        throwsStateError,
      );
      expect(await db.query('OgrenciFotograf'), isEmpty);
      expect(await ogrenciTablolari(), once);
    },
  );

  test(
    'Elle sınıf seçenekleri yalnız kapsamda mevcut aktif öğrencisi olan sınıflardır',
    () async {
      await expectLater(
        BireyselImportService.fotoImportSiniflariniGetir(),
        throwsStateError,
      );
      await kayitliOgrenci(0, '9-C');
      await kayitliOgrenci(1, '9-D');
      await kayitliOgrenci(2, '10-D', uyelikAktif: false);
      await kayitliOgrenci(3, '9-Z');
      expect(await BireyselImportService.fotoImportSiniflariniGetir(), [
        '9-C',
        '9-D',
      ]);
      await db.update('DersProgrami', {'Aktif': 0}, where: 'SinifSubeId = 1');
      expect(await BireyselImportService.fotoImportSiniflariniGetir(), ['9-D']);
      SharedPreferences.setMockInitialValues({'calisma_modu': 'okul'});
      await expectLater(
        BireyselImportService.fotoImportSiniflariniGetir(),
        throwsStateError,
      );
    },
  );

  test(
    'Mevcut fotoğraf güncellenir; ikinci öğrenci veya üyelik eklenmez',
    () async {
      final id = await kayitliOgrenci(0, '9-C');
      await db.insert('OgrenciFotograf', {
        'OgrenciId': id,
        'DosyaYolu': 'eski.jpg',
        'FotoVerisi': Uint8List.fromList([1, 2, 3]),
        'Aktif': 0,
        'OlusturmaTarihi': 'eski',
      });
      final once = await ogrenciTablolari();
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      final result = await BireyselImportService.ortakFotograflariKaydet(
        preview,
        {preview.kayitlar.single.id},
      );
      expect(result.eklenen, 0);
      expect(result.guncellenen, 1);
      final foto = (await db.query('OgrenciFotograf')).single;
      expect(foto['OgrenciId'], id);
      expect(foto['Aktif'], 1);
      expect(foto['FotoVerisi'], orderedEquals(excel.hucreler[0].fotoVerisi!));
      expect(await ogrenciTablolari(), once);
    },
  );

  test(
    'Fotoğraf ve mevcut öğrenci ön izleme bilgileri dışarıdan değiştirilemez',
    () async {
      await kayitliOgrenci(0, '9-C');
      final p = await BireyselImportService.fotoOnIzlemeHazirla(
        dosyaAdi: dosya.ad,
        dosyaBytes: dosya.bytes,
      );
      expect(p.kaydedilebilir, isTrue);
      expect(() => p.ogrenciKayitlari.clear(), throwsUnsupportedError);
      expect(
        () => p.ogrenciKayitlari.single['ad'] = 'Değiştirildi',
        throwsUnsupportedError,
      );
      expect(() => p.kayitlar.clear(), throwsUnsupportedError);
      expect(() => p.kayitlar.single.fotoVerisi[0] = 0, throwsUnsupportedError);
    },
  );

  final degisimler = <String, Future<void> Function(int)>{
    'öğrenci adı': (id) async {
      await db.update(
        'Ogrenci',
        {'Ad': 'Değişmiş Ad'},
        where: 'OgrenciId = ?',
        whereArgs: [id],
      );
    },
    'öğrenci numarası': (id) async {
      await db.update(
        'Ogrenci',
        {'OkulNo': '999999'},
        where: 'OgrenciId = ?',
        whereArgs: [id],
      );
    },
    'öğrencinin aktifliği': (id) async {
      await db.update(
        'Ogrenci',
        {'Aktif': 0},
        where: 'OgrenciId = ?',
        whereArgs: [id],
      );
    },
    'sınıf üyeliği': (id) async {
      await db.update(
        'OgrenciSinifKayit',
        {'SinifSubeId': 2},
        where: 'OgrenciId = ?',
        whereArgs: [id],
      );
    },
    'sınıf üyeliğinin aktifliği': (id) async {
      await db.update(
        'OgrenciSinifKayit',
        {'Aktif': 0},
        where: 'OgrenciId = ?',
        whereArgs: [id],
      );
    },
    'ders programı kapsamı': (_) async {
      await db.update('DersProgrami', {'Aktif': 0}, where: 'SinifSubeId = 1');
    },
    'eğitim yılı': (_) async {
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
    },
    'öğretmen profili': (_) async {
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Başka Öğretmen',
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
    },
    'çalışma modu': (_) async {
      SharedPreferences.setMockInitialValues({'calisma_modu': 'okul'});
    },
  };
  for (final degisim in degisimler.entries) {
    test(
      'Ön izlemeden sonra ${degisim.key} değişirse fotoğraf kaydı reddedilir',
      () async {
        final id = await kayitliOgrenci(0, '9-C');
        final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
        expect(preview.engeller, isEmpty);
        await degisim.value(id);
        final once = await ogrenciTablolari();
        await expectLater(
          BireyselImportService.ortakFotograflariKaydet(preview, {
            preview.kayitlar.single.id,
          }),
          throwsStateError,
        );
        expect(await db.query('OgrenciFotograf'), isEmpty);
        expect(await ogrenciTablolari(), once);
      },
    );
  }

  test(
    'İkinci fotoğrafta veritabanı hatası olursa ilk fotoğraf da geri alınır',
    () async {
      await kayitliOgrenci(0, '9-C');
      final ikinci = await kayitliOgrenci(1, '9-D');
      final preview = await BireyselImportService.ortakFotoOzelOku(dosya);
      final once = await ogrenciTablolari();
      await db.execute(
        "CREATE TRIGGER foto_test_hata BEFORE INSERT ON OgrenciFotograf WHEN NEW.OgrenciId = $ikinci BEGIN SELECT RAISE(ABORT, 'foto test hatası'); END",
      );
      try {
        await expectLater(
          BireyselImportService.ortakFotograflariKaydet(
            preview,
            preview.kayitlar.map((r) => r.id).toSet(),
          ),
          throwsStateError,
        );
        expect(await db.query('OgrenciFotograf'), isEmpty);
        expect(await ogrenciTablolari(), once);
      } finally {
        await db.execute('DROP TRIGGER foto_test_hata');
      }
    },
  );

  const tumSiniflarXls = String.fromEnvironment('IMPORT_ALL_CLASSES_XLS');
  test(
    'Gerçek e-Okul dosyasındaki geçersiz satır dışarıda kalırken altı program sınıfı alınır',
    () async {
      final file = ImportDosya(
        'TUMSINIFLAR.XLS',
        File(tumSiniflarXls).readAsBytesSync(),
      );
      final preview = await OgrenciImportTanimi.tanim.ozelOku!(file);
      expect(preview.engeller, isEmpty);
      // Dosya sonundaki öğrenci numarası olmayan metin gizlenmez; hatalı
      // bölüm kaydı gösterilir ve geçerli öğrencilerin seçimine karışmaz.
      final hatali = preview.kayitlar
          .where((k) => k.durum == ImportDurumu.hatali)
          .toList();
      expect(hatali, hasLength(1));
      expect(hatali.single.id, startsWith('bolum-hatasi:'));
      expect(hatali.single.aktarilabilir, isFalse);
      final normal = preview.kayitlar.where((k) => k.aktarilabilir).toList();
      expect(normal, hasLength(149));
      final ekSiniflar = BireyselImportService.ogrenciEkSinifOzeti(preview);
      expect(ekSiniflar, hasLength(19));
      expect(ekSiniflar.keys.any(siniflar.contains), isFalse);
      expect(
        preview.kayitlar
            .where((k) => !k.aktarilabilir && k.durum != ImportDurumu.hatali)
            .every((k) => k.durum == ImportDurumu.atlanan),
        isTrue,
      );
      final counts = <String, int>{};
      for (final row in normal) {
        final sinif = row.degerler['sinif']!;
        counts[sinif] = (counts[sinif] ?? 0) + 1;
        expect({'Kız', 'Erkek'}, contains(row.degerler['cinsiyet']));
      }
      expect(counts, {
        '9-C': 24,
        '9-D': 32,
        '10-D': 29,
        '11-C': 25,
        '11-D': 17,
        '12-D': 22,
      });
      expect(await db.query('Ogrenci'), isEmpty);
      final result = await OgrenciImportTanimi.tanim.aktar(
        preview,
        normal.map((k) => k.id).toSet(),
      );
      expect(result.eklenen, 149);
      expect(result.hatali, 1);
      expect(await db.query('Ogrenci'), hasLength(149));
      expect(await db.query('OgrenciSinifKayit'), hasLength(149));
    },
    skip: tumSiniflarXls.isEmpty,
  );
}
