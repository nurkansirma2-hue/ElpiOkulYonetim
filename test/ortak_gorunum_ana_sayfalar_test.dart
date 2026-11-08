import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUp(() async {
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await db.insert('OgretmenProfil', {
      'OgretmenProfilId': 1,
      'AdSoyad': 'Örnek Öğretmen',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': '2026-09-01',
    });
  });
  tearDown(() => LocalDatabase.instance.close());

  Widget uygulama(Widget home, {double yazi = 1}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(yazi)),
      child: child!,
    ),
    home: home,
  );

  Future<void> ayardanDegistir(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Diğer işlemler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Görünüm'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kompakt liste'));
    await tester.tap(find.text('Kompakt liste'));
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();
  }

  Future<void> menuyaGit(WidgetTester tester) async {
    final f = find.byType(AnaMenuYerlesimi);
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(f);
    await tester.pump();
  }

  for (final adim in [1, 2]) {
    for (final genislik in [320.0, 430.0]) {
      testWidgets('Kurulum adımı $adim tercihi zorlamaz: $genislik px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(genislik, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (adim == 2) {
          await db.insert('SinifSube', {
            'SinifSubeId': 1,
            'SinifKodu': '10-A',
            'SinifSeviyesi': 10,
            'EgitimOgretimYili': '2026-2027',
            'OlusturmaTarihi': '2026-09-01',
          });
          await db.insert('Ders', {
            'DersId': 1,
            'DersAdi': 'Matematik',
            'OlusturmaTarihi': '2026-09-01',
          });
          await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
          await db.insert('DersProgrami', {
            'SinifSubeId': 1,
            'DersId': 1,
            'DersSaatiId': 1,
            'Gun': 'Pazartesi',
            'OgretmenProfilId': 1,
            'EgitimOgretimYili': '2026-2027',
            'OlusturmaTarihi': '2026-09-01',
          });
        }
        await tester.pumpWidget(
          uygulama(
            const BireyselAnaSayfaScreen(),
            yazi: genislik == 320 ? 1.5 : 1,
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        expect(
          find.text(
            adim == 1
                ? '1 / 2 • Ders programınızı yükleyin'
                : '2 / 2 • Yıllık planlarınızı yükleyin',
          ),
          findsOneWidget,
        );
        await menuyaGit(tester);
        expect(
          tester
              .widget<AnaMenuYerlesimi>(find.byType(AnaMenuYerlesimi))
              .kompakt,
          isFalse,
        );
        expect(
          tester
              .widgetList<AnaMenuStili>(find.byType(AnaMenuStili))
              .every((s) => !s.kompakt),
          isTrue,
        );
        final onceki = tester.state(find.byType(BireyselAnaSayfaScreen));
        await ayardanDegistir(tester);
        await menuyaGit(tester);
        expect(
          tester
              .widget<AnaMenuYerlesimi>(find.byType(AnaMenuYerlesimi))
              .kompakt,
          isTrue,
        );
        expect(tester.state(find.byType(BireyselAnaSayfaScreen)), same(onceki));
        await ayardanDegistir(tester);
        expect(
          tester
              .widget<AnaMenuYerlesimi>(find.byType(AnaMenuYerlesimi))
              .kompakt,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
