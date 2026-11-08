import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/calisma_modu_service.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/ogretmen_programi_pdf_okuyucu.dart';
import 'package:elpi_okul_yonetim/services/ogretmen_programi_import_tanimi.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'support/windows_memory_database.dart';
import 'package:elpi_okul_yonetim/widgets/program_import_kapsam_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  late MesajBaglami b;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    mod = CalismaModu.bireyselOgretmen;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
      whatsappAc: (_, _) async => fail('Gerçek gönderim başlamamalı'),
      smsGonder: (_, _) async {
        fail('SMS başlamamalı');
      },
    );
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
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    for (final i in [1, 2, 3]) {
      await db.insert('SinifSube', {
        'SinifSubeId': i,
        'SinifKodu': ['9/A', '9/B', '9/C'][i - 1],
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      if (i < 3) {
        await db.insert('DersProgrami', {
          'SinifSubeId': i,
          'DersId': 1,
          'DersSaatiId': 1,
          'Gun': i == 1 ? 'Pazartesi' : 'Salı',
          'OgretmenProfilId': 1,
          'EgitimOgretimYili': '2026-2027',
          'OlusturmaTarihi': 'test',
        });
      }
    }
    b = await service.hazirla();
  });
  tearDown(() async {
    await LocalDatabase.instance.close();
  });
  ImportKaynakSatiri row(
    String id, {
    String ad = 'Ayşe Yılmaz',
    String sinif = '9-A',
    String yil = '2026-2027',
    String? blok,
  }) => ImportKaynakSatiri(id, 'Sayfa 1', {
    'ogretmen': ad,
    'dersler': 'Ders',
    'sinif': sinif,
    'yil': yil,
    'okul': 'Okul',
    'blok': blok ?? ad,
  });
  Future<ImportOnIzleme> preview(
    List<ImportKaynakSatiri> rows, {
    int sinif = 1,
  }) => service.ogretmenProgramiOnIzleme(b, rows, sinifId: sinif);
  Future<ImportOzet> aktar(ImportOnIzleme p) => service.ogretmenProgramiAktar(
    b,
    p,
    p.kayitlar.where((r) => r.aktarilabilir).map((r) => r.id).toSet(),
  );

  test(
    'PDF iki programı ayırır; tekrar saatleri ve dipnot sınıfını ilişki saymaz',
    () {
      final rows = OgretmenProgramiPdfOkuyucu.metindenOku([
        '''
Sayın AYŞE YILMAZ
Matematik
9-A
9-A
10-D
2026/2027 eğitim öğretim yılı
Haftalık Ders Programı
Sınıf Öğretmenliği
12-F
Sayın ÖMER ÇELİK
Türk Dili
9-B
2026-2027
Haftalık Ders Programı
''',
      ]);
      expect(rows, hasLength(3));
      expect(
        rows
            .where((r) => r.degerler['ogretmen'] == 'AYŞE YILMAZ')
            .map((r) => r.degerler['sinif']),
        ['9-A', '10-D'],
      );
      expect(rows.last.degerler['ogretmen'], 'ÖMER ÇELİK');
      expect(rows.every((r) => r.degerler['yil'] == '2026-2027'), true);
    },
  );
  test('tarama, sınıf programı, aşırı sayfa ve sahte PDF reddedilir', () async {
    expect(
      () => OgretmenProgramiPdfOkuyucu.metindenOku(['Tarama']),
      throwsFormatException,
    );
    expect(
      () => OgretmenProgramiPdfOkuyucu.metindenOku(List.filled(101, '')),
      throwsFormatException,
    );
    await expectLater(
      OgretmenProgramiPdfOkuyucu.oku(
        ImportDosya('x.pdf', Uint8List.fromList([1, 2, 3])),
      ),
      throwsFormatException,
    );
    expect(
      () => OgretmenProgramiPdfOkuyucu.metindenOku([
        '9-A Haftalık Ders Programı Pazartesi Ayşe Yılmaz',
      ]),
      throwsFormatException,
    );
  });
  test(
    'seçili sınıf ve yıl dışındakiler kaydedilemez; ön izleme kayıt yazmaz',
    () async {
      final p = await preview([
        row('a'),
        row('b', sinif: '9/B'),
        row('c', yil: '2025-2026'),
      ]);
      expect(p.kayitlar.map((r) => r.durum), [
        ImportDurumu.uygun,
        ImportDurumu.atlanan,
        ImportDurumu.hatali,
      ]);
      expect(await db.query('MesajOgretmenKisi'), isEmpty);
      await expectLater(
        () => service.ogretmenProgramiAktar(b, p, {'b'}),
        throwsStateError,
      );
      await expectLater(preview([row('a')], sinif: 3), throwsStateError);
      await aktar(p);
      expect((await db.query('MesajOgretmenSinif')).single['SinifSubeId'], 1);
      expect(
        (await db.query('MesajOgretmenSinif')).single['Kaynak'],
        'DersProgrami',
      );
      expect(await db.query('DersProgrami'), hasLength(2));
    },
  );
  test(
    'yeniden import mükerrer kişi üretmez; telefon ve önceki sınıfı korunur',
    () async {
      final id = await service.ogretmenIletisimKaydet(
        b,
        ad: 'Ayşe Yılmaz',
        telefon: '05320000000',
        sinifIdleri: {2},
        sinifIliskileriniDogruladim: true,
      );
      var p = await preview([row('a')]);
      expect(p.kayitlar.single.durum, ImportDurumu.uyarili);
      await aktar(p);
      p = await preview([row('a')]);
      final sonuc = await aktar(p);
      expect(sonuc.eklenen, 0);
      expect(sonuc.guncellenen, 0);
      expect(await db.query('MesajOgretmenKisi'), hasLength(1));
      expect(
        (await db.query('MesajOgretmenKisi')).single['Telefon'],
        '05320000000',
      );
      expect((await db.query('MesajOgretmenKisi')).single['KisiId'], id);
      expect(await db.query('MesajOgretmenSinif'), hasLength(2));
      expect(
        await service.aliciAdaylari(b, tur: MesajKisiTuru.ogretmen, sinifId: 1),
        hasLength(1),
      );
    },
  );
  test(
    'tekrar bloklar uyarılıdır; geçici ad düzeltilmeden kaydedilemez',
    () async {
      final p = await preview([
        row('a'),
        row('b', blok: 'ikinci'),
        row('c', ad: 'BÜRO ÖĞRT 1'),
      ]);
      expect(p.kayitlar.map((r) => r.durum), [
        ImportDurumu.uyarili,
        ImportDurumu.uyarili,
        ImportDurumu.hatali,
      ]);
      final yeni = await service.ogretmenProgramiDuzenle(b, p, [
        row('a'),
        row('b', blok: 'ikinci'),
        row('c', ad: 'Ömer Çelik'),
      ]);
      await aktar(yeni);
      expect(await db.query('MesajOgretmenKisi'), hasLength(2));
      expect(await db.query('MesajOgretmenSinif'), hasLength(2));
    },
  );
  test('aynı adlı farklı mevcut kişiler otomatik birleştirilmez', () async {
    for (final tel in ['05320000001', '05320000002']) {
      await service.ogretmenIletisimKaydet(
        b,
        ad: 'Ayşe Yılmaz',
        telefon: tel,
        sinifIdleri: {2},
        sinifIliskileriniDogruladim: true,
      );
    }
    final p = await preview([row('a')]);
    expect(p.kayitlar.single.durum, ImportDurumu.hatali);
    await expectLater(
      () => service.ogretmenProgramiAktar(b, p, {'a'}),
      throwsStateError,
    );
    expect(await db.query('MesajOgretmenSinif'), hasLength(2));
  });
  test(
    'ön izleme sonrası rehber veya ders kapsamı değişirse yazma başlamaz',
    () async {
      var p = await preview([row('a')]);
      await service.ogretmenIletisimKaydet(
        b,
        ad: 'Başka Kişi',
        sinifIdleri: {2},
        sinifIliskileriniDogruladim: true,
      );
      await expectLater(aktar(p), throwsStateError);
      p = await preview([row('a')]);
      await db.update('DersProgrami', {'Aktif': 0}, where: 'SinifSubeId=1');
      await expectLater(aktar(p), throwsStateError);
      expect(await db.query('MesajOgretmenKisi'), hasLength(1));
    },
  );
  test(
    'düzenleme kaynak eğitim yılını değiştiremez; mod ve sahip kontrol edilir',
    () async {
      final p = await preview([row('a', yil: '2025-2026')]);
      final yeni = await service.ogretmenProgramiDuzenle(b, p, [row('a')]);
      expect(yeni.kayitlar.single.durum, ImportDurumu.hatali);
      mod = null;
      await expectLater(preview([row('a')]), throwsStateError);
      mod = CalismaModu.bireyselOgretmen;
      final gecerli = await preview([row('a')]);
      await db.update('OgretmenProfil', {'AdSoyad': 'Yeni Profil'});
      await expectLater(aktar(gecerli), throwsStateError);
      expect(await db.query('MesajOgretmenKisi'), isEmpty);
    },
  );

  test(
    'bir ilişki kaydı başarısız olursa tüm yeni kişiler geri alınır',
    () async {
      final p = await preview([row('a'), row('b', ad: 'Ömer Çelik')]);
      await db.execute(
        '''CREATE TRIGGER import_deneme BEFORE INSERT ON MesajOgretmenSinif
      WHEN (SELECT AdSoyad FROM MesajOgretmenKisi WHERE KisiId=NEW.KisiId)='Ömer Çelik'
      BEGIN SELECT RAISE(ABORT, 'Deneme kayıt hatası'); END''',
      );
      await expectLater(aktar(p), throwsA(anything));
      expect(await db.query('MesajOgretmenKisi'), isEmpty);
      expect(await db.query('MesajOgretmenSinif'), isEmpty);
    },
  );

  Future<void> dokun(WidgetTester t, String text) async {
    final f = find.text(text);
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(f.last);
    await t.pump();
    await t.tap(f.last);
    await t.pump(const Duration(milliseconds: 350));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump();
    if (find.byType(AlertDialog).evaluate().isEmpty) {
      await t.pumpAndSettle();
    }
  }

  testWidgets('ortak import ön izleme ve son onay olmadan kaydetmez', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final tanim = OgretmenProgramiImportTanimi.olustur(
      service,
      b,
      1,
      pdfOku: (_) async => [row('a')],
    );
    await t.pumpWidget(
      MaterialApp(
        home: OrtakImportScreen(
          tanim: tanim,
          birlesikKaynakSecimi: true,
          baslangicDosyasi: ImportDosya(
            'Program.pdf',
            Uint8List.fromList('%PDF-test'.codeUnits),
          ),
        ),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pump(const Duration(milliseconds: 100));
      if (find.text('Ön İzleme Hazırla').evaluate().isNotEmpty) break;
    }
    await t.pumpAndSettle();
    expect(find.text('Örnek Şablon ve Gerekli Alanlar'), findsOneWidget);
    await dokun(t, 'Ön İzleme Hazırla');
    expect(await db.query('MesajOgretmenKisi'), isEmpty);
    await dokun(t, '1 Seçili Kaydı Aktar');
    await dokun(t, 'Vazgeç');
    expect(await db.query('MesajOgretmenKisi'), isEmpty);
    await dokun(t, '1 Seçili Kaydı Aktar');
    await dokun(t, 'Onayla ve Aktar');
    expect(
      (await db.query('MesajOgretmenKisi')).single['AdSoyad'],
      'Ayşe Yılmaz',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'mesajlaşmadan ortak üç kaynak girişine ulaşılır; iptalde mesaj taslağı korunur',
    (t) async {
      await t.pumpWidget(MaterialApp(home: MesajlasmaScreen(service: service)));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('programdan-ogretmen-aktar')),
        findsNothing,
      );
      final mesaj = find.widgetWithText(TextField, 'Mesajınız');
      await t.scrollUntilVisible(
        mesaj,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(mesaj, 'Korunan mesaj');
      final sinif = find.byType(DropdownButton<int>);
      await t.scrollUntilVisible(
        sinif,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(sinif);
      await t.pumpAndSettle();
      await dokun(t, '9/A');
      await dokun(t, 'Sınıfta derse giren öğretmenler');
      expect(find.text('Import Merkezi'), findsOneWidget);
      await dokun(t, 'Sınıf öğretmenleri ve dersleri');
      await dokun(t, 'Dosya seç ve aktar');
      expect(find.text('Dosya Seç'), findsOneWidget);
      await dokun(t, 'Dosya Seç');
      expect(find.text('Cihazımdan Seç'), findsOneWidget);
      expect(find.text('Belgelerimden Seç'), findsOneWidget);
      await dokun(t, 'İptal');
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        mesaj,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.widget<TextField>(mesaj).controller!.text, 'Korunan mesaj');
      expect(await db.query('MesajOgretmenKisi'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  test(
    'diğer sınıflar onayı kapsam içindeki bağları doğru sınıfa kaydeder',
    () async {
      final p = await service.ogretmenProgramiOnIzleme(
        b,
        [row('a'), row('b', sinif: '9-B'), row('c', sinif: '9-C')],
        sinifId: 1,
        digerSiniflar: true,
      );
      expect(p.kayitlar.map((r) => r.durum), [
        ImportDurumu.uygun,
        ImportDurumu.uygun,
        ImportDurumu.atlanan,
      ]);
      final yeni = await service.ogretmenProgramiDuzenle(b, p, [
        row('a'),
        row('b', sinif: '9-B'),
        row('c', sinif: '9-C'),
      ]);
      await aktar(yeni);
      expect(await db.query('MesajOgretmenKisi'), hasLength(1));
      expect(
        (await db.query(
          'MesajOgretmenSinif',
        )).map((r) => r['SinifSubeId']).toSet(),
        {1, 2},
      );
      final tekrar = await service.ogretmenProgramiOnIzleme(
        b,
        [row('a'), row('b', sinif: '9-B')],
        sinifId: 1,
        digerSiniflar: true,
      );
      final sonuc = await aktar(tekrar);
      expect(sonuc.guncellenen, 0);
      expect(await db.query('DersProgrami'), hasLength(2));
    },
  );

  for (final secim in ['Vazgeç', 'Yalnız 9/A', 'Diğer sınıfları da dahil et']) {
    testWidgets('diğer sınıflar sorusu: $secim; onay öncesinde yazmaz', (
      t,
    ) async {
      ImportOnIzleme? p;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  p = await ProgramImportKapsamDialog.hazirla(
                    c,
                    service,
                    b,
                    1,
                    ImportDosya('x.pdf', Uint8List(0)),
                    oku: (_) async => [row('a'), row('b', sinif: '9-B')],
                  );
                },
                child: const Text('Başlat'),
              ),
            ),
          ),
        ),
      );
      await dokun(t, 'Başlat');
      expect(find.text('Diğer sınıflar da aktarılsın mı?'), findsOneWidget);
      await dokun(t, secim);
      expect(await db.query('MesajOgretmenKisi'), isEmpty);
      if (secim == 'Vazgeç') {
        expect(p, isNull);
      } else {
        expect(
          p!.kayitlar.last.aktarilabilir,
          secim == 'Diğer sınıfları da dahil et',
        );
      }
    });
  }
  test(
    'aynı öğretmenin dersleri sınıfa göre tutulur; yeniden import ve telefon düzenleme korur',
    () async {
      ImportKaynakSatiri ders(String id, String sinif, String ad) =>
          ImportKaynakSatiri(id, 'Test', {
            ...row(id, sinif: sinif).degerler,
            'dersler': ad,
          });
      final kaynak = [
        ders('a', '9-A', 'Matematik\nRehberlik'),
        ders('b', '9-B', 'Geometri'),
      ];
      var p = await service.ogretmenProgramiOnIzleme(
        b,
        kaynak,
        sinifId: 1,
        digerSiniflar: true,
      );
      await aktar(p);
      expect(await db.query('MesajOgretmenKisi'), hasLength(1));
      expect(await db.query('MesajOgretmenSinifDers'), hasLength(3));
      expect(await db.query('DersSinif', where: 'Aktif=1'), hasLength(3));
      var kisiler = await service.aliciAdaylari(b, tur: MesajKisiTuru.ogretmen);
      expect(kisiler.first.aciklama, contains('Matematik'));
      expect(kisiler.first.aciklama, contains('Rehberlik'));
      expect(kisiler.last.aciklama, contains('Geometri'));
      final id = kisiler.first.kisiId;
      final eski = await service.ogretmenIletisimBilgisi(b, id);
      await service.ogretmenIletisimKaydet(
        b,
        id: id,
        ad: 'Ayşe Yılmaz',
        telefon: '05320000000',
        sinifIdleri: {1, 2},
        sinifIliskileriniDogruladim: true,
        onceki: eski,
      );
      expect(await db.query('MesajOgretmenSinifDers'), hasLength(3));
      expect(await db.query('DersSinif', where: 'Aktif=1'), hasLength(3));
      await db.update('DersSinif', {'Aktif': 0});
      p = await service.ogretmenProgramiOnIzleme(
        b,
        kaynak,
        sinifId: 1,
        digerSiniflar: true,
      );
      await aktar(p);
      expect(await db.query('MesajOgretmenSinifDers'), hasLength(3));
      expect(await db.query('DersSinif', where: 'Aktif=1'), hasLength(3));
      expect(
        (await db.query('MesajOgretmenKisi')).single['Telefon'],
        '05320000000',
      );
      expect(await db.query('DersProgrami'), hasLength(2));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}
