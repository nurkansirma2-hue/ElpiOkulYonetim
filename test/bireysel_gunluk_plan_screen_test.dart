import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_gunluk_plan_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yillik_planlarim_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';
import 'support/gunluk_plan_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  const yil = '2026/2027';
  final tarih = DateTime(2026, 10, 14);

  Future<void> subeEkle(int id, {bool dersKapsaminda = true}) async {
    await db.insert('SinifSube', {
      'SinifSubeId': id,
      'SinifKodu': '9-${String.fromCharCode(64 + id)}',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    if (dersKapsaminda) {
      await db.insert('DersProgrami', {
        'SinifSubeId': id,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Çarşamba',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
    }
  }

  setUpAll(() async {
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    for (final tablo in [
      'UygulamaAyarlari',
      'BireyselGunlukPlan',
      'YillikPlanDetay',
      'YillikPlan',
      'DersProgrami',
      'SinifSube',
      'Ders',
      'DersSaati',
      'OgretmenProfil',
      'OkulProfil',
    ]) {
      await db.delete(tablo);
    }
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Çınar Okulu',
      'OkulKisaAdi': 'ÇO',
      'EgitimYili': yil,
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'OgretmenProfilId': 1,
      'AdSoyad': 'Ayşe Öğretmen',
      'OkulAdi': 'Çınar Okulu',
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    await subeEkle(1);
    await db.insert('YillikPlan', {
      'YillikPlanId': 1,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'DersId': 1,
      'SinifSeviyesi': 9,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': 1,
      'HaftaNo': 6,
      'Saat': '2',
      'BaslangicTarihi': '2026-10-12',
      'BitisTarihi': '2026-10-16',
      'Konu': 'Denklemler',
      'Kazanim': 'Denklem çözer.',
      'YontemTeknik': 'Soru cevap',
      'AracGerec': 'Çalışma kâğıdı',
      'Degerlendirme': 'Çıkış bileti',
      'OlusturmaTarihi': 'test',
    });
    await gunlukPlanTestDbfEkle(db, ayrintili: false);
  });

  tearDownAll(() => LocalDatabase.instance.close());

  Future<void> tikla(
    WidgetTester tester,
    Finder hedef, {
    double kaydirma = 240,
  }) async {
    if (hedef.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        hedef,
        kaydirma,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(hedef);
    await tester.pumpAndSettle();
    await tester.tap(hedef);
    await tester.pumpAndSettle();
  }

  Finder alan(String ad) => find.byKey(ValueKey('gunluk-plan-$ad'));

  String metin(WidgetTester tester, String ad) =>
      tester.widget<TextFormField>(alan(ad)).controller!.text;

  Future<void> yaz(WidgetTester tester, String ad, String deger) async {
    final hedef = alan(ad);
    if (hedef.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        hedef,
        240,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(hedef);
    await tester.pumpAndSettle();
    await tester.enterText(hedef, deger);
    await tester.pumpAndSettle();
  }

  Future<void> ac(
    WidgetTester tester, {
    bool haftalik = false,
    String sube = '',
    double textScale = 1,
    bool koyu = false,
  }) async {
    final tema = ThemeData(
      brightness: koyu ? Brightness.dark : Brightness.light,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Theme(
          data: tema,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  if (haftalik) {
                    await bireyselHaftalikKazanimAc(
                      context,
                      ogretmenProfilId: 1,
                      egitimOgretimYili: yil,
                      dersId: 1,
                      dersAdi: 'Matematik',
                      sinifSeviyesi: 9,
                      tarih: tarih,
                      sinif: sube,
                    );
                  } else {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => InheritedTheme.captureAll(
                          context,
                          BireyselGunlukPlanScreen(
                            ogretmenProfilId: 1,
                            egitimOgretimYili: yil,
                            dersId: 1,
                            dersAdi: 'Matematik',
                            sinifSeviyesi: 9,
                            tarih: tarih,
                            baslangicSinifKodu: sube,
                          ),
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Haftalık kartın dersi, seçili tarihi, şubesi ve tema günlük ekrana geçer',
    (tester) async {
      await subeEkle(2);
      await ac(tester, haftalik: true, sube: '9-B', koyu: true);
      await tikla(tester, find.byKey(const ValueKey('gunluk-plan-hazirla')));
      expect(find.byType(BireyselGunlukPlanScreen), findsOneWidget);
      expect(find.text('Seçilen tarih: 14.10.2026'), findsOneWidget);
      expect(find.text('Öğretmen: Ayşe Öğretmen'), findsOneWidget);
      expect(find.text('Okul: Çınar Okulu'), findsOneWidget);
      expect(tester.widget<DropdownButton<int>>(alan('sinif')).value, 2);
      expect(metin(tester, 'konu'), 'Denklemler');
      expect(metin(tester, 'kazanim'), 'Denklem çözer.');
      expect(
        Theme.of(tester.element(alan('konu'))).brightness,
        Brightness.dark,
      );
      expect(await db.query('BireyselGunlukPlan'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Şube bilinmiyorsa yalnız ders kapsamındaki şubelerden seçilir', (
    tester,
  ) async {
    await subeEkle(2);
    await subeEkle(3, dersKapsaminda: false);
    await ac(tester);
    expect(alan('konu'), findsNothing);
    final secim = tester.widget<DropdownButton<int>>(alan('sinif'));
    expect(secim.value, isNull);
    expect(secim.items!.map((e) => e.value), [1, 2]);
    await tikla(tester, alan('sinif'));
    await tester.tap(find.text('9-B').last);
    await tester.pumpAndSettle();
    expect(metin(tester, 'yontemTeknik'), 'Soru cevap');
    expect(metin(tester, 'aracGerec'), 'Çalışma kâğıdı');
    expect(metin(tester, 'degerlendirme'), 'Çıkış bileti');
    expect(await db.query('BireyselGunlukPlan'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Kaydet, yeniden aç ve düzenle aynı kaydı korur; kaynak üzerine yazmaz',
    (tester) async {
      await ac(tester);
      await yaz(tester, 'konu', 'Öğretmenin konusu');
      await yaz(tester, 'dersinIslenisi', 'Hatırlatma ve örnek çözümü.');
      await yaz(tester, 'etkinlikler', 'İkili çalışma.');
      await tikla(tester, alan('kaydet'));
      final id = (await db.query('BireyselGunlukPlan')).single['GunlukPlanId'];
      await tester.pageBack();
      await tester.pumpAndSettle();
      await db.update('YillikPlanDetay', {'Konu': 'Yeni import konusu'});
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      expect(metin(tester, 'konu'), 'Öğretmenin konusu');
      expect(metin(tester, 'etkinlikler'), 'İkili çalışma.');
      await yaz(tester, 'etkinlikler', 'Düzenlenmiş etkinlik.');
      await tikla(tester, alan('kaydet'));
      await tikla(tester, alan('kaydet'));
      final kayitlar = await db.query('BireyselGunlukPlan');
      expect(kayitlar, hasLength(1));
      expect(kayitlar.single['GunlukPlanId'], id);
      expect(kayitlar.single['Etkinlikler'], 'Düzenlenmiş etkinlik.');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Kaydedilmemiş yazılar geri çıkışta korunur veya kaydedilerek çıkılır',
    (tester) async {
      await ac(tester);
      await yaz(tester, 'etkinlikler', 'Kaybolmaması gereken yazı');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      await tester.tap(find.text('Ekranda kal'));
      await tester.pumpAndSettle();
      expect(metin(tester, 'etkinlikler'), 'Kaybolmaması gereken yazı');
      expect(await db.query('BireyselGunlukPlan'), hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet ve devam et'));
      await tester.pumpAndSettle();
      expect(find.byType(BireyselGunlukPlanScreen), findsNothing);
      expect(
        (await db.query('BireyselGunlukPlan')).single['Etkinlikler'],
        'Kaybolmaması gereken yazı',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Şube değiştirirken vazgeçme yazıları korur; onaylanan değişim ayrı taslağı açar',
    (tester) async {
      await subeEkle(2);
      await ac(tester, sube: '9-A');
      await yaz(tester, 'konu', '9-A özel konusu');
      await tikla(tester, alan('sinif'), kaydirma: -240);
      await tester.tap(find.text('9-B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ekranda kal'));
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int>>(alan('sinif')).value, 1);
      expect(metin(tester, 'konu'), '9-A özel konusu');
      await tikla(tester, alan('sinif'), kaydirma: -240);
      await tester.tap(find.text('9-B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet ve devam et'));
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int>>(alan('sinif')).value, 2);
      expect(metin(tester, 'konu'), 'Denklemler');
      final kayitlar = await db.query('BireyselGunlukPlan');
      expect(kayitlar, hasLength(2));
      final kayit = kayitlar.singleWhere((r) => r['SinifSubeId'] == 1);
      expect(kayit['SinifSubeId'], 1);
      expect(kayit['Konu'], '9-A özel konusu');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Kaynak eksikken plan oluşturulmaz; yükleme bağlantısı sunulur', (
    tester,
  ) async {
    await db.delete('YillikPlanDetay');
    await db.delete('YillikPlan');
    await ac(tester, haftalik: true, sube: '9-A');
    await tikla(tester, find.byKey(const ValueKey('gunluk-plan-hazirla')));
    expect(find.textContaining('Yıllık plan eksik'), findsOneWidget);
    expect(alan('konu'), findsNothing);
    expect(await db.query('BireyselGunlukPlan'), isEmpty);
    await tikla(tester, find.text('Günlük plan için gerekli kaynaklar'));
    expect(find.text('Yıllık plan yükle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px ve büyük yazıda form ve işlem düğmeleri taşmadan kullanılabilir',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ac(tester, textScale: 1.6, koyu: true);
      await yaz(
        tester,
        'dersinIslenisi',
        'Öğrenci yanıtlarıyla derse giriş yapılır.',
      );
      await tikla(tester, alan('kaydet'));
      await tester.ensureVisible(alan('arsiv'));
      await tester.pumpAndSettle();
      expect(alan('pdf'), findsOneWidget);
      expect(alan('arsiv'), findsOneWidget);
      expect(await db.query('BireyselGunlukPlan'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
