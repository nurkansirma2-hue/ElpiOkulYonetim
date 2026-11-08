import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/bireysel_belge.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/services/ders_belgeleri_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory alan;
  late BireyselBelgeService belgeler;
  late DersBelgeleriService service;
  var mod = CalismaModu.bireyselOgretmen;
  final bytes = Uint8List.fromList(utf8.encode('Özgün şablon'));

  Future<void> planEkle(int dersId, int seviye, String yil) async {
    final id = await db.insert('YillikPlan', {
      'DersId': dersId,
      'SinifSeviyesi': seviye,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': id,
      'HaftaNo': 1,
      'TarihAraligi': '7-11 Eylül',
      'Konu': 'Korunacak konu',
      'OlusturmaTarihi': 'test',
    });
  }

  Future<void> bagla(
    ImportDosya dosya, {
    int ders = 1,
    int seviye = 11,
    String yil = '2026/2027',
  }) => service.yillikKaynakKaydet(
    profilId: 1,
    egitimYili: yil,
    dersId: ders,
    seviye: seviye,
    dosya: dosya,
  );

  Future<List<Map<String, Object?>>> baglar() =>
      db.query('UygulamaAyarlari', where: "Anahtar LIKE 'ders.yillik.v1.%'");

  Future<BireyselBelge> belgeEkle() async {
    final arsiv = (await belgeler.arsivleriGetir()).aktif;
    return (await belgeler.ekle(
      arsivId: arsiv.id,
      dosya: PlatformFile(name: 'kaynak.txt', size: bytes.length, bytes: bytes),
    )).belge;
  }

  Future<ImportDosya> sec(BireyselBelge belge) async => ImportDosya(
    belge.dosyaAdi,
    bytes,
    belgeKaynagi: await belgeler.importKaynaginiGetir(belge),
  );

  setUp(() async {
    mod = CalismaModu.bireyselOgretmen;
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    alan = await Directory.systemTemp.createTemp('ders_kaynak_test_');
    belgeler = BireyselBelgeService(
      databaseGetir: () async => db,
      alanGetir: () async => alan,
      geciciAlanGetir: () async => alan,
      modGetir: () async => mod,
    );
    service = DersBelgeleriService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
      belgeService: belgeler,
    );
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'Okul',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'OgretmenProfilId': 1,
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    for (var id = 1; id <= 2; id++) {
      await db.insert('Ders', {
        'DersId': id,
        'DersAdi': 'Ders $id',
        'OlusturmaTarihi': 'test',
      });
    }
    await planEkle(1, 11, '2026-2027');
    await planEkle(2, 11, '2026-2027');
    await planEkle(1, 12, '2026-2027');
  });

  tearDown(() async {
    await LocalDatabase.instance.close();
    await alan.delete(recursive: true);
  });

  test(
    'Aynı dosya ders ve seviyelere tek kopyayla bağlanır; tekrar idempotent',
    () async {
      final belge = await belgeEkle();
      await belgeler.belgeyiDuzenle(
        belge,
        tur: 'Genel belge',
        ad: 'Özel ad.txt',
      );
      final once = await db.query('BireyselBelge');
      final planlar = await db.query('YillikPlanDetay');
      final dosya = await sec(belge);
      await bagla(dosya);
      await bagla(dosya, ders: 2);
      await bagla(dosya, seviye: 12);
      await bagla(dosya);
      expect(await db.query('BireyselBelge'), once);
      expect(await db.query('YillikPlanDetay'), planlar);
      expect(await baglar(), hasLength(3));
      for (final r in await baglar()) {
        expect(jsonDecode(r['Deger'] as String)['belgeId'], belge.id);
      }
      final gruplar = await service.getir();
      expect(gruplar, hasLength(3));
      expect(gruplar.every((g) => g.yillikBelgeId == belge.id), isTrue);
      final files = await Directory(
        '${alan.path}/bireysel_belgeler',
      ).list(recursive: true).where((e) => e is File).toList();
      expect(files, hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'Başka adla cihazdan aynı içerik mevcut türü ve dosyayı korur',
    () async {
      final belge = await belgeEkle();
      await belgeler.belgeyiDuzenle(belge, tur: 'Ders bilgi formu');
      final once = await db.query('BireyselBelge');
      await bagla(ImportDosya('baska_ad.txt', bytes));
      expect(await db.query('BireyselBelge'), once);
      expect(
        jsonDecode((await baglar()).single['Deger'] as String)['belgeId'],
        belge.id,
      );
    },
  );

  test(
    'Yeni yılda aynı belge kullanılır; eski yıl bağı ve kayıt yılı korunur',
    () async {
      final belge = await belgeEkle();
      await bagla(await sec(belge));
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
      await planEkle(1, 11, '2027-2028');
      await bagla(await sec(belge), yil: '2027-2028');
      expect(await baglar(), hasLength(2));
      expect(
        (await db.query('BireyselBelge')).single['EgitimOgretimYili'],
        '2026/2027',
      );
      final g = (await service.getir()).single;
      expect(g.egitimYili, '2027/2028');
      expect(g.yillikBelgeId, belge.id);
    },
  );

  test(
    'Silinen belge yeniden oluşturulmaz ve bağlantı olarak sunulmaz',
    () async {
      final belge = await belgeEkle();
      final dosya = await sec(belge);
      await bagla(dosya);
      final once = await baglar();
      await belgeler.belgeyiDuzenle(belge, sil: true);
      await expectLater(bagla(dosya, ders: 2), throwsStateError);
      expect(await baglar(), once);
      expect(
        (await db.query('BireyselBelge')).single['SilinmeTarihi'],
        isNotNull,
      );
      expect(
        (await service.getir()).every((g) => g.yillikBelgeId == null),
        isTrue,
      );
    },
  );

  test('Seçim içeriği arşivle uyuşmuyorsa mevcut bağlantı korunur', () async {
    final belge = await belgeEkle();
    final dosya = await sec(belge);
    await bagla(dosya);
    final once = await baglar();
    await expectLater(
      bagla(
        ImportDosya(
          'kaynak.txt',
          Uint8List.fromList([1, 2]),
          belgeKaynagi: dosya.belgeKaynagi,
        ),
      ),
      throwsStateError,
    );
    expect(await baglar(), once);
    expect(await db.query('BireyselBelge'), hasLength(1));
  });

  test(
    'Okul değişimi, eski seçim yılı, geçersiz hedef ve mod geçişi engellenir',
    () async {
      final belge = await belgeEkle();
      final dosya = await sec(belge);
      await expectLater(bagla(dosya, ders: 999), throwsStateError);
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
      await planEkle(1, 11, '2027-2028');
      await expectLater(bagla(dosya, yil: '2027/2028'), throwsStateError);
      await db.update('OkulProfil', {'OkulId': 'okul-2'});
      await expectLater(
        bagla(
          ImportDosya(
            'kaynak.txt',
            bytes,
            belgeKaynagi: const BelgeImportKaynagi(
              'yanlis-arsiv',
              'belge',
              '2027/2028',
            ),
          ),
          yil: '2027/2028',
        ),
        throwsStateError,
      );
      // Kurumsal moda geçince SQLite kaydı yapılmamalı.
      mod = CalismaModu.values.firstWhere(
        (m) => m != CalismaModu.bireyselOgretmen,
      );
      await expectLater(bagla(dosya), throwsStateError);
      expect(await baglar(), isEmpty);
    },
  );
}
