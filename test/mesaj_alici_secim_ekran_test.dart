import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/widgets/mesaj_alici_duzenleme_dialog.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MesajlasmaService service;
  var gonderim = 0;
  Completer<void>? whatsappBekle;
  var whatsappHata = false;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    gonderim = 0;
    whatsappBekle = null;
    whatsappHata = false;
    service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
      whatsappAc: (_, _) async {
        gonderim++;
        if (whatsappHata) throw StateError('WhatsApp açılamadı');
        await whatsappBekle?.future;
      },
      smsIzni: () async => true,
      smsGonder: (_, _) async {
        gonderim++;
        return 1;
      },
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
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    for (var i = 1; i <= 3; i++) {
      await db.insert('SinifSube', {
        'SinifSubeId': i,
        'SinifKodu': i == 1
            ? '9/A'
            : i == 2
            ? '9/B'
            : '9/C',
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
    for (var i = 1; i <= 4; i++) {
      await db.insert('Ogrenci', {
        'OgrenciId': i,
        'OkulNo': '00$i',
        'Ad': 'Öğrenci$i',
        'Soyad': 'Test',
        'Telefon': '0532111223$i',
        'AnneAdi': 'Anne$i',
        'AnneTelefon': '0532444556$i',
        'BabaAdi': 'Baba$i',
        'BabaTelefon': '0532777889$i',
        'VeliTuru': 'Anne',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': i <= 2
            ? 1
            : i == 3
            ? 2
            : 3,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
  });
  tearDown(LocalDatabase.instance.close);

  Finder scrollable(WidgetTester t) {
    final dialog = find.byType(AlertDialog);
    return dialog.evaluate().isNotEmpty
        ? find.descendant(of: dialog, matching: find.byType(Scrollable)).first
        : find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first;
  }

  Future<void> gor(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      final s = scrollable(t);
      final position = t.state<ScrollableState>(s).position;
      position.jumpTo(position.minScrollExtent);
      await t.pump();
      await t.scrollUntilVisible(f, 180, scrollable: s);
    }
    await t.ensureVisible(f.last);
    await t.pump();
  }

  Future<void> dokun(WidgetTester t, Finder f) async {
    await gor(t, f);
    await t.tap(f.last);
    await t.pump(const Duration(milliseconds: 350));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pump();
    if (find.byType(AlertDialog).evaluate().isEmpty &&
        find.byType(SimpleDialog).evaluate().isEmpty) {
      await t.pumpAndSettle();
    }
  }

  Future<void> ac(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(home: MesajlasmaScreen(service: service)));
    await t.pumpAndSettle();
  }

  Future<void> ara(WidgetTester t, String text) async {
    final f = find.byKey(const ValueKey('mesaj-ogrenci-arama'));
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(f, -250, scrollable: scrollable(t));
    }
    await t.ensureVisible(f);
    await t.enterText(f, text);
    await t.pumpAndSettle();
  }

  Future<void> sinif(
    WidgetTester t,
    String text, {
    String hedef = 'Kendisi',
  }) async {
    final f = find.byType(DropdownButton<int>);
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(f, -250, scrollable: scrollable(t));
    }
    await dokun(t, f);
    await dokun(t, find.text(text).last);
    await dokun(t, find.text('Alıcı grubu'));
    await dokun(t, find.text('Sınıf öğrencileri'));
    await dokun(t, find.text(hedef));
    await dokun(t, find.textContaining('Öğrenci listesi ('));
  }

  Future<void> ogrenci(WidgetTester t, String id, String rol) async {
    await ara(t, '00$id');
    final baslik = find.textContaining('Öğrenci listesi (');
    await gor(t, baslik);
    if (!ExpansibleController.of(t.element(baslik)).isExpanded) {
      await dokun(t, baslik);
    }
    await dokun(t, find.byKey(ValueKey('mesaj-aday-Ogrenci:$id')));
    await dokun(t, find.text(rol));
  }

  Future<void> mesaj(WidgetTester t, String text) async {
    final f = find.widgetWithText(TextField, 'Mesajınız');
    await gor(t, f);
    await t.enterText(f, text);
    await t.pumpAndSettle();
  }

  testWidgets(
    'arama rol seçtirir; seçimler sınıf ve arama değişiminde korunur, tekrar eklenmez',
    (t) async {
      await ac(t);
      await ara(t, '004');
      expect(find.byKey(const ValueKey('mesaj-aday-Ogrenci:4')), findsNothing);
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      await ogrenci(t, '3', 'Velisine');
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      expect(find.text('Öğrenci listesi (1/1 seçili)'), findsOneWidget);
      await ogrenci(t, '1', 'Velisine');
      expect(find.text('Öğrenci listesi (1/1 seçili)'), findsOneWidget);
      await sinif(t, '9/A');
      expect(find.text('Öğrenci listesi (1/2 seçili)'), findsOneWidget);
      await dokun(
        t,
        find.descendant(
          of: find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(find.text('Öğrenci listesi (0/2 seçili)'), findsOneWidget);
      await sinif(t, '9/B', hedef: 'Velisi');
      expect(find.text('Öğrenci listesi (1/1 seçili)'), findsOneWidget);
      await sinif(t, '9/A');
      expect(find.text('Öğrenci listesi (0/2 seçili)'), findsOneWidget);
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(gonderim, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'veli tercihi sonrası sınıf topluca seçilir; seçim kaldırma gönderim yapmaz',
    (t) async {
      await ac(t);
      await sinif(t, '9/A', hedef: 'Velisi');
      expect(find.text('Öğrenci listesi (0/2 seçili)'), findsOneWidget);
      await dokun(t, find.text('Görünenleri seç'));
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.text('Öğrenci listesi (2/2 seçili)'), findsOneWidget);
      for (final id in ['1', '2']) {
        await dokun(t, find.textContaining('Öğrenci listesi ('));
        await dokun(
          t,
          find.descendant(
            of: find.byKey(ValueKey('mesaj-aday-Ogrenci:$id')),
            matching: find.byType(Checkbox),
          ),
        );
      }
      expect(find.text('Öğrenci listesi (0/2 seçili)'), findsOneWidget);
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(gonderim, 0);
    },
  );
  testWidgets(
    'kayıtlı öğretmen listelenir; ekleme düğmeleri yok ve ders adı görünür',
    (t) async {
      final b = await service.hazirla();
      final id = await service.ogretmenIletisimKaydet(
        b,
        ad: 'Ders öğretmeni',
        telefon: '05329990011',
        sinifIdleri: {1},
        sinifIliskileriniDogruladim: true,
      );
      await db.insert('MesajOgretmenSinifDers', {
        'KisiId': id,
        'SinifSubeId': 1,
        'EgitimOgretimYili': b.yil,
        'DersId': 1,
      });
      await ac(t);
      await sinif(t, '9/A');
      await dokun(t, find.text('Alıcı grubu'));
      await dokun(t, find.text('Sınıfta derse giren öğretmenler'));
      await dokun(t, find.textContaining('Öğretmen listesi ('));
      expect(find.text('Öğretmen ekle / ilişkilendir'), findsNothing);
      expect(find.text('Programdan öğretmen aktar'), findsNothing);
      expect(find.text('Import Merkezi'), findsNothing);
      await gor(t, find.byKey(ValueKey('mesaj-aday-Ogretmen:$id')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('9/A • Ders'), findsNothing);
      expect(find.text('Ders'), findsOneWidget);
      await dokun(t, find.byKey(ValueKey('mesaj-aday-Ogretmen:$id')));
      expect(find.text('Öğretmen listesi (1/1 seçili)'), findsOneWidget);
      await mesaj(t, 'Toplantı');
      await dokun(t, find.text('Ön İzle ve Onayla'));
      await dokun(t, find.byTooltip('Telefonu düzenle'));
      await t.enterText(
        find.byKey(const ValueKey('mesaj-kisi-telefon')),
        '05321110000',
      );
      await dokun(t, find.text('Kaydet'));
      expect(find.textContaining('+905321110000'), findsOneWidget);
      expect(
        (await db.query(
          'MesajOgretmenKisi',
          where: 'KisiId=?',
          whereArgs: [id],
        )).single['Telefon'],
        '05321110000',
      );
      await dokun(t, find.text('WhatsApp ile gönder'));
      expect(await db.query('MesajAliciBag'), isEmpty);
      expect(gonderim, 1);
    },
  );
  testWidgets(
    'öğrenci ve veli kuyruğunun telefonları ve türleri korunur; gönderim kendiliğinden başlamaz',
    (t) async {
      await ac(t);
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      await ogrenci(t, '2', 'Velisine');
      await mesaj(t, 'Bilgilendirme mesajı');
      await dokun(t, find.text('Ön İzle ve Onayla'));
      expect(
        find.textContaining('2 alıcı • 2 telefon numarası'),
        findsOneWidget,
      );
      await dokun(t, find.text('SMS ile gönder'));
      await dokun(t, find.text('Vazgeç'));
      final alicilar = await db.query('MesajAlici');
      expect(alicilar.map((a) => a['Telefon']).toSet(), {
        '905321112231',
        '905324445562',
      });
      expect((await db.query('MesajAliciBag')).map((b) => b['Tur']).toSet(), {
        'Ogrenci',
        'Veli',
      });
      expect(find.text('SIM Üzerinden Otomatik SMS Gönder'), findsNothing);
      expect(find.byKey(const ValueKey('whatsapp-devam')), findsNothing);
      expect(gonderim, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'eksik telefon engellenir; tekli düzenleme hata halinde girilen değeri korur',
    (t) async {
      await db.update('Ogrenci', {
        'Telefon': '',
        'AnneTelefon': '',
      }, where: 'OgrenciId=1');
      await ac(t);
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      await mesaj(t, 'Mesaj');
      await dokun(t, find.text('Ön İzle ve Onayla'));
      expect(find.text('Telefon bilgisi eksik'), findsNothing);
      expect(find.text('1 / 1 kişi'), findsOneWidget);
      expect(find.text('Rehberden seç'), findsOneWidget);
      expect(await db.query('MesajKuyrugu'), isEmpty);
      await dokun(t, find.text('İşlemi sonlandır'));
      await dokun(t, find.text('Ön İzle ve Onayla'));
      await t.enterText(
        find.byKey(const ValueKey('eksik-telefon-Ogrenci:1')),
        'abc',
      );
      await dokun(t, find.text('Kaydet ve sonrakine geç'));
      expect(find.text('Geçerli tek telefon numarası girin.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('eksik-telefon-Ogrenci:1')),
        '05320000000',
      );
      await db.update('Ogrenci', {
        'Telefon': '05321110000',
      }, where: 'OgrenciId=1');
      await dokun(t, find.text('Kaydet ve sonrakine geç'));
      expect(find.textContaining('Girişleriniz korunuyor'), findsOneWidget);
      expect(
        t
            .widget<TextField>(
              find.byKey(const ValueKey('eksik-telefon-Ogrenci:1')),
            )
            .controller!
            .text,
        '05320000000',
      );
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['Telefon'],
        '05321110000',
      );
      await dokun(t, find.text('İşlemi sonlandır'));
      expect(gonderim, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'yenileme ders kapsamından çıkan seçimi kaldırır; mesaj taslağını korur',
    (t) async {
      await ac(t);
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      await mesaj(t, 'Korunacak taslak');
      await db.update('DersProgrami', {'Aktif': 0}, where: 'SinifSubeId=1');
      await dokun(t, find.byTooltip('Yenile'));
      expect(
        find.textContaining('1 alıcı güncel ders kapsamından'),
        findsOneWidget,
      );
      await gor(t, find.widgetWithText(TextField, 'Mesajınız'));
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Mesajınız'))
            .controller!
            .text,
        'Korunacak taslak',
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Ön İzle ve Onayla'),
            )
            .onPressed,
        isNull,
      );
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(gonderim, 0);
    },
  );
  testWidgets('dar ekranda klavye açıkken seçim ve mesaj bölümleri taşmaz', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await ac(t);
    await ogrenci(t, '1', 'Öğrencinin kendisine');
    await mesaj(t, 'Dar ekran mesajı');
    expect(t.takeException(), isNull);
    expect(gonderim, 0);
  });
  testWidgets(
    'kendisi seçiminde numaralar öğrenci kaydına yazılır; sonlandırma sonraki kaydı değiştirmez',
    (t) async {
      await db.update('Ogrenci', {'Telefon': ''}, where: 'OgrenciId IN (1,2)');
      await ac(t);
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      await ogrenci(t, '2', 'Öğrencinin kendisine');
      await mesaj(t, 'Korunan taslak');
      await dokun(t, find.text('Ön İzle ve Onayla'));
      expect(find.text('1 / 2 kişi'), findsOneWidget);
      expect(find.text('Veli bilgisi'), findsNothing);
      expect(find.text('Adı soyadı'), findsNothing);
      expect(find.text('Numara Öğrenci kaydına yazılacak.'), findsOneWidget);
      for (final text in ['Bu kişiyi atla', 'Toplu gir', 'Hepsini atla']) {
        expect(find.text(text), findsNothing);
      }
      await t.enterText(
        find.byKey(const ValueKey('eksik-telefon-Ogrenci:1')),
        '05320000000',
      );
      await dokun(t, find.text('Kaydet ve sonrakine geç'));
      expect(find.text('2 / 2 kişi'), findsOneWidget);
      await dokun(t, find.text('İşlemi sonlandır'));
      final rows = await db.query('Ogrenci');
      expect(
        rows.firstWhere((r) => r['OgrenciId'] == 1)['Telefon'],
        '05320000000',
      );
      expect(
        rows.firstWhere((r) => r['OgrenciId'] == 1)['AnneTelefon'],
        '05324445561',
      );
      expect(rows.firstWhere((r) => r['OgrenciId'] == 2)['Telefon'], '');
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(gonderim, 0);
      await gor(t, find.widgetWithText(TextField, 'Mesajınız'));
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Mesajınız'))
            .controller!
            .text,
        'Korunan taslak',
      );
    },
  );

  for (final tur in ['Anne', 'Baba', 'Diger']) {
    testWidgets(
      'eksik öğrenci numarası $tur velisine kaydedilir ve ona mesaj hazırlanır',
      (t) async {
        await db.update('Ogrenci', {
          'Telefon': '',
          'AnneTelefon': '',
          'BabaTelefon': '',
          'VeliTelefonu': '',
        }, where: 'OgrenciId=1');
        await ac(t);
        await ogrenci(t, '1', 'Velisine');
        await mesaj(t, 'Bilgi');
        await dokun(t, find.text('Ön İzle ve Onayla'));
        if (tur != 'Anne') {
          await dokun(t, find.byType(DropdownButton<String>));
          await dokun(t, find.text(tur == 'Diger' ? 'Diğer veli' : tur).last);
        }
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('eksik-veli-adi-Veli:1')),
              )
              .controller!
              .text,
          tur == 'Diger' ? '' : '${tur}1',
        );
        await t.enterText(
          find.byKey(const ValueKey('eksik-veli-adi-Veli:1')),
          'Yeni $tur',
        );
        await t.enterText(
          find.byKey(const ValueKey('eksik-telefon-Veli:1')),
          '05320000000',
        );
        await dokun(t, find.text('Kaydet ve sonrakine geç'));
        expect(find.text('Mesajı gönder'), findsOneWidget);
        expect(
          find.textContaining('Veli (${tur == 'Diger' ? 'Diğer veli' : tur})'),
          findsOneWidget,
        );
        expect(find.textContaining('+905320000000'), findsOneWidget);
        final row = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
        final alan = tur == 'Diger' ? 'VeliTelefonu' : '${tur}Telefon';
        expect(row[alan], '05320000000');
        expect(row[tur == 'Diger' ? 'VeliAdi' : '${tur}Adi'], 'Yeni $tur');
        expect(
          find.textContaining(
            'Veli (${tur == 'Diger' ? 'Diğer veli' : tur}) • Yeni $tur',
          ),
          findsOneWidget,
        );
        for (final key in ['AnneTelefon', 'BabaTelefon', 'VeliTelefonu']) {
          if (key != alan) expect(row[key] ?? '', '');
        }
        expect(row['Telefon'], '');
        expect(row['VeliTuru'], tur);
        await dokun(t, find.text('WhatsApp ile gönder'));
        expect(gonderim, 1);
        final log = (await db.query('MesajTekliGecmis')).single;
        expect(log['Tur'], 'Veli');
        expect(log['AliciAdi'], 'Yeni $tur');
        expect(log['Telefon'], '905320000000');
      },
    );
  }

  testWidgets('öğretmenin eksik telefonu kendi iletişim kaydına yazılır', (
    t,
  ) async {
    final b = await service.hazirla();
    final id = await service.ogretmenIletisimKaydet(
      b,
      ad: 'Ders öğretmeni',
      sinifIdleri: {1},
      sinifIliskileriniDogruladim: true,
    );
    await ac(t);
    await sinif(t, '9/A');
    await dokun(t, find.text('Alıcı grubu'));
    await dokun(t, find.text('Sınıfta derse giren öğretmenler'));
    await dokun(t, find.textContaining('Öğretmen listesi ('));
    await dokun(t, find.byKey(ValueKey('mesaj-aday-Ogretmen:$id')));
    await mesaj(t, 'Toplantı');
    await dokun(t, find.text('Ön İzle ve Onayla'));
    await t.enterText(
      find.byKey(ValueKey('eksik-telefon-Ogretmen:$id')),
      '05320000000',
    );
    await dokun(t, find.text('Kaydet ve sonrakine geç'));
    await dokun(t, find.text('SMS ile gönder'));
    await dokun(t, find.text('Vazgeç'));
    expect(
      (await db.query('MesajOgretmenKisi')).single['Telefon'],
      '05320000000',
    );
    expect(await db.query('MesajAliciBag'), isEmpty);
    expect((await db.query('OgretmenProfil')).single['AdSoyad'], 'Profil');
    expect(gonderim, 0);
  });

  testWidgets('öğretmen dialogunda kayıt hatası adı ve telefonu silmez', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => MesajOgretmenDialog(
                  siniflar: const {1: '9/A'},
                  seciliSiniflar: const {1},
                  kaydet: (_, _, _) async {
                    throw StateError('Deneme hatası');
                  },
                ),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await dokun(t, find.text('Aç'));
    await t.enterText(
      find.byKey(const ValueKey('mesaj-ogretmen-ad')),
      'Kaybolmasın',
    );
    await t.enterText(
      find.byKey(const ValueKey('mesaj-ogretmen-telefon')),
      '05329990011',
    );
    await dokun(t, find.byKey(const ValueKey('mesaj-ogretmen-dogrula')));
    await dokun(t, find.text('Kaydet'));
    expect(find.textContaining('Girişleriniz korunuyor'), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('mesaj-ogretmen-ad')))
          .controller!
          .text,
      'Kaybolmasın',
    );
    expect(await db.query('MesajOgretmenKisi'), isEmpty);
  });
  testWidgets('tüm sınıflar yalnız ders kapsamındaki öğrencileri seçer', (
    t,
  ) async {
    await ac(t);
    final liste = t.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect(liste.items!.map((i) => (i.child as Text).data), [
      'Sınıf seçin',
      'Tüm sınıflar',
      '9/A',
      '9/B',
    ]);
    await sinif(t, 'Tüm sınıflar', hedef: 'Velisi');
    await dokun(t, find.text('Görünenleri seç'));
    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.text('Öğrenci listesi (3/3 seçili)'), findsOneWidget);
    expect(find.textContaining('Seçilen alıcılar'), findsNothing);
    expect(await db.query('MesajKuyrugu'), isEmpty);
    expect(gonderim, 0);
  });
  testWidgets('tekli öğrenci geçmişi okul numarasıyla filtrelenir', (t) async {
    await ac(t);
    await ogrenci(t, '1', 'Velisine');
    await mesaj(t, 'Birinci öğrencinin mesajı');
    await dokun(t, find.text('Ön İzle ve Onayla'));
    await dokun(t, find.text('WhatsApp ile gönder'));
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    await ogrenci(t, '2', 'Öğrencinin kendisine');
    await mesaj(t, 'İkinci öğrencinin mesajı');
    await dokun(t, find.text('Ön İzle ve Onayla'));
    await dokun(t, find.text('WhatsApp ile gönder'));
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    await dokun(t, find.text('Gönderim Geçmişi'));
    await dokun(t, find.text('Ara'));
    final arama = find.byKey(const ValueKey('gonderim-gecmisi-arama'));
    await t.enterText(arama, '001');
    await t.pumpAndSettle();
    expect(find.textContaining('Birinci öğrencinin mesajı'), findsOneWidget);
    expect(find.textContaining('İkinci öğrencinin mesajı'), findsNothing);
    expect(find.textContaining('Veli: Anne1'), findsOneWidget);
    expect(await db.query('MesajKuyrugu'), isEmpty);
    expect(await db.query('MesajTekliGecmis'), hasLength(2));
    expect(gonderim, 2);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'geçmiş satırı seçilir, tümünü seç filtreye uyar, özet açmadan onaylanır',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final b = await service.hazirla();
      final adaylar = await service.aliciAdaylari(b);
      final uzunMesaj =
          'Sayın Velimiz, ${'Açıklama ' * 200}\nForm bağlantısı: https://docs.google.com/forms/d/e/uzun-form/viewform\nTeşekkür ederiz.';
      for (final id in ['1', '2']) {
        await service.tekliGonder(
          b,
          id == '1' ? uzunMesaj : 'Mesaj $id',
          kisiler: MesajKisiOnIzleme(
            adaylar.where((k) => k.kisiId == id && k.tur == MesajKisiTuru.veli),
          ),
          sms: false,
          kaynakModul: 'Mesajlasma',
        );
      }
      await ac(t);
      expect(t.takeException(), isNull, reason: 'ilk ekran');
      await dokun(t, find.text('Gönderim Geçmişi'));
      expect(t.takeException(), isNull, reason: 'geçmiş açılışı');
      expect(find.byIcon(Icons.play_circle_outline), findsNothing);
      await dokun(t, find.byType(ListTile).first);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('1 seçili'), findsOneWidget);
      await dokun(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      expect(find.text('2 seçili'), findsOneWidget);
      await dokun(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      expect(find.text('0 seçili'), findsOneWidget);
      await dokun(t, find.text('Ara'));
      await t.enterText(
        find.byKey(const ValueKey('gonderim-gecmisi-arama')),
        '001',
      );
      await t.pumpAndSettle();
      await dokun(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      expect(find.text('1 seçili'), findsOneWidget);
      expect(find.textContaining('Bilgi formu daveti'), findsOneWidget);
      expect(find.text(uzunMesaj), findsNothing);
      expect(
        find.textContaining('https://docs.google.com/forms'),
        findsNothing,
      );
      await dokun(t, find.byKey(const ValueKey('gecmisi-onayla')));
      final rows = await db.query('MesajTekliGecmis');
      expect(rows.firstWhere((r) => r['OgrenciId'] == 1)['Metin'], uzunMesaj);
      expect(rows.firstWhere((r) => r['OgrenciId'] == 1)['Durum'], 'Istendi');
      expect(rows.firstWhere((r) => r['OgrenciId'] == 2)['Durum'], 'Acildi');
      expect(find.textContaining('Onaylandı'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(gonderim, 2);
      expect(await db.query('MesajKuyrugu'), isEmpty);
      final hata = t.takeException();
      expect(
        hata,
        isNull,
        reason: hata is FlutterError
            ? hata.diagnostics.map((d) => d.toStringDeep()).join('\n')
            : '$hata',
      );
    },
  );
  testWidgets(
    'geçmiş sınıf ve öğrenci filtreleri tümüyle açılır, seçim ve onay kapsamını korur',
    (t) async {
      final b = await service.hazirla();
      final adaylar = await service.aliciAdaylari(
        b,
        tur: MesajKisiTuru.ogrenci,
      );
      for (final id in ['1', '3']) {
        await service.tekliGonder(
          b,
          'Öğrenci $id mesajı',
          kisiler: MesajKisiOnIzleme(adaylar.where((k) => k.kisiId == id)),
          sms: false,
          kaynakModul: 'Mesajlasma',
        );
      }
      final q = await service.kisilerleKuyrukOlustur(
        b,
        MesajKisiOnIzleme(adaylar.where((k) => k.kisiId == '2')),
        'Kuyruk mesajı',
        kaynakModul: 'Mesajlasma',
      );
      await service.aliciyiAc(b, q.id, q.alicilar.single.id);
      // Güncel listeden çıkmış öğrencinin geçmişi filtrelerde korunmalı.
      await db.update('Ogrenci', {'Aktif': 0}, where: 'OgrenciId=1');
      await ac(t);
      await dokun(t, find.text('Gönderim Geçmişi'));
      await dokun(t, find.text('Filtrele'));
      expect(find.text('Tüm sınıflar'), findsOneWidget);
      expect(find.text('Tüm öğrenciler'), findsOneWidget);
      expect(find.textContaining('3 kayıt'), findsOneWidget);
      await dokun(t, find.byKey(const ValueKey('gecmis-sinif-null')));
      await dokun(t, find.text('9/A').last);
      expect(find.textContaining('2 kayıt'), findsOneWidget);
      await dokun(t, find.byKey(const ValueKey('gecmis-ogrenci-9/A-null')));
      expect(find.text('Öğrenci3 Test • 003'), findsNothing);
      await dokun(t, find.text('Öğrenci1 Test • 001').last);
      expect(find.textContaining('1 kayıt'), findsOneWidget);
      expect(find.byTooltip('Yarım kalan gönderimler'), findsNothing);
      await dokun(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      expect(find.text('1 seçili'), findsOneWidget);
      await dokun(t, find.byKey(const ValueKey('gecmis-ogrenci-9/A-1')));
      await dokun(t, find.text('Öğrenci2 Test • 002').last);
      expect(find.text('0 seçili'), findsOneWidget);
      expect(find.textContaining('1 kayıt'), findsOneWidget);
      await dokun(t, find.byKey(const ValueKey('gecmis-tumunu-sec')));
      await dokun(t, find.byKey(const ValueKey('gecmisi-onayla')));
      expect((await service.kuyrukGetir(b, q.id)).onaylanan, 1);
      expect(
        (await db.query(
          'MesajTekliGecmis',
        )).every((r) => r['Durum'] == 'Acildi'),
        true,
      );
      expect(gonderim, 3);
      await dokun(t, find.byKey(const ValueKey('gecmis-sinif-9/A')));
      await dokun(t, find.text('9/B').last);
      expect(find.text('Tüm öğrenciler'), findsOneWidget);
      expect(find.textContaining('1 kayıt'), findsOneWidget);
      await dokun(t, find.byKey(const ValueKey('gecmis-sinif-9/B')));
      await dokun(t, find.text('Tüm sınıflar').last);
      expect(find.textContaining('3 kayıt'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'tik/sil simgeleri tooltip gösterir, onaylı kayıt seçilip silme iptal edilebilir',
    (t) async {
      final b = await service.hazirla();
      final k = (await service.aliciAdaylari(b, tur: MesajKisiTuru.veli)).first;
      await service.tekliGonder(
        b,
        'Silme testi',
        kisiler: MesajKisiOnIzleme([k]),
        sms: false,
        kaynakModul: 'Mesajlasma',
      );
      final id = (await service.tekliGecmis(b)).single['KayitId'] as String;
      await service.gecmisiOnayla(b, kuyrukAlicilari: {}, tekliKayitlar: {id});
      await ac(t);
      await dokun(t, find.text('Gönderim Geçmişi'));
      expect(find.byTooltip('Onayla'), findsOneWidget);
      expect(find.byTooltip('Geçmiş işlemleri'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsWidgets);
      await dokun(t, find.byType(ListTile).first);
      expect(
        t
            .widget<IconButton>(find.byKey(const ValueKey('gecmisi-onayla')))
            .onPressed,
        isNull,
      );
      await dokun(t, find.byTooltip('Geçmiş işlemleri'));
      expect(
        t
            .widget<PopupMenuItem<String>>(find.byKey(const ValueKey('gecmisi-sil')))
            .enabled,
        isTrue,
      );
      await dokun(t, find.byKey(const ValueKey('gecmisi-sil')));
      expect(find.text('Seçili mesaj geçmişini sil'), findsOneWidget);
      await dokun(t, find.text('Vazgeç'));
      expect(await db.query('MesajTekliGecmis'), hasLength(1));
      await dokun(t, find.byTooltip('Geçmiş işlemleri'));
      await dokun(t, find.byKey(const ValueKey('gecmisi-sil')));
      await dokun(t, find.text('Sil'));
      expect(await db.query('MesajTekliGecmis'), isEmpty);
      expect(await db.query('Ogrenci'), hasLength(4));
      expect(gonderim, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('tek SMS kuyruksuz öğrenci geçmişine yazılır', (t) async {
    await ac(t);
    await ogrenci(t, '1', 'Öğrencinin kendisine');
    await mesaj(t, 'SMS deneme');
    await dokun(t, find.text('Ön İzle ve Onayla'));
    await dokun(t, find.text('SMS ile gönder'));
    expect(gonderim, 0);
    await dokun(t, find.text('SMS Gönderimini Başlat'));
    expect(gonderim, 1);
    expect(await db.query('MesajKuyrugu'), isEmpty);
    expect(await db.query('MesajSms'), isEmpty);
    final kayit = (await db.query('MesajTekliGecmis')).single;
    expect(kayit['OgrenciId'], 1);
    expect(kayit['Durum'], 'Istendi');
    await dokun(t, find.text('Gönderim Geçmişi'));
    expect(find.textContaining('SMS gönderim isteği iletildi'), findsWidgets);
    await dokun(t, find.byType(ListTile).first);
    expect(find.text('SMS ile devam et'), findsNothing);
    expect(gonderim, 1);
  });
  testWidgets(
    'tek WhatsApp açılırken takip görünmez; açılma gönderildi sayılmaz',
    (t) async {
      await ac(t);
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      await mesaj(t, 'Tek mesaj');
      await dokun(t, find.text('Ön İzle ve Onayla'));
      whatsappBekle = Completer<void>();
      await t.ensureVisible(find.text('WhatsApp ile gönder'));
      await t.tap(find.text('WhatsApp ile gönder'));
      for (var i = 0; i < 30 && gonderim == 0; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const ValueKey('whatsapp-devam')), findsNothing);
        expect(find.text('SIM Üzerinden Otomatik SMS Gönder'), findsNothing);
      }
      expect(gonderim, 1);
      whatsappBekle!.complete();
      whatsappBekle = null;
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('whatsapp-devam')), findsNothing);
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(await db.query('MesajAlici'), isEmpty);
      expect((await db.query('MesajTekliGecmis')).single['Durum'], 'Acildi');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'kaynak modülde toplu WhatsApp yalnız takip penceresinde çalışır',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(
                  PageRouteBuilder<void>(
                    opaque: false,
                    pageBuilder: (_, _, _) => MesajlasmaScreen(
                      service: service,
                      baslangicMetni: 'Kaynak mesajı',
                      baslangicKisiBaglari: const {
                        'Ogrenci:1:1',
                        'Ogrenci:2:1',
                      },
                      gonderimOnizlemesiniAc: true,
                      yalnizGonderimOnayi: true,
                      takipPenceresi: true,
                    ),
                  ),
                ),
                child: const Text('Kaynak ekran'),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await dokun(t, find.text('Kaynak ekran'));
      expect(find.text('Mesajı gönder'), findsOneWidget);
      expect(find.text('Yeni Mesaj'), findsNothing);
      expect(gonderim, 0);
      await dokun(t, find.text('WhatsApp ile gönder'));
      expect(gonderim, 1);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Gönderim Geçmişi'), findsNothing);
      final b = await service.hazirla();
      expect((await service.kuyruklar(b)).single.onaylanan, 0);
      await dokun(t, find.text('Atla'));
      expect(gonderim, 2);
      await dokun(t, find.text('Gönderdim, sıradakine geç'));
      expect(find.byType(MesajlasmaScreen), findsNothing);
      expect(find.text('Kaynak ekran'), findsOneWidget);
      final q = (await service.kuyruklar(b)).single;
      expect(q.atlanan, 1);
      expect(q.onaylanan, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pencereli akışta ortak numara dönüş onayından sonra kaynağa döner',
    (t) async {
      await db.update('Ogrenci', {
        'Telefon': '05321112231',
      }, where: 'OgrenciId=2');
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(
                  PageRouteBuilder<void>(
                    opaque: false,
                    pageBuilder: (_, _, _) => MesajlasmaScreen(
                      service: service,
                      baslangicMetni: 'Ortak numara',
                      baslangicKisiBaglari: const {
                        'Ogrenci:1:1',
                        'Ogrenci:2:1',
                      },
                      gonderimOnizlemesiniAc: true,
                      yalnizGonderimOnayi: true,
                      takipPenceresi: true,
                    ),
                  ),
                ),
                child: const Text('Kaynak ekran'),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await dokun(t, find.text('Kaynak ekran'));
      await dokun(t, find.text('WhatsApp ile gönder'));
      expect(gonderim, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('Mesajı gönderdiniz mi?'), findsOneWidget);
      await dokun(t, find.text('Daha sonra'));
      await t.pumpAndSettle();
      expect(find.byType(MesajlasmaScreen), findsNothing);
      final q = (await service.kuyruklar(await service.hazirla())).single;
      expect(q.onaylanan, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'toplu WhatsApp dönüşte sade kontrol; atlama ve beyan sıradakini açar',
    (t) async {
      await ac(t);
      for (final id in ['1', '2', '3']) {
        await ogrenci(t, id, 'Öğrencinin kendisine');
      }
      await mesaj(t, 'Toplu mesaj');
      await dokun(t, find.text('Ön İzle ve Onayla'));
      await dokun(t, find.text('WhatsApp ile gönder'));
      expect(gonderim, 1);
      expect(find.text('SIM Üzerinden Otomatik SMS Gönder'), findsNothing);
      expect(find.text('Gönderdim, sıradakine geç'), findsOneWidget);
      await dokun(t, find.text('Atla'));
      expect(gonderim, 2);
      expect(find.textContaining('2 / 3'), findsOneWidget);
      await dokun(t, find.text('Gönderdim, sıradakine geç'));
      expect(gonderim, 3);
      expect(find.textContaining('3 / 3'), findsOneWidget);
      await dokun(t, find.text('Daha sonra devam et'));
      await t.pumpWidget(const SizedBox.shrink());
      await ac(t);
      expect(gonderim, 3);
      await dokun(t, find.text('Gönderim Geçmişi'));
      await dokun(t, find.byTooltip('Geçmiş işlemleri'));
      expect(gonderim, 3);
      await dokun(t, find.textContaining('Devam et: Toplu mesaj'));
      // Açılmış alıcı yeniden açılmaz veya gönderilmiş sayılmaz.
      expect(gonderim, 3);
      await dokun(t, find.text('Gönderdim, sıradakine geç'));
      final q = (await service.kuyruklar(await service.hazirla())).single;
      expect(q.atlanan, 1);
      expect(q.onaylanan, 2);
      expect(q.siradaki, isNull);
      expect(find.byKey(const ValueKey('whatsapp-devam')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'tekli WhatsApp hatası geçmişte tutulur, taslakla yeniden denenir',
    (t) async {
      whatsappHata = true;
      await ac(t);
      await ogrenci(t, '1', 'Öğrencinin kendisine');
      await mesaj(t, 'Yeniden dene');
      await dokun(t, find.text('Ön İzle ve Onayla'));
      await dokun(t, find.text('WhatsApp ile gönder'));
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect((await db.query('MesajTekliGecmis')).single['Durum'], 'Acilamadi');
      whatsappHata = false;
      await dokun(t, find.text('Ön İzle ve Onayla'));
      await dokun(t, find.text('WhatsApp ile gönder'));
      expect(gonderim, 2);
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(
        (await db.query('MesajTekliGecmis')).map((r) => r['Durum']).toSet(),
        {'Acildi', 'Acilamadi'},
      );
    },
  );
}
