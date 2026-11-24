import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/belge_disari_aktar_service.dart';
import 'package:elpi_okul_yonetim/services/ortak_import_service.dart';
import 'package:elpi_okul_yonetim/screens/veli_bilgileri_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ogrenci_islemleri_screen.dart';
import 'support/windows_memory_database.dart';
import 'package:elpi_okul_yonetim/widgets/ortak_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  late MesajBaglami b;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    mod = CalismaModu.bireyselOgretmen;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
    );
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
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-C',
      'EgitimOgretimYili': '2026-2027',
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
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OgrenciId': 1,
      'OkulNo': '001',
      'Ad': 'Ali',
      'Soyad': 'Test',
      'Telefon': '',
      'AnneAdi': 'Anne Adı',
      'AnneTelefon': '05324445566',
      'BabaAdi': 'Baba Adı',
      'BabaTelefon': '05327778899',
      'VeliTuru': 'Anne',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    b = await service.hazirla();
  });
  tearDown(LocalDatabase.instance.close);

  Future<ImportOnIzleme> onizle(
    Map<String, String> patch, {
    List<Map<String, String>>? beklenen,
  }) async {
    final row = (await service.veliSinifBilgileri(b, 1)).single;
    return service.veliOnizle(b, 1, [
      ImportKaynakSatiri('1', 'satır 2', {...row, ...patch}),
    ], beklenen: beklenen);
  }

  test('boş Excel hücreleri silmez, kimlik ve diğer veli korunur', () async {
    await db.update('Ogrenci', {
      'VeliAdi': 'Eski Yakın',
      'VeliTelefonu': '05321112233',
    }, where: 'OgrenciId=1');
    final p = await onizle({
      'Telefon': '05320000001',
      'AnneAdi': '',
      'AnneTelefon': '',
      'VeliTuru': 'Baba',
      'VeliAdi': '',
      'VeliTelefonu': '',
    });
    expect(p.engeller, isEmpty);
    expect((await db.query('Ogrenci')).single['VeliTuru'], 'Anne');
    await service.veliAktar(p, {'1'});
    final row = (await db.query('Ogrenci')).single;
    expect(row['AnneAdi'], 'Anne Adı');
    expect(row['AnneTelefon'], '05324445566');
    expect(row['VeliAdi'], 'Eski Yakın');
    expect(row['VeliTelefonu'], '05321112233');
    expect(row['VeliTuru'], 'Baba');
    expect(row['OkulNo'], '001');
    expect(row['Ad'], 'Ali');
    expect(row['Telefon'], '05320000001');
    final alici = (await service.aliciAdaylari(
      b,
      tur: MesajKisiTuru.veli,
    )).single;
    expect(alici.telefon, '05327778899');
  });

  test(
    'Diğer için ad, yakınlık ve telefon zorunlu, türler arasında veri korunur',
    () async {
      expect((await onizle({'VeliTuru': 'Diğer'})).engeller, isNotEmpty);
      final p = await onizle({
        'VeliTuru': 'Diğer',
        'VeliAdi': 'Ayşe Yılmaz',
        'VeliYakinlik': 'Teyzesi',
        'VeliTelefonu': '05321112233',
      });
      expect(p.engeller, isEmpty);
      await service.veliAktar(p, {'1'});
      expect(
        (await service.veliSinifBilgileri(b, 1)).single['VeliYakinlik'],
        'Teyzesi',
      );
      expect((await db.query('Ogrenci')).single['VeliTuru'], 'Diger');
      final anne = await onizle({'VeliTuru': 'Anne'});
      await service.veliAktar(anne, {'1'});
      final row = (await service.veliSinifBilgileri(b, 1)).single;
      expect(row['VeliAdi'], 'Ayşe Yılmaz');
      expect(row['VeliYakinlik'], 'Teyzesi');
    },
  );

  test(
    'kimlik, ad, numara, sınıf, okul, profil ve yıl değişikliği reddedilir',
    () async {
      for (final k in VeliBilgileriIslemleri.kimlikler.keys) {
        final p = await onizle({k: 'değiştirildi', 'Telefon': '05320000001'});
        expect(p.engeller, isNotEmpty, reason: k);
        await expectLater(service.veliAktar(p, {'1'}), throwsStateError);
      }
      expect((await db.query('Ogrenci')).single['Telefon'], '');
    },
  );

  test('tekrarlı ve geçersiz satırlar bloklanır; boş seçim yazmaz', () async {
    final row = (await service.veliSinifBilgileri(b, 1)).single;
    final p = await service.veliOnizle(b, 1, [
      ImportKaynakSatiri('a', '2', {...row, 'Telefon': '05320000001'}),
      ImportKaynakSatiri('b', '3', {...row, 'Telefon': '05320000002'}),
    ]);
    expect(p.kayitlar.every((r) => r.durum == ImportDurumu.hatali), isTrue);
    expect((await onizle({'AnneTelefon': 'abc'})).engeller, isNotEmpty);
    final uygun = await onizle({'Telefon': '05320000001'});
    await expectLater(service.veliAktar(uygun, {}), throwsStateError);
    expect((await onizle({})).kayitlar.single.durum, ImportDurumu.atlanan);
  });

  test(
    'önizleme sonrası veri değişirse kayıt durur; hızlı giriş eski görüntüyü reddeder',
    () async {
      final once = await service.veliSinifBilgileri(b, 1);
      final p = await onizle({'Telefon': '05320000001'});
      await db.update('Ogrenci', {
        'AnneAdi': 'Başka güncelleme',
      }, where: 'OgrenciId=1');
      await expectLater(service.veliAktar(p, {'1'}), throwsStateError);
      expect(
        (await onizle({'Telefon': '05320000001'}, beklenen: once)).engeller,
        isNotEmpty,
      );
      expect((await db.query('Ogrenci')).single['Telefon'], '');
    },
  );

  test('geçersiz moda ve kaldırılmış ders kapsamına yazılmaz', () async {
    final p = await onizle({'Telefon': '05320000001'});
    mod = null;
    await expectLater(service.veliAktar(p, {'1'}), throwsStateError);
    mod = CalismaModu.bireyselOgretmen;
    await db.update('DersProgrami', {'Aktif': 0});
    await expectLater(service.veliAktar(p, {'1'}), throwsStateError);
    expect((await db.query('Ogrenci')).single['Telefon'], '');
  });

  test('önizleme sonrası profil ve yıl değişikliği reddedilir', () async {
    final p = await onizle({'Telefon': '05320000001'});
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
    await expectLater(service.veliAktar(p, {'1'}), throwsStateError);
  });

  test('dolu Excel ortak okuyucuyla kimlik ve sıfır başını korur', () async {
    final tanim = service.veliImportTanimi(b, 1);
    final row = (await service.veliSinifBilgileri(b, 1)).single;
    final bytes = await BelgeDisariAktarService.excelOlustur(tanim, [
      ImportKaydi('1', '', {...row, 'Telefon': '05320000001'}),
    ], sablon: true);
    final tablolar = await OrtakImportService.oku(
      ImportDosya('veli.xlsx', bytes),
    );
    expect(tablolar, isNotEmpty);
    expect(tablolar.first.satirlar.first.take(3), ['Okul No', 'Ad', 'Soyad']);
    expect(tablolar.first.satirlar[1], contains('001'));
    final tablo = tablolar.first;
    final baslik = tablo.baslikBul(tanim);
    final esleme = tablo.otomatikEsle(tanim, baslik);
    expect(tablo.eslemeHatalari(tanim, baslik, esleme), isEmpty);
    final p = await tanim.hazirla(tablo.esle(baslik, esleme));
    expect(p.engeller, isEmpty);
    await tanim.aktar(p, p.kayitlar.map((r) => r.id).toSet());
    expect((await db.query('Ogrenci')).single['Telefon'], '05320000001');
  });

  test('toplu kayıt hatasında önceki güncellemeler de geri alınır', () async {
    await db.insert('Ogrenci', {
      'OgrenciId': 2,
      'OkulNo': '002',
      'Ad': 'Ece',
      'Soyad': 'Test',
      'OlusturmaTarihi': 'test',
      'VeliTuru': 'Anne',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 2,
      'SinifSubeId': 1,
      'EgitimOgretimYili': b.yil,
      'OlusturmaTarihi': 'test',
    });
    final rows = await service.veliSinifBilgileri(b, 1);
    final p = await service.veliOnizle(b, 1, [
      for (final r in rows)
        ImportKaynakSatiri(r['OgrenciId']!, '', {
          ...r,
          'Telefon': '05320000001',
        }),
    ]);
    await db.execute(
      "CREATE TRIGGER fail_second BEFORE UPDATE ON Ogrenci WHEN NEW.OgrenciId=2 BEGIN SELECT RAISE(ABORT, 'test rollback'); END",
    );
    await expectLater(service.veliAktar(p, {'1', '2'}), throwsStateError);
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=1')).single['Telefon'],
      '',
    );
  });

  testWidgets('gerçek Flutter ekran görüntüleri ve büyük yazı kontrolü', (
    t,
  ) async {
    t.view.physicalSize = const Size(400, 950);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final loader = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final key = GlobalKey();
    for (final tur in ['hizli', 'excel', 'ogrenci']) {
      await t.pumpWidget(
        MaterialApp(
          theme: OrtakUi.tema(
            ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: tur == 'ogrenci'
                ? const BireyselOgrenciIslemleriScreen()
                : VeliBilgileriScreen(service: service, excel: tur == 'excel'),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('/tmp/veli-ui').create(recursive: true);
        await File(
          '/tmp/veli-ui/$tur.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    }
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: VeliBilgileriScreen(service: service, excel: true),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'hızlı giriş önizleme ve onay olmadan yazmaz; onaydan sonra kalıcıdır',
    (t) async {
      await t.pumpWidget(
        MaterialApp(home: VeliBilgileriScreen(service: service)),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('1:Telefon')), '05320000001');
      await t.pump();
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      expect(find.text('Değişiklikleri onaylayın'), findsOneWidget);
      expect((await db.query('Ogrenci')).single['Telefon'], '');
      await t.tap(find.text('Geri'));
      await t.pumpAndSettle();
      expect((await db.query('Ogrenci')).single['Telefon'], '');
      await t.pump();
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      await t.tap(find.text('Onayla ve Kaydet'));
      await t.pumpAndSettle();
      expect((await db.query('Ogrenci')).single['Telefon'], '05320000001');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        MaterialApp(home: VeliBilgileriScreen(service: service)),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('1:Telefon')))
            .controller!
            .text,
        '05320000001',
      );
    },
  );

  testWidgets('iptal kayıtsız taslağı koruma onayı ister ve veri yazmaz', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => VeliBilgileriScreen(service: service),
                ),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Aç'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('1:Telefon')), '05320000001');
    await t.pump();
    await t.tap(find.text('İptal'));
    await t.pumpAndSettle();
    expect(find.text('Değişikliklerden vazgeçilsin mi?'), findsOneWidget);
    await t.tap(find.text('Düzenlemeye dön'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('1:Telefon')))
          .controller!
          .text,
      '05320000001',
    );
    await t.pump();
    await t.tap(find.text('İptal'));
    await t.pumpAndSettle();
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(find.text('Aç'), findsOneWidget);
    expect((await db.query('Ogrenci')).single['Telefon'], '');
  });

  testWidgets('40 öğrenci, büyütülmüş yazı, klavye ve son satır erişimi', (
    t,
  ) async {
    for (var id = 2; id <= 40; id++) {
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '$id',
        'Ad': 'Uzun Öğrenci Adı $id',
        'Soyad': 'Uzunsoyadı',
        'VeliTuru': 'Anne',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': id,
        'SinifSubeId': 1,
        'EgitimOgretimYili': b.yil,
        'OlusturmaTarihi': 'test',
      });
    }
    t.view.physicalSize = const Size(320, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: VeliBilgileriScreen(service: service),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('40:Telefon')),
      500,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 100,
    );
    await t.tap(find.byKey(const ValueKey('40:Telefon')));
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(find.text('Kaydet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final width in [320.0, 400.0, 900.0]) {
    testWidgets(
      'hızlı giriş $width genişlikte açılır, arama ve iptal veri yazmaz',
      (t) async {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(home: VeliBilgileriScreen(service: service)),
        );
        await t.pumpAndSettle();
        expect(find.text('001 - Ali Test'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.enterText(
          find.byKey(const ValueKey('1:Telefon')),
          '05320000001',
        );
        expect((await db.query('Ogrenci')).single['Telefon'], '');
        await t.enterText(
          find.widgetWithText(TextField, 'Öğrenci ara…'),
          'bulunmaz',
        );
        await t.pumpAndSettle();
        expect(find.text('Arama sonucu yok.'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('öğrenci ve form sekmesi korunur, veli girişine erişilir', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: BireyselOgrenciIslemleriScreen(
          ogrenciler: Text('mevcut liste'),
          formlar: Text('mevcut formlar'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('mevcut liste'), findsOneWidget);
    await t.tap(find.text('Form İşlemleri'));
    await t.pumpAndSettle();
    expect(find.text('mevcut formlar'), findsOneWidget);
  });
}
