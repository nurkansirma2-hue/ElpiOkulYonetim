import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yillik_planlarim_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final factory = WindowsMemoryFactory();
  late Database db;
  const hamYil = '2026/2027';

  setUpAll(() async {
    databaseFactory = factory;
    db = await LocalDatabase.instance.database;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    for (final tablo in [
      'YillikPlanDetay',
      'YillikPlan',
      'DersProgrami',
      'SinifSube',
      'Ders',
      'DersSaati',
      'OgretmenProfil',
    ]) {
      await db.delete(tablo);
    }
    await db.insert('OgretmenProfil', {
      'OgretmenProfilId': 1,
      'AdSoyad': 'Öğretmen',
      'EgitimOgretimYili': hamYil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-A',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': hamYil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    await db.insert('DersProgrami', {
      'DersId': 1,
      'SinifSubeId': 1,
      'DersSaatiId': 1,
      'Gun': 'Salı',
      'Baslangic': '08:00',
      'Bitis': '08:40',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': hamYil,
      'OlusturmaTarihi': 'test',
    });
  });

  tearDownAll(() async {
    await factory.db?.close();
  });

  Future<int> planEkle(List<Map<String, Object?>> satirlar) async {
    final id = await db.insert('YillikPlan', {
      'DersId': 1,
      'SinifSeviyesi': 9,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    for (final satir in satirlar) {
      await db.insert('YillikPlanDetay', {
        'YillikPlanId': id,
        'OlusturmaTarihi': 'test',
        ...satir,
      });
    }
    return id;
  }

  Map<String, Object?> satir(
    String konu, {
    String bas = '2026-10-12',
    String bit = '2026-10-16',
    String? kazanim,
    int? hafta = 6,
  }) => {
    'HaftaNo': hafta,
    'BaslangicTarihi': bas,
    'BitisTarihi': bit,
    'Konu': konu,
    if (kazanim != null) 'Kazanim': kazanim,
  };

  Future<void> ekraniAc(
    WidgetTester tester, {
    bool listeden = false,
    double textScale = 1,
    bool koyu = false,
    String? takvimUyarisi,
  }) async {
    final tema = ThemeData(
      colorSchemeSeed: Colors.green,
      brightness: koyu ? Brightness.dark : Brightness.light,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Theme(
          data: tema,
          child: listeden
              ? const BireyselYillikPlanlarimScreen()
              : Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => bireyselHaftalikKazanimAc(
                        context,
                        ogretmenProfilId: 1,
                        egitimOgretimYili: hamYil,
                        dersId: 1,
                        dersAdi: 'Matematik',
                        sinifSeviyesi: 9,
                        tarih: DateTime(2026, 10, 13),
                        sinif: '9-A',
                        takvimUyarisi: takvimUyarisi,
                      ),
                      child: const Text('Kartı aç'),
                    ),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!listeden) {
      await tester.tap(find.text('Kartı aç'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> gorVeTikla(WidgetTester tester, Finder hedef) async {
    if (hedef.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        hedef,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(hedef);
    await tester.pumpAndSettle();
    await tester.tap(hedef);
    await tester.pumpAndSettle();
  }

  testWidgets('Listeden giriş normalize plan yılını bulur ve kartı açar', (
    tester,
  ) async {
    await planEkle([
      satir('Listeden açılan konu', bas: '2026-01-01', bit: '2027-12-31'),
    ]);
    await ekraniAc(tester, listeden: true);
    expect(find.text('Yıllık plan yüklendi'), findsOneWidget);
    await gorVeTikla(tester, find.text('Matematik'));
    expect(find.text('Haftalık kazanım'), findsOneWidget);
    expect(find.text('Listeden açılan konu'), findsOneWidget);
    expect(find.byType(Table), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Aynı tarihin tüm satırları ve özgün alan başlıkları korunur', (
    tester,
  ) async {
    await planEkle([
      {
        ...satir('Denklemler', kazanim: 'Denklem çözer.'),
        'Unite': 'Cebir',
        'OgrenmeCiktisi': 'Çözümünü açıklar.',
        'YontemTeknik': 'Soru cevap',
      },
      {
        ...satir('', hafta: null),
        'IcerikCercevesi': 'Kesirler',
        'OgrenmeCiktisi': 'Kesirleri karşılaştırır.',
      },
      satir('Sonraki hafta', bas: '2026-10-19', bit: '2026-10-23'),
    ]);
    final once = await db.query('YillikPlanDetay');
    await ekraniAc(tester);
    expect(find.text('6. hafta'), findsOneWidget);
    expect(find.text('Kazanım'), findsOneWidget);
    expect(find.text('Denklem çözer.'), findsOneWidget);
    expect(find.text('Sonraki hafta'), findsNothing);
    await gorVeTikla(tester, find.text('Diğer plan bilgileri').first);
    expect(find.text('Soru cevap'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kesirleri karşılaştırır.'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('haftalik-kazanim-listesi')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('İçerik çerçevesi'), findsOneWidget);
    expect(find.text('Hafta numarası belirtilmemiş'), findsOneWidget);
    expect(await db.query('YillikPlanDetay'), once);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Tarih seçimi ile satırlar değişir, tablo dönüşünde tarih korunur',
    (tester) async {
      await planEkle([
        satir('İlk hafta'),
        satir('İkinci hafta', bas: '2026-10-19', bit: '2026-10-23', hafta: 7),
      ]);
      await ekraniAc(tester);
      await tester.tap(find.byKey(const ValueKey('haftalik-kazanim-tarih')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('Seç'));
      await tester.pumpAndSettle();
      expect(find.text('20.10.2026'), findsOneWidget);
      expect(find.text('İkinci hafta'), findsOneWidget);
      expect(find.text('İlk hafta'), findsNothing);
      await gorVeTikla(tester, find.text('Tüm yıl tablosu'));
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('İlk hafta'), findsOneWidget);
      await tester.tap(find.text('Haftalık karta dön'));
      await tester.pumpAndSettle();
      expect(find.text('20.10.2026'), findsOneWidget);
      expect(find.text('İkinci hafta'), findsOneWidget);
      expect(find.byType(Table), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Plan yok ve ayrıntı yok durumları ayrı gösterilir', (
    tester,
  ) async {
    await ekraniAc(tester);
    expect(find.textContaining('yıllık plan bulunamadı'), findsOneWidget);
    expect(find.text('Tüm yıl tablosu'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await planEkle([]);
    await ekraniAc(tester);
    expect(
      find.text('Yıllık plan var; kayıtlı ayrıntı bulunamadı.'),
      findsOneWidget,
    );
    expect(find.textContaining('yıllık plan bulunamadı'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tarihsiz ve geçersiz tarih satırları haftaya atanmaz', (
    tester,
  ) async {
    await planEkle([
      {'HaftaNo': 6, 'TarihAraligi': 'Belirsiz tarih', 'Konu': 'Tarihsiz'},
      satir('Hatalı tarih', bas: '2026-02-30', bit: '2026-03-05'),
    ]);
    await ekraniAc(tester);
    expect(
      find.textContaining('tarih aralığı eksik veya geçersiz'),
      findsOneWidget,
    );
    expect(
      find.text('Seçili tarih için plan bilgisi bulunamadı.'),
      findsOneWidget,
    );
    expect(find.text('6. hafta'), findsNothing);
    await gorVeTikla(tester, find.text('Tüm yıl tablosu'));
    expect(find.text('Tarihsiz'), findsOneWidget);
    expect(find.text('Hatalı tarih'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px büyük yazıda uzun kazanım okunur, koyu tema korunur', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final uzunKazanim = List.filled(
      30,
      'Öğrenci çözümünü örneklerle açıklar.',
    ).join(' ');
    await planEkle([satir('Denklemler', kazanim: uzunKazanim)]);
    await ekraniAc(
      tester,
      textScale: 1.6,
      koyu: true,
      takvimUyarisi: 'Çalışma takvimi yüklenmemiş',
    );
    expect(find.textContaining('Çalışma takvimi yüklenmemiş'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(uzunKazanim),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    final metin = tester.widget<Text>(find.text(uzunKazanim));
    expect(metin.maxLines, isNull);
    expect(metin.overflow, isNull);
    expect(
      Theme.of(tester.element(find.text(uzunKazanim))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}
