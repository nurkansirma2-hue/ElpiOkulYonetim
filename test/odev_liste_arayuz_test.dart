import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/odev_kontrol.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_odev_kontrol_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselListeOturumu oturum;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    await BireyselProfilService.kaydet(
      adSoyad: 'Öğretmen',
      brans: 'Ders',
      okulAdi: 'Okul',
      okulKisaAdi: 'O',
      egitimOgretimYili: '2026-2027',
      donem: 1,
      meslekPaketiAktif: false,
    );
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Ders',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    for (final id in [1, 2]) {
      await db.insert('SinifSube', {
        'SinifSubeId': id,
        'SinifKodu': '9-${id == 1 ? 'C' : 'D'}',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': id,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': id == 1 ? 'Pazartesi' : 'Salı',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '$id',
        'Ad': 'Öğrenci',
        'Soyad': '$id',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': id,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    oturum = await BireyselOdevKontrolService.hazirla();
  });
  tearDown(LocalDatabase.instance.close);
  Future<int> gorev(
    String baslik, {
    int sinif = 1,
    OdevGorevTuru tur = OdevGorevTuru.normalOdev,
  }) => BireyselOdevKontrolService.gorevOlustur(
    oturum,
    sinifSubeId: sinif,
    dersId: 1,
    gorevTuru: tur,
    baslik: baslik,
    baslangicTarihi: DateTime(2026, 9, 1),
    ogrenciIdleri: [sinif],
  );

  Future<void> ac(WidgetTester t, double genislik) async {
    t.view.physicalSize = Size(genislik, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('ODEV_GORSEL')) {
      final font = FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
    await t.pumpWidget(
      const RepaintBoundary(
        key: ValueKey('goruntu'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: OdevKontrolScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('arama sıralama ve durum sayıları gerçek kayıtlarla çalışır', (
    t,
  ) async {
    await gorev('Zebra');
    final a = await gorev('Alfa', tur: OdevGorevTuru.proje);
    await BireyselOdevKontrolService.tamamlanmaKaydet(oturum, a, true);
    await db.insert('OdevEk', {
      'OdevId': a,
      'DosyaAdi': 'ornek.txt',
      'Veri': Uint8List.fromList([65]),
    });
    await ac(t, 390);
    expect(find.text('1 dosya'), findsOneWidget);
    expect(find.text('Tümü (2)'), findsOneWidget);
    expect(find.text('Bekleyen (1)'), findsOneWidget);
    expect(find.text('Tamamlanan (1)'), findsOneWidget);
    await t.tap(find.byTooltip('Sırala'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ödev adı (A–Z)'));
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.text('Alfa')).dy,
      lessThan(t.getTopLeft(find.text('Zebra')).dy),
    );
    await t.tap(find.byTooltip('Ödev ara'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Zebra');
    await t.pumpAndSettle();
    expect(find.text('Alfa'), findsNothing);
    await t.tap(find.byTooltip('Aramayı kapat'));
    await t.pumpAndSettle();
    expect(find.text('Alfa'), findsOneWidget);
    await t.tap(find.text('Tamamlanan (1)'));
    await t.pumpAndSettle();
    expect(find.text('Zebra'), findsNothing);
    expect(find.text('Alfa'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('320 px sabit alt çubuk kaydırmada erişilir ve seçim korunur', (
    t,
  ) async {
    final a = await gorev('Defter');
    for (var i = 0; i < 16; i++) {
      await gorev('Ödev $i');
    }
    await ac(t, 320);
    final once = t.getTopLeft(find.byTooltip('Ödev ara'));
    await t.drag(find.byType(ListView), const Offset(0, -900));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byTooltip('Ödev ara')), once);
    await t.drag(find.byType(ListView), const Offset(0, 2000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(ValueKey('odev-sec-$a')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.byKey(ValueKey('odev-sec-$a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('odev-sec-$a')));
    await t.pumpAndSettle();
    expect(find.byTooltip('Seçili ödevleri sil'), findsOneWidget);
    expect(
      t.getTopLeft(find.byTooltip('Seçili ödevleri sil')).dy,
      greaterThan(550),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('390 px ödev listesi görsel kontrol', (t) async {
    final a = await gorev('Mobil Uygulamalar');
    await gorev('Dijital Tasarım', tur: OdevGorevTuru.proje);
    await gorev('Nesne Tabanlı Programlama', tur: OdevGorevTuru.performans);
    await gorev('Bilgisayarlı Tasarım', tur: OdevGorevTuru.rutinKontrol);
    await BireyselOdevKontrolService.tamamlanmaKaydet(oturum, a, true);
    await ac(t, 390);
    if (const bool.fromEnvironment('ODEV_GORSEL')) {
      await t.runAsync(() async {
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('goruntu')),
        );
        final img = await boundary.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'C:/OkulYonetim/work/odev_liste_arayuz_20261028/odevlerim.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        img.dispose();
      });
    }
    expect(find.byTooltip('Ana Sayfa'), findsOneWidget);
    expect(find.byTooltip('Bildirimler'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
