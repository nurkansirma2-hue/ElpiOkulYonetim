import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'package:elpi_okul_yonetim/widgets/modul_ust_bar.dart';
import 'package:elpi_okul_yonetim/widgets/mesajlasma_gorunumu.dart';
import 'support/windows_memory_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  var gonderim = 0;
  setUpAll(() async {
    if (const bool.fromEnvironment('MESAJ_GORSEL')) {
      for (final family in ['NotoSans', 'Roboto', 'Ahem']) {
        await (FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
            .load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    await BireyselProfilService.kaydet(
      adSoyad: 'Deniz Öğretmen',
      brans: 'Matematik',
      okulAdi: 'Test Okulu',
      okulKisaAdi: 'TO',
      egitimOgretimYili: '2026-2027',
      donem: 1,
      meslekPaketiAktif: false,
    );
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    for (final id in [1, 2]) {
      await db.insert('SinifSube', {
        'SinifSubeId': id,
        'SinifKodu': id == 1 ? '9-C' : '10-D',
        'SinifSeviyesi': id == 1 ? 9 : 10,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': id,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    for (var i = 1; i <= 41; i++) {
      await db.insert('Ogrenci', {
        'OgrenciId': i,
        'OkulNo': '$i',
        'Ad': i == 1 ? 'Ada' : 'Uzun öğrenci adı $i',
        'Soyad': 'Yılmaz',
        'Telefon': '0532000${i.toString().padLeft(4, '0')}',
        'AnneAdi': 'Anne $i',
        'AnneTelefon': i == 1 ? '' : '0532000${i.toString().padLeft(4, '0')}',
        'BabaAdi': 'Baba $i',
        'BabaTelefon': '05321112233',
        'VeliTuru': 'Anne',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': i == 41 ? 2 : 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    gonderim = 0;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
      whatsappAc: (_, _) async {
        gonderim++;
      },
      smsIzni: () async => true,
      smsGonder: (_, _) async {
        gonderim++;
        return 1;
      },
    );
    ModulUstBarBaglantisi.aktif = ModulUstBarBaglantisi(
      sahip: service,
      ayarlar: () async {},
      profil: () async {},
      bildirimler: () async {},
    );
  });
  tearDown(() async {
    ModulUstBarBaglantisi.aktif = null;
    await LocalDatabase.instance.close();
  });
  Finder getScroll() => find
      .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
      .first;
  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      t.state<ScrollableState>(getScroll()).position.jumpTo(0);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        f,
        150,
        scrollable: getScroll(),
        maxScrolls: 80,
      );
    }
    await t.ensureVisible(f.last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(f.last);
    await t.pump(const Duration(milliseconds: 350));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump();
    for (
      var i = 0;
      i < 40 &&
          find.byType(AlertDialog).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    if (find.byType(AlertDialog).evaluate().isEmpty &&
        find.byType(SimpleDialog).evaluate().isEmpty) {
      await t.pumpAndSettle();
    }
  }

  Future<void> ac(WidgetTester t, {double width = 390, double yazi = 1}) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('mesaj-gorsel'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(yazi)),
            child: child!,
          ),
          home: MesajlasmaScreen(service: service),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> sinif(WidgetTester t) async {
    await tap(t, find.byType(DropdownButton<int>));
    await tap(t, find.text('9-C').last);
    await tap(t, find.text('Alıcı grubu'));
    await tap(t, find.text('Sınıf öğrencileri'));
    await tap(t, find.text('Velisi'));
  }

  Future<void> gorsel(WidgetTester t, String name) async {
    if (!const bool.fromEnvironment('MESAJ_GORSEL')) return;
    await t.runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('mesaj-gorsel')),
      );
      final img = await boundary.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File('build/mesaj_arayuz/$name.png');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(data!.buffer.asUint8List());
      img.dispose();
    });
  }

  for (final width in [320.0, 390.0]) {
    testWidgets('$width px pastel kartlar ve sabit ön izleme taşmaz', (
      t,
    ) async {
      await ac(t, width: width);
      await sinif(t);
      expect(find.text('Öğrenci listesi (0/40 seçili)'), findsOneWidget);
      final button = find.byType(MesajOnizlemeButonu);
      final y = t.getTopLeft(button).dy;
      t.state<ScrollableState>(getScroll()).position.jumpTo(0);
      await t.pumpAndSettle();
      await gorsel(t, 'mesaj_${width.toInt()}');
      await t.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await t.pumpAndSettle();
      expect(t.getTopLeft(button).dy, y);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'sekme dönüşünde sınıf, alıcı ve metin korunur; gönderim ön izlemede başlatılmaz',
    (t) async {
      await ac(t);
      await sinif(t);
      await tap(t, find.text('Öğrenci listesi (0/40 seçili)'));
      await tap(t, find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')));
      await tap(t, find.text('Gönderim Geçmişi'));
      await tap(t, find.text('Yeni Mesaj'));
      expect(find.text('Öğrenci listesi (1/40 seçili)'), findsOneWidget);
      final field = find.byKey(const ValueKey('mesaj-metni'));
      await tap(t, field);
      await t.enterText(field, 'Merhaba {OgrenciAdi}, {Sinif}, {Tarih}');
      await t.pumpAndSettle();
      await tap(t, find.text('Gönderim Geçmişi'));
      await tap(t, find.text('Yeni Mesaj'));
      expect(
        t.widget<TextField>(field).controller!.text,
        contains('{OgrenciAdi}'),
      );
      await tap(t, find.text('Ön İzle ve Onayla'));
      expect(find.textContaining('Merhaba Ada Yılmaz, 9-C,'), findsOneWidget);
      expect(find.textContaining('Baba telefonu kullanılıyor'), findsOneWidget);
      expect(find.text('SMS ile gönder'), findsOneWidget);
      expect(find.text('WhatsApp ile gönder'), findsOneWidget);
      expect(gonderim, 0);
      expect(await db.query('MesajKuyrugu'), isEmpty);
      await tap(t, find.text('Düzelt'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Mesaj taslağından çıkılsın mı?'), findsOneWidget);
      await tap(t, find.text('Düzenlemeye devam et'));
      expect(
        t.widget<TextField>(field).controller!.text,
        contains('{OgrenciAdi}'),
      );
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['VeliTuru'],
        'Anne',
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('40 öğrenci topluca seçilir ve görünür seçimler kaldırılır', (
    t,
  ) async {
    await ac(t);
    await sinif(t);
    await tap(t, find.text('Öğrenci listesi (0/40 seçili)'));
    await tap(t, find.text('Görünenleri seç'));
    expect(find.text('Öğrenci listesi (40/40 seçili)'), findsOneWidget);
    await tap(t, find.text('Öğrenci listesi (40/40 seçili)'));
    await tap(t, find.text('Seçimi kaldır'));
    expect(find.text('Öğrenci listesi (0/40 seçili)'), findsOneWidget);
    expect(gonderim, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('büyük yazı ve klavye açıkken mesaj alanı erişilebilir', (
    t,
  ) async {
    await ac(t, width: 320, yazi: 1.7);
    await sinif(t);
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    final field = find.byKey(const ValueKey('mesaj-metni'));
    await tap(t, field);
    await t.enterText(field, 'Mesaj denemesi');
    await t.pumpAndSettle();
    expect(
      t.getBottomRight(find.byType(MesajOnizlemeButonu)).dy,
      lessThanOrEqualTo(844 - 280),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('kendisi seçiliyken kalem öğrenci telefonunu düzenler', (
    t,
  ) async {
    await ac(t);
    await sinif(t);
    await tap(t, find.byKey(const ValueKey('mesaj-ogrenci-hedef-basligi')));
    await tap(t, find.text('Kendisi'));
    await tap(t, find.text('Öğrenci listesi (0/40 seçili)'));
    await tap(t, find.byTooltip('Öğrenci telefonunu düzenle').first);
    expect(find.text('Telefonu düzenle'), findsOneWidget);
    expect(find.text('Veli bilgilerini düzenle'), findsNothing);
    final tel = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await t.enterText(tel, '05329991111');
    await tap(t, find.text('Kaydet'));
    final row = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
    expect(row['Telefon'], '05329991111');
    expect(row['AnneTelefon'], '');
    expect(row['BabaTelefon'], '05321112233');
    expect(t.takeException(), isNull);
  });
  testWidgets('boş öğrenci listesinde ön izleme kapalı kalır', (t) async {
    await db.delete('OgrenciSinifKayit');
    await ac(t);
    await sinif(t);
    await tap(t, find.text('Öğrenci listesi (0/0 seçili)'));
    expect(find.text('Eşleşen öğrenci bulunamadı.'), findsOneWidget);
    expect(
      t.widget<MesajOnizlemeButonu>(find.byType(MesajOnizlemeButonu)).onPressed,
      isNull,
    );
    expect(gonderim, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('geçmiş öğrenci bazında gerçek tarih ve kanalı gösterir', (
    t,
  ) async {
    final b = await service.hazirla();
    final kisi = (await service.aliciAdaylari(
      b,
    )).firstWhere((k) => k.tur == MesajKisiTuru.veli && k.kisiId == '1');
    await service.tekliGonder(
      b,
      'Bilgilendirme mesajı',
        kaynakModul: 'Mesajlasma',
      kisiler: MesajKisiOnIzleme([kisi]),
      sms: false,
    );
    await ac(t);
    await tap(t, find.text('Gönderim Geçmişi'));
    expect(find.byType(MesajGecmisKarti), findsOneWidget);
    expect(find.textContaining('WhatsApp'), findsWidgets);
    expect(find.textContaining('Onay bekliyor'), findsOneWidget);
    expect(find.text('9-C • 1 • Ada Yılmaz'), findsOneWidget);
    await gorsel(t, 'mesaj_gecmis');
    expect(await db.query('MesajTekliGecmis'), hasLength(1));
    expect(t.takeException(), isNull);
  });
}
