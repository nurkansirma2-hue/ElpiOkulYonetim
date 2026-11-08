import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/import_kurulum_service.dart';
import 'package:elpi_okul_yonetim/services/fotograf_import_tanimi.dart';
import 'support/windows_memory_database.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/services/calisma_modu_service.dart';
import 'package:elpi_okul_yonetim/screens/import_merkezi_screen.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
  });
  tearDown(LocalDatabase.instance.close);
  Future<void> profil() async {
    await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
      'EgitimYili': '2026-2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Profil',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
  }

  Future<void> tikla(WidgetTester t, String text) async {
    final f = find.text(text);
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'ilk kurulum otomatik açılır; çıkış hatırlanır ve yeniden başlatılır',
    (t) async {
      await profil();
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const MaterialApp(home: ImportMerkeziScreen()));
      await t.pumpAndSettle();
      expect(find.text('Temel kurulum'), findsOneWidget);
      expect(find.text('Adım 1 / 5'), findsOneWidget);
      await tikla(t, 'Şimdilik atla');
      expect(find.text('Adım 2 / 5'), findsOneWidget);
      expect(find.text('Yıllık plan ve çalışma takvimi'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Dosya seç ve yükle'),
            )
            .onPressed,
        isNull,
      );
      await tikla(t, 'Geri');
      expect(find.text('Adım 1 / 5'), findsOneWidget);
      await t.tap(find.byTooltip('Import Merkezi’ne dön'));
      await t.pumpAndSettle();
      expect(find.text('Verilerinizi hazırlayın'), findsOneWidget);
      expect((await ImportKurulumService().getir())!.otomatik, false);
      await tikla(t, 'Adım adım kurulum');
      expect(find.text('Temel kurulum'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Verilerinizi hazırlayın'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(const MaterialApp(home: ImportMerkeziScreen()));
      await t.pumpAndSettle();
      expect(find.text('Temel kurulum'), findsNothing);
      expect(find.text('Verilerinizi hazırlayın'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  test(
    'kurulum durumu aktif profil ve yılı izler; kayıtları değiştirmez',
    () async {
      await profil();
      final service = ImportKurulumService();
      expect((await service.getir())!.sayilar, [0, 0, 0, 0]);
      await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
      await db.insert('DersSaati', {'SiraNo': 1});
      await db.insert('SinifSube', {
        'SinifSubeId': 1,
        'SinifKodu': '9/A',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': 1,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      final durum = (await service.getir())!;
      expect(durum.sayilar, [1, 0, 0, 0]);
      expect(durum.otomatik, false);
      for (final id in [1, 2]) {
        await db.insert('Ogrenci', {
          'OgrenciId': id,
          'OkulNo': '$id',
          'Ad': 'Öğrenci',
          'Soyad': 'Test',
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciSinifKayit', {
          'OgrenciId': id,
          'SinifSubeId': 1,
          'EgitimOgretimYili': id == 1 ? '2026-2027' : '2025-2026',
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciFotograf', {
          'OgrenciId': id,
          'DosyaYolu': 'foto.jpg',
          'OlusturmaTarihi': 'test',
        });
      }
      const kisi = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await db.insert('MesajOgretmenKisi', {
        'KisiId': kisi,
        'OkulId': 'okul',
        'SahipProfilId': 1,
        'AdSoyad': 'Ders Öğretmeni',
        'OlusturmaTarihi': 'test',
        'GuncellemeTarihi': 'test',
      });
      await db.insert('MesajOgretmenSinif', {
        'KisiId': kisi,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'Kaynak': 'DersProgrami',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('MesajOgretmenSinifDers', {
        'KisiId': kisi,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'DersId': 1,
      });
      expect((await service.getir())!.sayilar, [1, 1, 1, 1]);
      await service.kapat(durum);
      expect(await db.query('DersProgrami'), hasLength(1));
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Yeni profil',
        'OkulAdi': 'Okul',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      expect((await service.getir())!.sayilar, [0, 0, 0, 0]);
      expect((await service.getir())!.otomatik, true);
    },
  );

  testWidgets('geçersiz oturum import merkezinden işlem başlatamaz', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calisma_modu', 'gecersiz');
    await t.pumpWidget(const MaterialApp(home: ImportMerkeziScreen()));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Uygulamayı yeniden başlatın'),
      findsOneWidget,
    );
    expect(find.text('Öğrenci listeleri'), findsNothing);
  });
  testWidgets('dar ekranda merkez mevcut öğrenci importunu açar', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await CalismaModuService.kaydet(CalismaModu.bireyselOgretmen);
    await t.pumpWidget(const MaterialApp(home: ImportMerkeziScreen()));
    await t.pumpAndSettle();
    final grup = find.byKey(const ValueKey('import-ogrenciler-karti'));
    expect(
      find.descendant(of: grup, matching: find.text('Öğrenci listeleri')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: grup, matching: find.text('Öğrenci fotoğrafları')),
      findsNothing,
    );
    expect(
      t.getTopLeft(find.text('Ders programım')).dy,
      lessThan(t.getTopLeft(find.text('Yıllık plan ve çalışma takvimi')).dy),
    );
    expect(
      t.getTopLeft(find.text('Yıllık plan ve çalışma takvimi')).dy,
      lessThan(t.getTopLeft(find.text('Öğrenci listeleri')).dy),
    );
    final f = find.text('Öğrenci listeleri');
    await t.scrollUntilVisible(
      f,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
    expect(find.byType(OrtakImportScreen), findsNothing);
    expect(find.text('Öğrenci listesi'), findsOneWidget);
    expect(find.text('Resimli liste'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Öğrenci listesi')).dy,
      lessThan(t.getTopLeft(find.text('Resimli liste')).dy),
    );
    await tikla(t, 'Öğrenci listesi');
    expect(find.byType(OrtakImportScreen), findsOneWidget);
    expect(find.text('Dosya Seç'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tikla(t, 'Resimli liste');
    expect(
      t.widget<OrtakImportScreen>(find.byType(OrtakImportScreen)).tanim,
      same(FotografImportTanimi.tanim),
    );
    expect(find.text('Dosya Seç'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
