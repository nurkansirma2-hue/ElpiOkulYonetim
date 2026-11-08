import 'dart:io';

import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_ders_programi_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_yillik_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Tarih uçları ve yıl geçişinde tüm geçerli detaylar korunur', () {
    final icerik = BireyselYillikPlanIcerigi(
      yillikPlanId: 1,
      detaylar: [
        {
          'YillikPlanDetayId': 1,
          'BaslangicTarihi': '2026-12-28',
          'BitisTarihi': '2027-01-08',
        },
        {
          'YillikPlanDetayId': 2,
          'BaslangicTarihi': '2027-01-01',
          'BitisTarihi': '2027-01-08',
        },
      ],
    );
    expect(icerik.tariheAitDetaylar(DateTime(2026, 12, 27)), isEmpty);
    expect(icerik.tariheAitDetaylar(DateTime(2026, 12, 28)), hasLength(1));
    expect(icerik.tariheAitDetaylar(DateTime(2027, 1, 1)), hasLength(2));
    expect(
      icerik.tariheAitDetaylar(DateTime(2027, 1, 8, 23, 59)),
      hasLength(2),
    );
    expect(icerik.tariheAitDetaylar(DateTime(2027, 1, 9)), isEmpty);
    expect(icerik.tarihsizDetayVar, isFalse);
  });

  test(
    'Tarihsiz, geçersiz ve ters aralıklı detaylardan hafta tahmin edilmez',
    () {
      final icerik = BireyselYillikPlanIcerigi(
        yillikPlanId: 1,
        detaylar: [
          {'HaftaNo': 1, 'TarihAraligi': '12-16 Ekim'},
          {'BaslangicTarihi': '2026-02-30', 'BitisTarihi': '2026-03-06'},
          {'BaslangicTarihi': '2026-10-16', 'BitisTarihi': '2026-10-12'},
          {
            'BaslangicTarihi': '2026-10-12T00:00:00',
            'BitisTarihi': '2026-10-16',
          },
          {'BaslangicTarihi': '2026-10-12'},
        ],
      );
      expect(icerik.tariheAitDetaylar(DateTime(2026, 10, 12)), isEmpty);
      expect(icerik.tariheAitDetaylar(DateTime(2026, 3, 2)), isEmpty);
      expect(icerik.tarihsizDetayVar, isTrue);
      expect(icerik.detaylar, hasLength(5));
    },
  );

  group('Bireysel haftalık kazanım salt okunur servisi', () {
    late Database db;
    final factory = WindowsMemoryFactory();
    const hamYil = '2026 / 2027';
    const planYili = '2026-2027';
    final pazartesi = DateTime(2026, 10, 12);

    Future<BireyselYillikPlanIcerigi> oku({
      int profil = 1,
      String yil = hamYil,
      int ders = 1,
      int seviye = 9,
    }) => BireyselYillikPlanService.icerigiGetir(
      ogretmenProfilId: profil,
      egitimOgretimYili: yil,
      dersId: ders,
      sinifSeviyesi: seviye,
    );

    Future<int> programEkle({
      int profil = 1,
      String yil = hamYil,
      int ders = 1,
      int seviye = 9,
      String baslangic = '2026-09-01',
      String? bitis,
      int surumAktif = 1,
    }) async {
      if ((await db.query(
        'Ders',
        where: 'DersId = ?',
        whereArgs: [ders],
      )).isEmpty) {
        await db.insert('Ders', {
          'DersId': ders,
          'DersAdi': ders == 1 ? 'Matematik' : 'Fizik',
          'OlusturmaTarihi': 'test',
        });
      }
      final sinif = await db.insert('SinifSube', {
        'SinifKodu': '$seviye-$profil-$ders-$baslangic',
        'SinifSeviyesi': seviye,
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
      final surum = await db.insert('DersProgramiSurum', {
        'OgretmenProfilId': profil,
        'EgitimOgretimYili': yil,
        'BaslangicTarihi': baslangic,
        'BitisTarihi': bitis,
        'Aktif': surumAktif,
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'ProgramSurumId': surum,
        'SinifSubeId': sinif,
        'DersId': ders,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'Baslangic': '08:00',
        'Bitis': '08:40',
        'OgretmenProfilId': profil,
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
      return surum;
    }

    Future<int> planEkle({
      int profil = 1,
      String yil = planYili,
      int ders = 1,
      int seviye = 9,
      bool aktif = true,
    }) => db.insert('YillikPlan', {
      'OgretmenProfilId': profil,
      'EgitimOgretimYili': yil,
      'DersId': ders,
      'SinifSeviyesi': seviye,
      'Aktif': aktif ? 1 : 0,
      'OlusturmaTarihi': 'test',
    });

    Future<void> detayEkle(
      int plan,
      String konu, {
      String? baslangic = '2026-10-12',
      String? bitis = '2026-10-16',
      int hafta = 6,
      int aktif = 1,
      String? icerik,
    }) async {
      await db.insert('YillikPlanDetay', {
        'YillikPlanId': plan,
        'HaftaNo': hafta,
        'BaslangicTarihi': baslangic,
        'BitisTarihi': bitis,
        'Konu': konu,
        'IcerikCercevesi': icerik,
        'Kazanim': 'Kazanım $konu',
        'Aktif': aktif,
        'OlusturmaTarihi': 'test',
      });
    }

    Future<Map<String, List<Map<String, Object?>>>> anlikGoruntu() async {
      final tablolar = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      return {
        for (final tablo in tablolar)
          tablo['name'] as String: await db.query(tablo['name'] as String),
      };
    }

    setUpAll(() async {
      databaseFactory = factory;
      db = await LocalDatabase.instance.database;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      for (final tablo in [
        'YillikPlanDetay',
        'YillikPlan',
        'CalismaTakvimiDetay',
        'CalismaTakvimi',
        'DersProgramiGorev',
        'DersProgrami',
        'DersProgramiSurum',
        'DersSinif',
        'SinifSube',
        'Ders',
        'DersSaati',
        'OgretmenProfil',
      ]) {
        await db.delete(tablo);
      }
      for (var id = 1; id <= 2; id++) {
        await db.insert('OgretmenProfil', {
          'OgretmenProfilId': id,
          'AdSoyad': 'Öğretmen $id',
          'EgitimOgretimYili': hamYil,
          'Aktif': id == 1 ? 1 : 0,
          'OlusturmaTarihi': 'test',
        });
      }
      await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    });

    tearDownAll(() async {
      await factory.db?.close();
    });

    test(
      'Son aktif plan seçilir; yıl, profil, ders ve seviye karışmaz',
      () async {
        await programEkle();
        await programEkle(ders: 2);
        final eski = await planEkle();
        await detayEkle(eski, 'Eski konu');
        final guncel = await planEkle(yil: hamYil);
        await detayEkle(guncel, 'Birinci konu');
        await detayEkle(guncel, 'İkinci konu');
        await detayEkle(guncel, 'Pasif detay', aktif: 0);
        for (final plan in [
          await planEkle(aktif: false),
          await planEkle(profil: 2),
          await planEkle(yil: '2025-2026'),
          await planEkle(seviye: 10),
          await planEkle(ders: 2),
        ]) {
          await detayEkle(plan, 'Kapsam dışı');
        }
        final icerik = await oku(yil: planYili);
        expect(icerik.yillikPlanId, guncel);
        expect(icerik.tariheAitDetaylar(pazartesi).map((d) => d['Konu']), [
          'Birinci konu',
          'İkinci konu',
        ]);
        expect(icerik.detaylar, hasLength(2));
      },
    );

    test(
      'Plan yok, boş son plan ve tarihsiz plan birbirinden ayrılır',
      () async {
        await programEkle();
        expect((await oku()).yillikPlanId, isNull);
        final eski = await planEkle();
        await detayEkle(eski, 'Eski konu');
        final bos = await planEkle();
        final icerik = await oku();
        expect(icerik.yillikPlanId, bos);
        expect(icerik.detaylar, isEmpty);
        expect(icerik.tarihsizDetayVar, isFalse);
        final bugun = await BireyselDersProgramiService.bugununDurumunuGetir(
          ogretmenProfilId: 1,
          egitimOgretimYili: hamYil,
          tarih: pazartesi,
        );
        expect(bugun.dersler.single.konu, isEmpty);
        await detayEkle(bos, 'Tarihsiz konu', baslangic: null, bitis: null);
        final tarihsiz = await oku();
        expect(tarihsiz.detaylar, hasLength(1));
        expect(tarihsiz.tariheAitDetaylar(pazartesi), isEmpty);
        expect(tarihsiz.tarihsizDetayVar, isTrue);
      },
    );

    test(
      'Aktif profil, eğitim yılı, bireysel mod ve ders kapsamı doğrulanır',
      () async {
        await programEkle();
        await expectLater(oku(profil: 2), throwsException);
        await expectLater(oku(yil: '2025-2026'), throwsException);
        await expectLater(oku(seviye: 10), throwsException);
        await expectLater(oku(ders: 2), throwsException);
        SharedPreferences.setMockInitialValues({'calisma_modu': 'okul'});
        await expectLater(oku(), throwsStateError);
      },
    );

    test('Bugünkü programda kalmayan tarihsel dersin planı okunur', () async {
      await programEkle(bitis: '2026-09-30');
      final plan = await planEkle();
      await detayEkle(
        plan,
        'Tarihsel konu',
        baslangic: '2026-09-07',
        bitis: '2026-09-11',
        hafta: 1,
      );
      final icerik = await oku();
      expect(icerik.yillikPlanId, plan);
      expect(icerik.tariheAitDetaylar(DateTime(2026, 9, 7)), hasLength(1));
      final bugun = await BireyselDersProgramiService.bugununDurumunuGetir(
        ogretmenProfilId: 1,
        egitimOgretimYili: hamYil,
        tarih: pazartesi,
      );
      expect(bugun.dersler, isEmpty);
    });

    test(
      'Günlük konu kartla aynı son planı, tüm satırları ve yıl biçimini kullanır',
      () async {
        final surum = await programEkle();
        final eski = await planEkle();
        await detayEkle(eski, 'Eski konu');
        final plan = await planEkle();
        await detayEkle(plan, 'Birinci konu');
        await detayEkle(plan, '', icerik: 'İçerik konusu');
        await detayEkle(plan, 'Tarihsiz', baslangic: null, bitis: null);
        await db.insert('DersProgramiGorev', {
          'ProgramSurumId': surum,
          'Gun': 'Pazartesi',
          'DersSaatiNo': 2,
          'Baslangic': '09:00',
          'Bitis': '09:40',
          'GorevAdi': 'Koordinatörlük',
        });
        final takvim = await db.insert('CalismaTakvimi', {
          'OgretmenProfilId': 1,
          'EgitimOgretimYili': planYili,
          'OlusturmaTarihi': 'test',
        });
        for (final calisma in [1, 0]) {
          await db.insert('CalismaTakvimiDetay', {
            'CalismaTakvimiId': takvim,
            'BaslangicTarihi': '2026-10-12',
            'BitisTarihi': '2026-10-16',
            'KayitTuru': calisma == 1 ? 'DersHaftasi' : 'Tatil',
            'CalismaVarMi': calisma,
            'Aciklama': calisma == 1 ? '6. Hafta' : 'Tatil',
            'OlusturmaTarihi': 'test',
          });
        }
        final bugun = await BireyselDersProgramiService.bugununDurumunuGetir(
          ogretmenProfilId: 1,
          egitimOgretimYili: hamYil,
          tarih: pazartesi,
        );
        final icerik = await oku();
        expect(icerik.yillikPlanId, plan);
        expect(icerik.tariheAitDetaylar(pazartesi), hasLength(2));
        expect(bugun.dersler.first.konu, 'Birinci konu\nİçerik konusu');
        expect(bugun.dersler.last.gorevMi, isTrue);
        expect(bugun.dersler.last.konu, isEmpty);
        expect(bugun.calismaTakvimiVarMi, isTrue);
        expect(bugun.tarihTakvimdeVarMi, isTrue);
        expect(bugun.calismaVarMi, isFalse);
        expect(bugun.takvimAciklamasi, 'Tatil');
        final haftaSonu =
            await BireyselDersProgramiService.bugununDurumunuGetir(
              ogretmenProfilId: 1,
              egitimOgretimYili: hamYil,
              tarih: DateTime(2026, 10, 17),
            );
        expect(haftaSonu.haftaSonu, isTrue);
        expect(haftaSonu.dersler, isEmpty);
      },
    );

    test(
      'Kart ve günlük özet açılışı hiçbir SQLite kaydını değiştirmez',
      () async {
        await programEkle();
        final plan = await planEkle();
        await detayEkle(plan, 'Konu');
        final once = await anlikGoruntu();
        final icerik = await oku();
        icerik.tariheAitDetaylar(pazartesi);
        await BireyselDersProgramiService.bugununDurumunuGetir(
          ogretmenProfilId: 1,
          egitimOgretimYili: hamYil,
          tarih: pazartesi,
        );
        expect(await anlikGoruntu(), once);
        expect(() => icerik.detaylar.clear(), throwsUnsupportedError);
        expect(
          () => icerik.detaylar.first['Konu'] = 'Değişiklik',
          throwsUnsupportedError,
        );
      },
    );
  }, skip: !Platform.isWindows);
}
