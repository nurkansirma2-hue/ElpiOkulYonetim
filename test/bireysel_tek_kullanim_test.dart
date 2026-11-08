import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/main.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_kurulum_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'support/windows_memory_database.dart';

class _AgYasak extends HttpOverrides {
  int istek = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    istek++;
    throw StateError('Açılışta ağ erişimi beklenmiyordu.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late _AgYasak ag;
  HttpOverrides? onceki;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    onceki = HttpOverrides.current;
    ag = _AgYasak();
    HttpOverrides.global = ag;
  });
  tearDown(() async {
    HttpOverrides.global = onceki;
    await LocalDatabase.instance.close();
  });
  Future<void> ac(WidgetTester t) async {
    await t.pumpWidget(const MyApp());
    for (var i = 0; i < 40; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 100));
      if (find.byType(BireyselAnaSayfaScreen).evaluate().isNotEmpty ||
          find.byType(BireyselKurulumScreen).evaluate().isNotEmpty) break;
    }
    await t.pump(const Duration(seconds: 3));
    addTearDown(() => t.pumpWidget(const SizedBox.shrink()));
  }
  testWidgets('ilk kurulum çevrimdışı doğrudan öğretmen bilgilerini açar', (t) async {
    SharedPreferences.setMockInitialValues({});
    await ac(t);
    expect(find.byType(BireyselKurulumScreen), findsOneWidget);
    expect(find.text('Okul / Kurumsal'), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('calisma_modu'), 'bireysel');
    expect(ag.istek, 0);
    expect(t.takeException(), isNull);
  });
  for (final eski in ['okul', 'kurumsal', 'bireysel']) {
    testWidgets('eski $eski tercihi profil ve öğrencileri silmeden bireyseli açar', (t) async {
      SharedPreferences.setMockInitialValues({'calisma_modu': eski});
      await BireyselProfilService.kaydet(
        adSoyad: 'Test Öğretmen', brans: 'Matematik', okulAdi: 'Test Okulu',
        okulKisaAdi: 'TO', egitimOgretimYili: '2026-2027', donem: 1,
        meslekPaketiAktif: false,
      );
      await db.insert('Ogrenci', {'OkulNo': '17', 'Ad': 'Öğrenci', 'Soyad': 'Test', 'OlusturmaTarihi': 'test'});
      final oncekiProfil = await db.query('OgretmenProfil');
      final oncekiOgrenciler = await db.query('Ogrenci');
      await ac(t);
      expect(find.byType(BireyselAnaSayfaScreen), findsOneWidget);
      expect(await db.query('OgretmenProfil'), oncekiProfil);
      expect(await db.query('Ogrenci'), oncekiOgrenciler);
      expect((await SharedPreferences.getInstance()).getString('calisma_modu'), 'bireysel');
      expect(ag.istek, 0);
      expect(t.takeException(), isNull);
    });
  }
}
