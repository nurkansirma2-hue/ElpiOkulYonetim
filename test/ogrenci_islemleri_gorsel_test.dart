import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ogrenci_islemleri_screen.dart';
import 'package:elpi_okul_yonetim/screens/veli_bilgileri_screen.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'package:elpi_okul_yonetim/widgets/modul_ust_bar.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  var bildirim = 0;
  setUpAll(() async {
    final normal = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await normal.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'gorsel-test-okulu',
      'OkulAdi': 'Test Okulu',
      'OkulKisaAdi': 'Test',
      'EgitimYili': '2026-2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Test Öğretmeni',
      'OkulAdi': 'Test Okulu',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-C',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {
      'DersAdi': 'Test Dersi',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    // Yalnız :memory: test verisi; uygulama verisi veya üretim örneği değildir.
    for (var i = 1; i <= 148; i++) {
      await db.insert('Ogrenci', {
        'OgrenciId': i,
        'OkulNo': '${3000 + i}',
        'Ad': i == 1
            ? 'ABDULLAH YİĞİT'
            : 'ÖĞRENCİ ${i.toString().padLeft(3, '0')}',
        'Soyad': i == 1 ? 'UZUNSOYADI' : 'TEST',
        'VeliTuru': 'Anne',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    bildirim = 0;
    ModulUstBarBaglantisi.aktif = ModulUstBarBaglantisi(
      sahip: Object(),
      ayarlar: () async {},
      profil: () async {},
      bildirimler: () async {
        bildirim++;
      },
    );
  });
  tearDown(() async {
    ModulUstBarBaglantisi.aktif = null;
    await LocalDatabase.instance.close();
  });

  Future<void> ac(
    WidgetTester t,
    double width,
    double scale, {
    bool dark = false,
    GlobalKey? capture,
  }) async {
    t.view.physicalSize = Size(width, 840);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AnaSayfaTemasi.mavi.olustur(
          dark ? Brightness.dark : Brightness.light,
        ),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute<void>(
                  builder: (_) => RepaintBoundary(
                    key: capture,
                    child: const BireyselOgrenciIslemleriScreen(
                      formlar: Center(child: Text('Mevcut Form İşlemleri')),
                    ),
                  ),
                ),
              ),
              child: const Text('Modülü aç'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Modülü aç'));
    await t.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 390.0, 400.0, 420.0, 900.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        '$width / $scale sekmeler tam görünür, araçlar ölçülür, liste korunur',
        (t) async {
          await ac(t, width, scale);
          expect(t.takeException(), isNull);
          expect(find.text('148 öğrenci'), findsOneWidget);
          expect(find.text('Liste Tasarla / Yazdır'), findsNothing);
          final form = find.byKey(const ValueKey('ogrenci-sekmesi-1'));
          expect(form.hitTestable(), findsOneWidget);
          expect(t.getBottomRight(form).dx, lessThanOrEqualTo(width));
          for (final title in ['Form', 'İşlemleri']) {
            expect(find.textContaining(title), findsWidgets);
          }
          final scroll = t.widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ogrenci-araclari')),
          );
          final state = t.state<ScrollableState>(
            find
                .descendant(
                  of: find.byWidget(scroll),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          if (width >= 390 && scale == 1) {
            expect(
              state.position.maxScrollExtent,
              lessThanOrEqualTo(1),
              reason: 'Normal telefonda yedi araç birlikte görünmeli.',
            );
          }
          expect(
            t.getSize(find.byKey(const ValueKey('ogrenci-arac-0'))).height,
            lessThan(105),
          );
          await t.tap(form);
          await t.pumpAndSettle();
          expect(find.text('Mevcut Form İşlemleri'), findsOneWidget);
          await t.tap(find.byKey(const ValueKey('ogrenci-sekmesi-0')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('ogrenci-gorunum-1')));
          await t.pumpAndSettle();
          final liste = find
              .descendant(
                of: find.byType(CustomScrollView).first,
                matching: find.byType(Scrollable),
              )
              .first;
          await t.drag(liste, const Offset(0, -260));
          await t.pumpAndSettle();
          expect(find.textContaining('Cinsiyet:'), findsWidgets);
          t.state<ScrollableState>(liste).position.jumpTo(0);
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('ogrenci-gorunum-0')));
          await t.pumpAndSettle();
          expect(find.textContaining('Cinsiyet:'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('dar başlıkta bildirim menüden çalışır, Ana Sayfa geri döner', (
    t,
  ) async {
    await ac(t, 320, 1.6);
    await t.tap(find.byTooltip('Diğer işlemler'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bildirimler'));
    await t.pumpAndSettle();
    expect(bildirim, 1);
    await t.tap(find.byTooltip('Ana Sayfa'));
    await t.pumpAndSettle();
    expect(find.text('Modülü aç'), findsOneWidget);
  });

  testWidgets('Veli Bilgileri aracı mevcut hızlı girişi açar', (t) async {
    await ac(t, 400, 1);
    await t.tap(find.byKey(const ValueKey('ogrenci-arac-3')));
    await t.pumpAndSettle();
    expect(find.byType(VeliBilgileriScreen), findsOneWidget);
    expect(find.text('Sınıf Bazlı Veli Bilgisi Girişi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('büyük yazıda klavye, arama ve son öğrenci erişimi', (t) async {
    await ac(t, 320, 1.6);
    final liste = find
        .descendant(
          of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    // Liste başlığı ve giriş alanı da aynı kaydırma alanındadır.
    final arama = find.widgetWithText(TextField, 'Ad, soyad veya okul no ara');
    await t.drag(liste, const Offset(0, -200));
    await t.pumpAndSettle();
    await t.ensureVisible(arama);
    await t.tap(arama);
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('ogrenci-araclari')), findsNothing);
    await t.enterText(arama, 'ÖĞRENCİ 148');
    await t.pumpAndSettle();
    expect(find.text('1 öğrenci'), findsOneWidget);
    final scroll = t.state<ScrollableState>(liste).position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await t.pumpAndSettle();
    expect(find.text('ÖĞRENCİ 148 TEST'), findsOneWidget);
    expect(t.takeException(), isNull);
    t.view.resetViewInsets();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ogrenci-araclari')), findsOneWidget);
  });

  testWidgets('telefon ve büyük yazıda gerçek Flutter görüntüleri', (t) async {
    final oncekiGolge = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final durum in [
        (400.0, 1.0, false),
        (360.0, 1.15, false),
        (320.0, 1.6, false),
        (400.0, 1.0, true),
      ]) {
        final key = GlobalKey();
        await ac(t, durum.$1, durum.$2, dark: durum.$3, capture: key);
        expect(t.takeException(), isNull);
        if (durum.$1 == 360) {
          final a = find.byKey(const ValueKey('ogrenci-araclari'));
          final scroll = t.state<ScrollableState>(
            find.descendant(of: a, matching: find.byType(Scrollable)).first,
          );
          expect(scroll.position.maxScrollExtent, lessThanOrEqualTo(1));
          for (var i = 0; i < 7; i++) {
            final metinler = find.descendant(
              of: find.byKey(ValueKey('ogrenci-arac-$i')),
              matching: find.byType(Text),
            );
            for (final e in metinler.evaluate()) {
              expect(
                (e.renderObject! as RenderParagraph).didExceedMaxLines,
                false,
                reason: 'Araç adı kesilmemeli: ${(e.widget as Text).data}',
              );
            }
          }
        }
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(
            '/tmp/ogrenci-gorsel-duzeltme',
          ).create(recursive: true);
          await File(
            '/tmp/ogrenci-gorsel-duzeltme/${durum.$1.toInt()}-${durum.$2}-${durum.$3 ? "koyu" : "acik"}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
      }
    } finally {
      debugDisableShadows = oncekiGolge;
    }
  });
}
