import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
// File-system calls are isolated in a temporary directory using the existing plugin interface.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_kurulum_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ders_programim_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_rehberlik_screen.dart';
import 'package:elpi_okul_yonetim/screens/odev_kontrol_screen.dart';
import 'package:elpi_okul_yonetim/screens/performans_not_screen.dart';
import 'package:elpi_okul_yonetim/screens/rapor_olustur_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_belgelerim_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yillik_planlarim_screen.dart';
import 'package:elpi_okul_yonetim/screens/import_merkezi_screen.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/screens/test_modulu_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ogrenci_islemleri_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_profil_service.dart';
import 'package:elpi_okul_yonetim/services/baslangic_belgeleri_service.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'support/windows_memory_database.dart';

class _Yollar extends PathProviderPlatform {
  _Yollar(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory alan;
  late PathProviderPlatform eskiYollar;
  final bugun = DateUtils.dateOnly(DateTime.now());
  final basYil = bugun.month >= 7 ? bugun.year : bugun.year - 1;
  final yil = '$basYil-${basYil + 1}';
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  setUpAll(() async {
    if (const bool.fromEnvironment('ANA_SAYFA_GORSEL')) {
      await (FontLoader(
        'NotoSans',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
      await (FontLoader(
        'Ahem',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({
      'calisma_modu': 'bireysel',
      for (final ad in BaslangicBelgeleriService.dosyalar)
        'baslangic_belgesi_v1_$ad': true,
    });
    alan = await Directory.systemTemp.createTemp('ana_sayfa_ui_');
    eskiYollar = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Yollar(alan.path);
    db = await LocalDatabase.instance.database;
    await BireyselProfilService.kaydet(
      adSoyad: 'Deniz Öğretmen',
      brans: 'Matematik',
      okulAdi: 'Örnek Okul',
      okulKisaAdi: 'ÖO',
      egitimOgretimYili: yil,
      donem: 1,
      meslekPaketiAktif: false,
    );
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-A',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    for (final id in [1, 2]) {
      await db.insert('DersSaati', {'DersSaatiId': id, 'SiraNo': id});
      for (final gun in ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma']) {
        await db.insert('DersProgrami', {
          'DersId': 1,
          'SinifSubeId': 1,
          'DersSaatiId': id,
          'OgretmenProfilId': 1,
          'EgitimOgretimYili': yil,
          'Gun': gun,
          'Baslangic': id == 1 ? '08:00' : '08:50',
          'Bitis': id == 1 ? '08:40' : '09:30',
          'Derslik': 'Derslik A',
          'OlusturmaTarihi': 'test',
        });
      }
    }
    await db.insert('YillikPlan', {
      'YillikPlanId': 1,
      'OgretmenProfilId': 1,
      'DersId': 1,
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': 1,
      'HaftaNo': 1,
      'BaslangicTarihi': iso(bugun.subtract(const Duration(days: 90))),
      'BitisTarihi': iso(bugun.add(const Duration(days: 90))),
      'Konu': 'Denklem çözüm yöntemleri',
      'Saat': '2',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('CalismaTakvimi', {
      'CalismaTakvimiId': 1,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('CalismaTakvimiDetay', {
      'CalismaTakvimiId': 1,
      'HaftaNo': 1,
      'BaslangicTarihi': iso(bugun.subtract(const Duration(days: 90))),
      'BitisTarihi': iso(bugun.add(const Duration(days: 90))),
      'KayitTuru': 'Ders',
      'CalismaVarMi': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OgrenciId': 1,
      'OkulNo': '125',
      'Ad': 'Ada',
      'Soyad': 'Yılmaz',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': yil,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OgrenciId': 2,
      'OkulNo': '999',
      'Ad': 'Kapsam Dışı',
      'Soyad': 'Öğrenci',
      'OlusturmaTarihi': 'test',
    });
  });
  tearDown(() async {
    await LocalDatabase.instance.close();
    PathProviderPlatform.instance = eskiYollar;
    await alan.delete(recursive: true);
  });

  Widget app({double yazi = 1}) => RepaintBoundary(
    key: const ValueKey('ana-sayfa-onizleme'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(yazi),
        ),
        child: child!,
      ),
      home: const BireyselAnaSayfaScreen(),
    ),
  );
  Future<void> ac(WidgetTester t, {double width = 390, double yazi = 1}) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(app(yazi: yazi));
    await t.pumpAndSettle();
  }

  Future<void> dokun(WidgetTester t, Finder f, {bool bekle = true}) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        180,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
    }
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
    await t.tap(f.last);
    if (!bekle) {
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      return;
    }
    for (var i = 0; i < 60; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await t.pumpAndSettle();
  }

  Future<void> menu(WidgetTester t, String ad) async {
    if (ad == 'Öğrenci ara') {
      await dokun(t, find.byKey(const ValueKey('sabit-ogrenci-arama')));
      return;
    }
    await dokun(t, find.byTooltip('Diğer işlemler'));
    await dokun(t, find.text(ad));
  }

  Future<void> gorsel(WidgetTester t, String name) async {
    if (!const bool.fromEnvironment('ANA_SAYFA_GORSEL')) return;
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('ana-sayfa-onizleme')),
      );
      final image = await b.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final f = File('build/ana_sayfa_onizleme/$name.png');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets('$width px uyarlanır kartlar, gerçek ders/konu ve kaydırma', (
      t,
    ) async {
      await ac(t, width: width);
      if (bugun.weekday > 5) {
        for (var i = 0; i < bugun.weekday - 5; i++) {
          await dokun(t, find.byTooltip('Önceki gün'));
        }
      }
      expect(find.text('OkulYonetim'), findsOneWidget);
      expect(find.text('Bireysel Öğretmen Modu'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.text('Matematik · 9-A'), findsOneWidget);
      expect(find.text('Denklem çözüm yöntemleri'), findsOneWidget);
      expect(find.text('Derslik: Derslik A'), findsOneWidget);
      expect(find.text('Deniz Öğretmen'), findsOneWidget);
      await gorsel(t, 'ana_sayfa_${width.toInt()}');
      await dokun(t, find.text('Daralt'));
      expect(find.text('Matematik · 9-A'), findsOneWidget);
      expect(find.text('Önceki ders'), findsOneWidget);
      expect(find.text('Sonraki ders'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'ana_sayfa_dersler_acik',
        ),
        false,
      );
      final a = find.byKey(const ValueKey('modul-Ders Programım')),
          b = find.byKey(const ValueKey('modul-Sınıf Rehberliğim'));
      await t.ensureVisible(a);
      await t.pumpAndSettle();
      if (t.getTopLeft(a).dy == t.getTopLeft(b).dy) {
        expect(
          t.getTopLeft(b).dx,
          greaterThanOrEqualTo(t.getBottomRight(a).dx),
        );
      } else {
        expect(
          t.getTopLeft(b).dy,
          greaterThanOrEqualTo(t.getBottomRight(a).dy),
        );
      }
      await dokun(t, find.byKey(const ValueKey('modul-Öğrenci İşlemleri')));
      expect(find.byType(BireyselOgrenciIslemleriScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('boş gün ve büyük yazı; daraltma ile tema tercihi korunur', (
    t,
  ) async {
    await db.delete('DersProgrami');
    SharedPreferences.setMockInitialValues({
      'calisma_modu': 'bireysel',
      'ana_sayfa_ekran_modu': 'dark',
      'ana_sayfa_tema': 'yesil',
      'ana_sayfa_kompakt': true,
    });
    await ac(t, width: 320, yazi: 2);
    expect(find.text('Bugünkü dersler'), findsOneWidget);
    await dokun(t, find.text('Daralt'));
    expect(find.text('Genişlet'), findsOneWidget);
    await menu(t, 'Öğrenci ara');
    expect(find.byType(TextField), findsOneWidget);
    await dokun(t, find.byTooltip('Ana sayfaya dön'));
    await t.pumpAndSettle();
    expect(find.text('Modüller'), findsOneWidget);
    final c = t.element(find.byType(AnaMenuKart).first);
    expect(Theme.of(c).brightness, Brightness.dark);
    expect(
      (await SharedPreferences.getInstance()).getBool('ana_sayfa_kompakt'),
      true,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('arama ders kapsamındaki öğrenciyi bulur; geri aramayı kapatır', (
    t,
  ) async {
    await ac(t);
    final before = await db.query('Ogrenci');
    await menu(t, 'Öğrenci ara');
    await t.enterText(find.byType(TextField), 'Ada');
    await t.pumpAndSettle();
    expect(find.text('Ada Yılmaz'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Kapsam Dışı');
    await t.pumpAndSettle();
    expect(find.text('Sonuç bulunamadı'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Modüller'), findsOneWidget);
    expect(await db.query('Ogrenci'), before);
  });
  testWidgets(
    'arama yalnız dokununca odaklanır; dönüşte ve yenilemede odaklanmaz',
    (t) async {
      await ac(t);
      final arama = find.byKey(const ValueKey('sabit-ogrenci-arama'));
      FocusNode odak() => t.widget<TextField>(arama).focusNode!;
      expect(odak().hasFocus, false);
      odak().requestFocus();
      await t.pumpAndSettle();
      expect(odak().hasFocus, false);
      await t.tap(arama);
      await t.pumpAndSettle();
      expect(odak().hasFocus, true);
      await menu(t, 'Profilim');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(odak().hasFocus, false);
      await t.tap(find.byTooltip('Yenile'));
      await t.pumpAndSettle();
      expect(odak().hasFocus, false);
      await t.tap(arama);
      await t.pumpAndSettle();
      expect(odak().hasFocus, true);
      await dokun(t, find.byTooltip('Ana sayfaya dön'));
      expect(odak().hasFocus, false);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('alt arama kaydırmada sabittir; geri aramayı temizler', (
    t,
  ) async {
    await ac(t, width: 320);
    final arama = find.byKey(const ValueKey('sabit-ogrenci-arama'));
    final konum = t.getTopLeft(arama);
    await t.drag(find.byType(ListView).first, const Offset(0, -450));
    await t.pumpAndSettle();
    expect(t.getTopLeft(arama), konum);
    expect(find.byTooltip('Ana Sayfa'), findsNothing);
    expect(find.byTooltip('Bildirimler'), findsOneWidget);
    await t.tap(arama);
    await t.enterText(arama, 'Ada');
    await t.pumpAndSettle();
    expect(find.text('Ada Yılmaz'), findsOneWidget);
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    await t.pumpAndSettle();
    expect(t.getBottomRight(arama).dy, lessThanOrEqualTo(844 - 280));
    t.view.resetViewInsets();
    await t.tap(find.byTooltip('Ana sayfaya dön'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(arama).controller!.text, isEmpty);
    expect(find.text('Modüller'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'bildirim sayısı uydurulmaz, profil ve ayarlar üst menüden açılır',
    (t) async {
      await ac(t);
      expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, false);
      await dokun(t, find.byTooltip('Bildirimler'));
      expect(find.text('Henüz bildirim yok.'), findsOneWidget);
      await dokun(t, find.byTooltip('Kapat'));
      await menu(t, 'Profilim');
      expect(find.byType(BireyselKurulumScreen), findsOneWidget);
      expect(find.text('Profilim'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      final f = find.widgetWithText(TextField, 'Ad Soyad *');
      expect(t.widget<TextField>(f).controller!.text, 'Deniz Öğretmen');
      await t.pageBack();
      await t.pumpAndSettle();
      await menu(t, 'Ayarlar');
      expect(find.text('Görünüm'), findsOneWidget);
      expect(find.text('Okul Bilgileri'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('bildirim bileşeni sadece verilen okunmamış sayısını rozetler', (
    t,
  ) async {
    for (final count in [0, 3, 125]) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                AnaSayfaBildirimSimgesi(onPressed: () {}, okunmamis: count),
              ],
            ),
          ),
        ),
      );
      expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, count > 0);
      if (count > 0) {
        expect(find.text(count > 99 ? '99+' : '$count'), findsOneWidget);
      }
    }
  });
  testWidgets('profil kaydı kalıcıdır ve ana sayfaya döner', (t) async {
    await ac(t);
    await menu(t, 'Profilim');
    await t.enterText(
      find.widgetWithText(TextField, 'Ad Soyad *'),
      'Ece Öğretmen',
    );
    await dokun(t, find.text('Kaydet'));
    expect(find.byType(BireyselAnaSayfaScreen), findsOneWidget);
    expect((await BireyselProfilService.getir())!['AdSoyad'], 'Ece Öğretmen');
    expect(t.takeException(), isNull);
  });
  testWidgets('gün ve ders geçişleri ile günlük plan bağlantısı çalışır', (
    t,
  ) async {
    await ac(t);
    if (bugun.weekday > 5) {
      for (var i = 0; i < bugun.weekday - 5; i++) {
        await dokun(t, find.byTooltip('Önceki gün'));
      }
    }
    var kart = t.widget<GunlukDersGorunumu>(find.byType(GunlukDersGorunumu));
    final ilkSira = kart.sira;
    final oncekiVar = kart.oncekiDers != null;
    await dokun(t, find.text('Daralt'));
    await dokun(t, find.text(oncekiVar ? 'Önceki ders' : 'Sonraki ders'));
    kart = t.widget<GunlukDersGorunumu>(find.byType(GunlukDersGorunumu));
    expect(kart.sira, isNot(ilkSira));
    await dokun(t, find.text(oncekiVar ? 'Sonraki ders' : 'Önceki ders'));
    kart = t.widget<GunlukDersGorunumu>(find.byType(GunlukDersGorunumu));
    expect(kart.sira, ilkSira);
    await dokun(t, find.text('Genişlet'));
    expect(kart.onGunlukPlan, isNotNull);
    await dokun(t, find.text('Günlük Plan'), bekle: false);
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(BireyselAnaSayfaScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Ders bilgi formu eksik'), findsOneWidget);
    await t.tap(find.text('Kapat'));
    await t.pumpAndSettle();
    await dokun(t, find.byTooltip('Sonraki gün'));
    expect(find.text('Bugüne dön'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  const hedefler = <String, Type>{
    'Ders Programım': BireyselDersProgramimScreen,
    'Sınıf Rehberliğim': BireyselRehberlikScreen,
    'Ödevlerim': OdevKontrolScreen,
    'Raporlar': RaporOlusturScreen,
    'Not Hesaplama': PerformansNotScreen,
    'Belgelerim': BireyselBelgelerimScreen,
    'Yıllık Planlarım': BireyselYillikPlanlarimScreen,
    'Import Merkezi': ImportMerkeziScreen,
    'Mesajlaşma': MesajlasmaScreen,
    'Test Modülü': TestModuluScreen,
    'Öğrenci İşlemleri': BireyselOgrenciIslemleriScreen,
  };
  for (final e in hedefler.entries) {
    testWidgets('${e.key} gerçek modülüne gider ve geri döner', (t) async {
      await ac(t);
      await dokun(
        t,
        find.byKey(ValueKey('modul-${e.key}')),
        bekle: e.key != 'Belgelerim',
      );
      if (e.key == 'Belgelerim') {
        expect(find.byType(e.value), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.byType(BireyselAnaSayfaScreen), findsOneWidget);
        return;
      }
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle();
      expect(find.byType(e.value), findsOneWidget);
      expect(find.byTooltip('Ana Sayfa'), findsOneWidget);
      expect(find.byTooltip('Bildirimler'), findsOneWidget);
      if (e.key == 'Mesajlaşma' || e.key == 'Ders Programım') {
        await gorsel(
          t,
          e.key == 'Mesajlaşma' ? 'modul_mesajlasma' : 'modul_ders_programim',
        );
      }
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(BireyselAnaSayfaScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('not hesaplama modu geçersizse kayıt açılmaz', (t) async {
    await ac(t);
    final once = await db.query('PerformansTanim');
    await (await SharedPreferences.getInstance()).setString(
      'calisma_modu',
      'kurumsal',
    );
    await dokun(t, find.byKey(const ValueKey('modul-Not Hesaplama')));
    expect(find.byType(PerformansNotScreen), findsNothing);
    expect(find.textContaining('Not hesaplama açılamadı'), findsOneWidget);
    expect(await db.query('PerformansTanim'), once);
    expect(t.takeException(), isNull);
  });
}
