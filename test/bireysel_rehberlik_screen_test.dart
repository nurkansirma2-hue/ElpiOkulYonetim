import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_rehberlik_screen.dart';
import 'support/windows_memory_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifKodu': '9/A',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
  });
  tearDown(() => LocalDatabase.instance.close());

  Future<void> ac(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BireyselRehberlikScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> dokun(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    // Servisin kalıcı işlem kuyruğu gerçek async ortamında tamamlanır;
    // önceki widget testinin sanal saatine bağlı Future bırakılmaz.
    await tester.runAsync(() async {
      await tester.tap(find.text(text).last);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  Future<void> yeni(WidgetTester tester) async {
    await dokun(tester, 'Yeni atama');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await dokun(tester, '9/A');
  }

  Future<int> atama({String baslangic = '2000-01-01', String? bitis}) =>
      db.insert('RehberlikAtama', {
        'OkulId': 'okul',
        'OgretmenProfilId': 1,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026/2027',
        'BaslangicTarihi': baslangic,
        'BitisTarihi': bitis,
        'OlusturmaTarihi': 'test',
      });

  testWidgets(
    'Rehberlik öğrencileri dar ekranda mevcut veli bilgileriyle açılır',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await atama();
      for (var i = 1; i <= 3; i++) {
        await db.insert('Ogrenci', {
          'OkulNo': '$i',
          'Ad': 'Öğrenci$i',
          'Soyad': 'Soyad',
          'VeliAdi': 'Veli$i',
          'VeliTelefonu': '05550000000',
          'Aktif': i == 3 ? 0 : 1,
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciSinifKayit', {
          'OgrenciId': i,
          'SinifSubeId': 1,
          'EgitimOgretimYili': i == 2 ? '2025/2026' : '2026/2027',
          'OlusturmaTarihi': 'test',
        });
      }
      await ac(tester);
      await dokun(tester, 'Öğrencilerim');
      expect(find.text('Öğrenci1 Soyad'), findsOneWidget);
      expect(find.text('Veli: Veli1'), findsOneWidget);
      expect(find.text('Telefon: 05550000000'), findsOneWidget);
      expect(find.text('Öğrenci2 Soyad'), findsNothing);
      expect(find.text('Öğrenci3 Soyad'), findsNothing);
      expect(tester.takeException(), isNull);
      await db.update('RehberlikAtama', {'BitisTarihi': '2000-01-02'});
      await tester.tap(find.byTooltip('Yenile'));
      await tester.pumpAndSettle();
      expect(find.text('Öğrenci1 Soyad'), findsNothing);
      expect(find.textContaining('Bugün geçerli'), findsOneWidget);
    },
  );

  testWidgets('Boş liste ve gelecekteki atama erişimi', (tester) async {
    await atama();
    await ac(tester);
    await dokun(tester, 'Öğrencilerim');
    expect(find.textContaining('aktif öğrenci bulunmuyor'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await db.update('RehberlikAtama', {'BaslangicTarihi': '9999-01-01'});
    await dokun(tester, 'Öğrencilerim');
    expect(find.textContaining('Bugün geçerli'), findsOneWidget);
  });

  test(
    'Öğrenci okuma sahibi, yıl, mod ve gün dahil sınırını doğrular',
    () async {
      final bugun = DateTime.now().toIso8601String().substring(0, 10);
      final id = await atama(baslangic: bugun, bitis: bugun);
      final service = BireyselRehberlikService.instance;
      final b = await service.hazirla();
      expect(await service.ogrencileriGetir(b, atamaId: id), isEmpty);
      await expectLater(
        service.ogrencileriGetir(b, atamaId: id + 1),
        throwsStateError,
      );
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Başka',
        'OkulAdi': 'Okul',
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await expectLater(
        service.ogrencileriGetir(b, atamaId: id),
        throwsStateError,
      );
      final yeni = await service.hazirla();
      await expectLater(
        service.ogrencileriGetir(yeni, atamaId: id),
        throwsStateError,
      );
      await db.update('OgretmenProfil', {
        'Aktif': 0,
      }, where: 'OgretmenProfilId = 2');
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
      await expectLater(
        service.ogrencileriGetir(await service.hazirla(), atamaId: id),
        throwsStateError,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('calisma_modu', 'kurumsal');
      await expectLater(
        service.ogrencileriGetir(b, atamaId: id),
        throwsStateError,
      );
    },
  );

  testWidgets('Dar ekranda sınıf doğrulaması, kayıt ve çift tıklama güvenli', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await ac(tester);
    final yeniAtama = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Yeni atama'))
        .onPressed!;
    await tester.runAsync(() async {
      yeniAtama();
      yeniAtama();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await dokun(tester, 'Kaydet');
    expect(find.text('Sınıf seçin.'), findsOneWidget);
    expect(await db.query('RehberlikAtama'), isEmpty);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await dokun(tester, '9/A');
    await dokun(tester, 'Kaydet');
    expect(await db.query('RehberlikAtama'), hasLength(1));
    expect(find.text('Rehberlik ataması kaydedildi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sonlandırma iptali korur; tarih ve onay sonrası kayıt kapanır', (
    tester,
  ) async {
    await ac(tester);
    await yeni(tester);
    await dokun(tester, 'Kaydet');
    await dokun(tester, 'Atamayı sonlandır');
    await dokun(tester, 'Seç');
    await dokun(tester, 'İptal');
    expect((await db.query('RehberlikAtama')).single['BitisTarihi'], isNull);
    await dokun(tester, 'Atamayı sonlandır');
    await dokun(tester, 'Seç');
    await dokun(tester, 'Sonlandır');
    expect((await db.query('RehberlikAtama')).single['BitisTarihi'], isNotNull);
    expect(find.text('Atamayı sonlandır'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Değişmiş oturum yazamaz; yenileme güncel bağlamı getirir', (
    tester,
  ) async {
    await ac(tester);
    await yeni(tester);
    await db.update('OgretmenProfil', {'AdSoyad': 'Yeni öğretmen'});
    await dokun(tester, 'Kaydet');
    expect(find.textContaining('Atama kaydedilemedi.'), findsOneWidget);
    expect(await db.query('RehberlikAtama'), isEmpty);
    await tester.tap(find.byTooltip('Yenile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Yeni öğretmen'), findsOneWidget);
  });

  testWidgets('Derssiz ve kurumsal mod durumunda kayıt açılamaz', (
    tester,
  ) async {
    await db.update('DersProgrami', {'Aktif': 0});
    await ac(tester);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Yeni atama'))
          .onPressed,
      isNull,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calisma_modu', 'kurumsal');
    await tester.tap(find.byTooltip('Yenile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Atamalar okunamadı.'), findsOneWidget);
    expect(find.text('Yeni atama'), findsNothing);
  });

  testWidgets('Bireysel ana menü kartı modülü açar ve geri dönülür', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: BireyselAnaSayfaScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.scrollUntilVisible(
      find.text('Sınıf Rehberliğim'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await dokun(tester, 'Sınıf Rehberliğim');
    expect(find.byType(BireyselRehberlikScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BireyselAnaSayfaScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
