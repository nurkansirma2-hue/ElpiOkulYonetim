import 'dart:convert';
import 'dart:io';

import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/dbf_belgesi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_dbf_service.dart';
import 'package:elpi_okul_yonetim/services/dbf_kaynak_service.dart';
import 'package:elpi_okul_yonetim/services/ders_belgeleri_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/services/calisma_modu_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_dbf_import_screen.dart';
import 'package:elpi_okul_yonetim/screens/ders_belgeleri_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_gunluk_plan_akisi.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_gunluk_plan_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yillik_plan_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

const dbfMetni =
    'DERS BİLGİ FORMU\nDERSİN ADI BİLGİSAYARLI TASARIM UYGULAMALARI\n'
    'DERSİN SINIFI 9. Sınıf\nDERSİN SÜRESİ Haftalık 2 Ders Saati\n'
    'ÖĞRENME ÇIKTILARI\nTeknik resim uygulamaları yapabilme';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;
  late BireyselDbfService service;

  DbfBelgesi belge() => DbfBelgesi.metinden(
    dosyaAdi: 'DBF.pdf',
    sayfalar: [dbfMetni],
    icerikOzeti: 'crc32:test',
  );
  Future<DbfBelgesi?> getir({int profil = 1, String yil = '2026-2027'}) =>
      service.getir(
        profilId: profil,
        egitimYili: yil,
        dersId: 1,
        sinifSeviyesi: 9,
      );
  Future<DbfBelgesi> kaydet({DbfBelgesi? aday, int surum = 0}) =>
      service.kaydet(
        profilId: 1,
        egitimYili: '2026-2027',
        dersId: 1,
        sinifSeviyesi: 9,
        belge: aday ?? belge(),
        beklenenSurum: surum,
        kaynakAdresi: DbfKaynakService.varsayilanAdres,
        programSurumu: '2026',
      );

  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    mod = CalismaModu.bireyselOgretmen;
    service = BireyselDbfService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
    );
    SharedPreferences.setMockInitialValues({});
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
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
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Bilgisayarlı Tasarım Uygulamaları',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-A',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    await db.insert('DersProgrami', {
      'DersProgramiId': 1,
      'DersId': 1,
      'SinifSubeId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
  });
  tearDown(() => LocalDatabase.instance.close());

  Future<void> planEkle() async {
    final id = await db.insert('YillikPlan', {
      'OgretmenProfilId': 1,
      'DersId': 1,
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': id,
      'HaftaNo': 7,
      'BaslangicTarihi': '2026-10-12',
      'BitisTarihi': '2026-10-16',
      'Konu': 'Teknik çizim',
      'OlusturmaTarihi': 'test',
    });
  }

  Future<void> akisiAc(WidgetTester tester) async {
    await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => bireyselGunlukPlanAc(
                context,
                ogretmenProfilId: 1,
                egitimOgretimYili: '2026-2027',
                dersId: 1,
                dersAdi: 'Bilgisayarlı Tasarım Uygulamaları',
                sinifSeviyesi: 9,
                tarih: DateTime(2026, 10, 12),
                baslangicSinifKodu: '9-A',
              ),
              child: const Text('Günlük Plan'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Günlük Plan'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Yıllık plan eksikse ilgili dersin importunu açar; iptalde durur',
    (tester) async {
      await akisiAc(tester);
      final ekran = tester.widget<BireyselYillikPlanImportScreen>(
        find.byType(BireyselYillikPlanImportScreen),
      );
      expect(ekran.baslangicDersId, 1);
      expect(ekran.baslangicSinifSeviyesi, 9);
      expect(ekran.kaydedinceDon, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(BireyselDbfImportScreen), findsNothing);
      expect(find.byType(BireyselGunlukPlanScreen), findsNothing);
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
    },
  );

  testWidgets(
    'DBF eksikse yükleme açılır; kaydedilen kaynakla aynı tarihe devam eder',
    (tester) async {
      await planEkle();
      await akisiAc(tester);
      final ekran = tester.widget<BireyselDbfImportScreen>(
        find.byType(BireyselDbfImportScreen),
      );
      expect(ekran.kaydedinceDon, isTrue);
      await kaydet();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final plan = tester.widget<BireyselGunlukPlanScreen>(
        find.byType(BireyselGunlukPlanScreen),
      );
      expect(plan.dersId, 1);
      expect(plan.tarih, DateTime(2026, 10, 12));
      expect(plan.baslangicSinifKodu, '9-A');
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Belgeler kayıtlıysa import açmadan doğrudan günlük plana gider',
    (tester) async {
      await planEkle();
      await kaydet();
      await akisiAc(tester);
      expect(find.byType(BireyselGunlukPlanScreen), findsOneWidget);
      expect(find.byType(BireyselDbfImportScreen), findsNothing);
      expect(find.byType(BireyselYillikPlanImportScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Günlük plandan çağrılan DBF importu onaylı kayıttan sonra geri döner',
    (tester) async {
      await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => BireyselDbfImportScreen(
                      profilId: 1,
                      egitimYili: '2026-2027',
                      dersId: 1,
                      dersAdi: 'Bilgisayarlı Tasarım Uygulamaları',
                      sinifSeviyesi: 9,
                      kaydedinceDon: true,
                      dosyaSec: (_) async => belge(),
                    ),
                  ),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İndirilen Dosyayı Yükle'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), '2026');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Onayla ve Kaydet'));
      await tester.tap(find.text('Onayla ve Kaydet'));
      await tester.pumpAndSettle();
      expect(find.byType(BireyselDbfImportScreen), findsNothing);
      expect((await getir())!.surum, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Onaylı kaynak PDF Belgelerim arşivine kopyalanır ve bağlantı korunur',
    () async {
      final alan = await Directory.systemTemp.createTemp('dbf_test_');
      try {
        final belgeler = BireyselBelgeService(
          databaseGetir: () async => db,
          alanGetir: () async => alan,
          geciciAlanGetir: () async => alan,
          modGetir: () async => mod,
        );
        service = BireyselDbfService(
          databaseGetir: () async => db,
          modGetir: () async => mod,
          belgeService: belgeler,
        );
        final bytes = await File('test/fixtures/dbf/meb_dbf.pdf').readAsBytes();
        final kaynak = DbfBelgesi.metinden(
          dosyaAdi: 'DBF.pdf',
          sayfalar: [dbfMetni],
          icerikOzeti:
              'crc32:${getCrc32(bytes).toRadixString(16).padLeft(8, '0')}',
          pdfBytes: bytes,
        );
        final sonuc = await kaydet(aday: kaynak);
        final dosya = await belgeler.dosyaYolunuGetir(
          arsivId: sonuc.arsivId!,
          belgeId: sonuc.belgeId!,
        );
        expect(await File(dosya).readAsBytes(), bytes);
        expect((await getir())!.belgeId, sonuc.belgeId);
        final belgeKaydi = await belgeler.belgeGetir(
          sonuc.arsivId!,
          sonuc.belgeId!,
        );
        expect(belgeKaydi.belgeTuru, 'Ders bilgi formu');
      } finally {
        // Yalnız bu testin oluşturduğu geçici alan temizlenir.
        await alan.delete(recursive: true);
      }
    },
  );

  testWidgets('Kayıtlı DBF dar ekranda açılırken yeniden dosya istemez', (
    tester,
  ) async {
    await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
    await kaydet();
    var secimSayisi = 0;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: BireyselDbfImportScreen(
          profilId: 1,
          egitimYili: '2026-2027',
          dersId: 1,
          dersAdi: 'Bilgisayarlı Tasarım Uygulamaları',
          sinifSeviyesi: 9,
          dosyaSec: (_) async {
            secimSayisi++;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(secimSayisi, 0);
    await tester.scrollUntilVisible(
      find.textContaining('Kayıtlı DBF: DBF.pdf'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Kayıtlı DBF: DBF.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ders başlığı altında belgeler istenen sırada gösterilir', (
    tester,
  ) async {
    await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
    await kaydet();
    await tester.pumpWidget(const MaterialApp(home: DersBelgeleriScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bilgisayarlı Tasarım Uygulamaları'));
    await tester.pumpAndSettle();
    final yillik = tester.getTopLeft(find.text('Yıllık Plan')).dy;
    final gunluk = tester.getTopLeft(find.text('Günlük Plan')).dy;
    final dbf = tester.getTopLeft(find.text('Ders Bilgi Formu')).dy;
    expect(yillik, lessThan(gunluk));
    expect(gunluk, lessThan(dbf));
    expect(find.textContaining('DBF.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Belgelerim ders grubu kayıtlı DBF ile aynı kaynağı gösterir', () async {
    final belgeler = DersBelgeleriService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
    );
    final bos = await belgeler.getir();
    expect(bos, hasLength(1));
    expect(bos.single.dbf, isNull);
    await kaydet();
    final gruplar = await belgeler.getir();
    expect(gruplar.single.dersId, 1);
    expect(gruplar.single.sinifSeviyesi, 9);
    expect(gruplar.single.dbf!.sayfalar, [dbfMetni]);
    expect(gruplar.single.yillikPlanVar, isFalse);
    mod = null;
    await expectLater(belgeler.getir(), throwsStateError);
  });

  test(
    'PDF ön izleme salt okunur; onaylı kaynak tekrar açılır ve sürümlenir',
    () async {
      final aday = belge();
      expect(aday.dersAdi, 'BİLGİSAYARLI TASARIM UYGULAMALARI');
      expect(aday.sinifSeviyesi, 9);
      expect(await getir(), isNull);
      expect(await db.query('UygulamaAyarlari'), isEmpty);
      final ilk = await kaydet();
      expect(ilk.surum, 1);
      expect((await getir())!.sayfalar, [dbfMetni]);
      await expectLater(kaydet(), throwsStateError);
      final ikinci = await kaydet(surum: 1);
      expect(ikinci.surum, 2);
      expect(await db.query('UygulamaAyarlari'), hasLength(1));
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
      expect(await db.query('YillikPlan'), isEmpty);
    },
  );

  test('Yanlış ders, sınıf ve günlük plan DBF olarak kaydedilemez', () async {
    for (final metin in [
      dbfMetni.replaceAll('TASARIM UYGULAMALARI', 'ÇİZİM'),
      dbfMetni.replaceAll('9. Sınıf', '10. Sınıf'),
    ]) {
      await expectLater(
        kaydet(
          aday: DbfBelgesi.metinden(
            dosyaAdi: 'yanlis.pdf',
            sayfalar: [metin],
            icerikOzeti: 'test',
          ),
        ),
        throwsStateError,
      );
    }
    expect(
      () => DbfBelgesi.metinden(
        dosyaAdi: 'gunluk.pdf',
        sayfalar: ['GÜNLÜK PLAN'],
        icerikOzeti: 'test',
      ),
      throwsFormatException,
    );
    expect(await db.query('UygulamaAyarlari'), isEmpty);
  });

  test(
    'Kurumsal mod, farklı profil/yıl ve ders kapsamı erişimi engellenir',
    () async {
      await kaydet();
      await expectLater(getir(profil: 2), throwsStateError);
      await expectLater(getir(yil: '2025-2026'), throwsStateError);
      mod = null;
      await expectLater(getir(), throwsStateError);
      await expectLater(kaydet(surum: 1), throwsStateError);
      mod = CalismaModu.bireyselOgretmen;
      await db.update('DersProgrami', {'Aktif': 0});
      await expectLater(getir(), throwsStateError);
      expect(await db.query('UygulamaAyarlari'), hasLength(1));
    },
  );

  test(
    'Kaynak metni yedeklenebilir JSON; bireysel sıfırlama DBF kaydını temizler',
    () async {
      await kaydet();
      final row = (await db.query('UygulamaAyarlari')).single;
      expect(DbfBelgesi.fromJson(jsonDecode(row['Deger'] as String)).sayfalar, [
        dbfMetni,
      ]);
      await LocalDatabase.instance.bireyselVerileriSifirla(
        onayMetni: 'SIFIRLA',
      );
      expect(await db.query('UygulamaAyarlari'), isEmpty);
    },
  );

  test(
    'Kaynak adresi sorgu ve harfleriyle korunur; tehlikeli adres reddedilir',
    () async {
      const adres =
          'https://meslek.meb.gov.tr/dbflistele.aspx?kurum_id=1&sinif_kodu=10';
      await DbfKaynakService.kaydet(adres);
      expect(await DbfKaynakService.getir(), adres);
      for (final s in [
        'file:///a',
        'javascript:alert(1)',
        'https://user:pass@meb.gov.tr',
        'http://meb.gov.tr',
        'https://',
        'https://meb.gov.tr/ a',
      ]) {
        expect(() => DbfKaynakService.dogrula(s), throwsFormatException);
      }
      expect(await DbfKaynakService.getir(), adres);
    },
  );
}
