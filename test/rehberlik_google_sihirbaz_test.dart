import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_google_form_service.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_google_form_yoneticisi.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bilgi_toplama_service.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_google_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_bilgi_toplama_screen.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselRehberlikService s;
  late BireyselRehberlikBaglami b;
  const sablon =
      'https://docs.google.com/forms/d/e/test/viewform?usp=pp_url&entry.123=OKUL_DAVET_KODU';
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    s = BireyselRehberlikService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
    );
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
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('SinifSube', {
      'SinifKodu': '9-C',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    for (var i = 1; i <= 2; i++) {
      await db.insert('Ogrenci', {
        'OkulNo': '$i',
        'Ad': 'Öğrenci$i',
        'Soyad': 'Test',
        'VeliTelefonu': '05321234567',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
    }
    await db.insert('RehberlikAtama', {
      'OkulId': 'okul',
      'OgretmenProfilId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026/2027',
      'BaslangicTarihi': '2000-01-01',
      'OlusturmaTarihi': 'test',
    });
    b = await s.hazirla();
  });
  tearDown(() async => LocalDatabase.instance.close());
  Future<void> form() => s.googleFormKimliginiKaydet(b, 1, 'form-test');

  test(
    'Toplu davet tekrarında kodlar ve yeniden açılan bağlantılar korunur',
    () async {
      await form();
      final codes = await s.googleTopluDavetHazirla(b, 1, [
        1,
        2,
      ], baglantiSablonu: sablon);
      final once = await db.query('RehberlikFormDavet');
      expect(
        await s.googleTopluDavetHazirla(b, 1, [1, 2], baglantiSablonu: sablon),
        isEmpty,
      );
      expect(await db.query('RehberlikFormDavet'), once);
      final again = BireyselRehberlikService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final durum = await again.googleSinifDurumu(b, 1);
      final rows = durum['davetler'] as List;
      expect(
        Uri.parse(
          rows.first['Baglanti'] as String,
        ).queryParameters['entry.123'],
        codes[1],
      );
      expect(await again.googleYanitOgrenciAdayi(b, 1, codes[2]!), 2);
    },
  );
  test('Eski davet geri üretilemese de kodu değiştirilmez', () async {
    await form();
    final old = await s.googleDavetKoduUret(b, 1, 1);
    await s.googleTopluDavetHazirla(b, 1, [1, 2], baglantiSablonu: sablon);
    expect(await s.googleYanitOgrenciAdayi(b, 1, old), 1);
    expect(
      ((await s.googleSinifDurumu(b, 1))['davetler'] as List).first['Baglanti'],
      isNull,
    );
  });
  test(
    'Yanıt takip kaydı hatası fişi de geri alır; tekrar yalnız bir fiş kaydeder',
    () async {
      await form();
      final kod = await s.googleDavetKoduUret(b, 1, 1);
      await s.formKaydet(
        b,
        1,
        1,
        ['Eski'],
        {'Eski': 'Korunacak'},
        hassasOnay: true,
      );
      await db.execute(
        "CREATE TRIGGER fail_google BEFORE INSERT ON RehberlikGoogleYanit BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      final cevap = {'Öğrenci davet kodu': kod, 'Yeni': 'Cevap'};
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'response', 1, cevap),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), hasLength(1));
      await db.execute('DROP TRIGGER fail_google');
      await s.googleYanitiOnayla(b, 1, 'response', 1, cevap);
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'response', 1, cevap),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), hasLength(2));
      final saved =
          jsonDecode(
                (await db.query(
                      'RehberlikForm',
                      orderBy: 'Id DESC',
                    )).first['Cevaplar']
                    as String,
              )
              as Map;
      expect(saved, {'Eski': 'Korunacak', 'Yeni': 'Cevap'});
      expect(
        (await db.query('RehberlikGoogleYanit')).single['DavetId'],
        isNotNull,
      );
    },
  );
  test(
    'Yanlış öğrenci, süresi dolan davet ve ayrılan öğrenci kaydedilmez',
    () async {
      await form();
      final kod = await s.googleDavetKoduUret(b, 1, 1);
      final cevap = {'Öğrenci davet kodu': kod, 'Yeni': 'Cevap'};
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'r1', 2, cevap),
        throwsStateError,
      );
      await db.update('RehberlikFormDavet', {
        'SonGecerlilikTarihi': '2000-01-01',
      });
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'r1', 1, cevap),
        throwsStateError,
      );
      await db.update('OgrenciSinifKayit', {'Aktif': 0}, where: 'OgrenciId=1');
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'r1', 1, cevap),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), isEmpty);
    },
  );
  test('Belirsiz forms.create ikinci kez tekrarlanmaz', () async {
    var calls = 0;
    final g = RehberlikGoogleFormService(
      client: MockClient((r) async {
        calls++;
        throw http.ClientException('network');
      }),
    );
    final m = RehberlikGoogleFormYoneticisi(rehberlik: s, google: g);
    Future<void> create() async {
      await m.hazirla(
        baglam: b,
        atamaId: 1,
        sinifKodu: '9-C',
        erisimBelirteci: 'fake',
      );
    }

    await expectLater(create(), throwsA(isA<http.ClientException>()));
    await expectLater(create(), throwsStateError);
    expect(calls, 1);
  });
  test(
    'Öğrenciye özel bağlantılar aynı veli mesajında birleşir ve ikinci kuyruk engellenir',
    () async {
      final sent = <String>[];
      final ms = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
        whatsappAc: (tel, text) async => sent.add(text),
      );
      final mb = await ms.hazirla();
      final p = MesajOnIzleme(await ms.ogrenciler(mb));
      final q = await ms.kuyrukOlustur(
        mb,
        p,
        'Davetler',
        kaynakModul: 'SinifRehberligim',
        kaynakKayit: 'atama:1:google-form-davet',
        ogrenciMesajlari: {1: 'Öğrenci1: link1', 2: 'Öğrenci2: link2'},
      );
      expect(q.alicilar, hasLength(1));
      await ms.aliciyiAc(mb, q.id, q.alicilar.single.id);
      expect(sent.single, contains('link1'));
      expect(sent.single, contains('link2'));
      await expectLater(
        ms.kuyrukOlustur(
          mb,
          p,
          'Davetler',
          kaynakModul: 'SinifRehberligim',
          kaynakKayit: 'atama:1:google-form-davet',
          ogrenciMesajlari: {1: 'link1', 2: 'link2'},
        ),
        throwsStateError,
      );
      expect(await db.query('MesajKuyrugu'), hasLength(1));
    },
  );
  BireyselBilgiToplamaService ortak() => BireyselBilgiToplamaService(
    databaseGetir: () async => db,
    modGetir: () async => CalismaModu.bireyselOgretmen,
  );
  test(
    'tanıma kataloğu mevcut formu çoğaltmaz ve sahip kapsamını korur',
    () async {
      final f = ortak(), fb = await ortak().hazirla();
      expect(await f.ogrenciTanimaFormlari(fb), isEmpty);
      expect(
        await f.ogrenciTanimaFormlari(fb, yalnizKayitli: false),
        hasLength(1),
      );
      await form();
      final liste = await f.ogrenciTanimaFormlari(fb);
      expect(liste, hasLength(1));
      expect(liste.single['GoogleFormId'], 'form-test');
      await db.update('RehberlikAtama', {
        'BitisTarihi': '2000-01-02',
      }, where: 'RehberlikAtamaId=1');
      await db.insert('RehberlikAtama', {
        'OkulId': 'okul',
        'OgretmenProfilId': 1,
        'SinifSubeId': 1,
        'EgitimOgretimYili': b.egitimOgretimYili,
        'BaslangicTarihi': '2000-01-03',
        'OlusturmaTarihi': 'test',
      });
      final yeni = (await f.ogrenciTanimaFormlari(fb)).single;
      expect(yeni['AtamaId'], 2);
      expect(yeni['GoogleFormId'], 'form-test');
      expect(await db.query('RehberlikGoogleForm'), hasLength(1));
      await db.update('OkulProfil', {'EgitimYili': '2028'}, where: 'Id=1');
      await expectLater(f.ogrenciTanimaFormlari(fb), throwsStateError);
    },
  );

  test(
    'Eski bağlantı doğru öğrenci ve alan doğrulanarak kurtarılır; süre açık onayla uzar',
    () async {
      await form();
      await s.googleDavetSablonuKaydet(b, 1, sablon);
      final kod = await s.googleDavetKoduUret(b, 1, 1);
      final link = s.googleDavetBaglantisi(sablon, kod);
      await expectLater(
        s.googleMevcutDavetiSurdur(b, 1, 2, link, sureyiUzat: false),
        throwsStateError,
      );
      await expectLater(
        s.googleMevcutDavetiSurdur(
          b,
          1,
          1,
          link.replaceAll('entry.123', 'entry.456'),
          sureyiUzat: false,
        ),
        throwsFormatException,
      );
      await db.update('RehberlikFormDavet', {
        'SonGecerlilikTarihi': '2000-01-01',
      });
      await s.googleMevcutDavetiSurdur(b, 1, 1, link, sureyiUzat: false);
      expect(await s.googleYanitOgrenciAdayi(b, 1, kod), isNull);
      await s.googleMevcutDavetiSurdur(b, 1, 1, link, sureyiUzat: true);
      expect(await s.googleYanitOgrenciAdayi(b, 1, kod), 1);
      expect(
        ((await s.googleSinifDurumu(b, 1))['davetler'] as List)
            .single['Baglanti'],
        link,
      );
    },
  );

  Future<void> ortakEkran(WidgetTester t) async {
    t.view.physicalSize = const Size(420, 960);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: RehberlikBilgiFormScreen(
          service: s,
          baglam: b,
          atamaId: 1,
          sinifId: 1,
          formService: ortak(),
          hesapBagla: () async => 'fake',
          google: BilgiToplamaGoogleService(
            client: MockClient((r) async => http.Response('{}', 503)),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
    }
  }

  Future<void> ortakTap(WidgetTester t, String text) async {
    final f = find.text(text);
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        220,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
      );
    }
    await t.ensureVisible(f.first);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(f.first);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await t.pumpAndSettle();
  }

  testWidgets(
    'rehberlik kartı ortak formu sınıf veli ve tüm öğrenciler seçili açar',
    (t) async {
      await ortakEkran(t);
      expect(find.text('Yeni bilgi formu'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Form adı'))
            .controller!
            .text,
        'Öğrenci Bilgi Formu',
      );
      expect(find.text('2 öğrenci seçili.'), findsOneWidget);
      expect(find.text('9-C'), findsOneWidget);
      expect(find.text('Mesaj alıcısı: Velisi'), findsOneWidget);
      expect(find.text('Öğrenci listesi (2/2 seçili)'), findsOneWidget);
      expect(find.textContaining('Kurulum •'), findsNothing);
      expect(find.text('Tanıma formunun sınıfını seç'), findsNothing);
      expect(await db.query('BilgiToplamaForm'), isEmpty);
      expect(await db.query('RehberlikGoogleForm'), isEmpty);
      final arama = find.byKey(const ValueKey('mesaj-ogrenci-arama'));
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: arama, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        false,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'ortak rehberlik formu veli hedefleriyle kaydolur eski Google kaydı korunur',
    (t) async {
      await t.runAsync(form);
      await ortakEkran(t);
      await ortakTap(t, 'Devam');
      await ortakTap(t, 'Devam');
      await ortakTap(t, 'Google Formu Hazırla');
      expect(find.text('Özet'), findsOneWidget);
      expect(find.text('Yanıtlar'), findsOneWidget);
      final f = (await db.query('BilgiToplamaForm')).single;
      expect(f['Baslik'], 'Öğrenci Bilgi Formu');
      expect(f['GoogleFormId'], isNull);
      expect(
        await ortak().formAliciBaglari(await ortak().hazirla(), f['Id'] as int),
        {'Veli:1:1', 'Veli:2:1'},
      );
      expect(
        (await db.query('RehberlikGoogleForm')).single['GoogleFormId'],
        'form-test',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('form merkezi tanıma şablonu aynı ortak başlangıcı kullanır', (
    t,
  ) async {
    t.view.physicalSize = const Size(420, 960);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiToplamaScreen(
          service: ortak(),
          hesapBagla: () async => 'fake',
        ),
      ),
    );
    await t.pumpAndSettle();
    await ortakTap(t, 'Yeni form');
    await ortakTap(t, 'Öğrenci tanıma formu');
    await ortakTap(t, '9-C • Öğrenci tanıma formu');
    expect(find.text('Yeni bilgi formu'), findsOneWidget);
    expect(find.text('Öğrenci listesi (2/2 seçili)'), findsOneWidget);
    expect(find.text('Mesaj alıcısı: Velisi'), findsOneWidget);
    expect(find.text('Formu Hazırla / Kontrol Et'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('rehberlik yılı değişirse ortak taslak kaydı durur', (t) async {
    await ortakEkran(t);
    await ortakTap(t, 'Devam');
    await ortakTap(t, 'Devam');
    await db.update('OkulProfil', {'EgitimYili': '2028'}, where: 'Id=1');
    await ortakTap(t, 'Google Formu Hazırla');
    expect(await db.query('BilgiToplamaForm'), isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  Future<void> secimliForm() async {
    await form();
    await s.googleOgrenciSecenekleriniHazirla(b, 1);
    await s.googleFormEslemeleriniKaydet(b, 1, 'form-test', {
      RehberlikGoogleFormService.ogrenciSecimSorusu: {
        'itemId': 'secim-item',
        'questionId': 'secim-q',
      },
    });
  }

  test(
    'SQLite listesi aktif öğrencileri numarayla sıralar ve çakışmada durur',
    () async {
      await db.update('Ogrenci', {'OkulNo': '10'}, where: 'OgrenciId=1');
      final liste = await s.googleOgrenciSecenekleriniHazirla(b, 1);
      expect(liste.values.toList(), [2, 1]);
      await db.update('Ogrenci', {'OkulNo': '02'}, where: 'OgrenciId=1');
      await expectLater(
        s.googleOgrenciSecenekleriniHazirla(b, 1),
        throwsStateError,
      );
      await db.update('Ogrenci', {
        'OkulNo': '3',
        'Ad': '',
      }, where: 'OgrenciId=1');
      await expectLater(
        s.googleOgrenciSecenekleriniHazirla(b, 1),
        throwsFormatException,
      );
      await db.update('Ogrenci', {'Aktif': 0}, where: 'OgrenciId=1');
      expect(
        (await s.googleOgrenciSecenekleriniHazirla(b, 1)).values.toList(),
        [2],
      );
    },
  );
  test(
    'Ad ve numara değişince eski seçenek sabit öğrenci kimliğiyle korunur',
    () async {
      await secimliForm();
      await db.update('Ogrenci', {
        'OkulNo': '3004',
        'Ad': 'YeniAd',
      }, where: 'OgrenciId=1');
      await s.googleOgrenciSecenekleriniHazirla(b, 1);
      final eski = await s.googleSecimOgrenciAdayi(b, 1, '1 – Öğrenci1 Test');
      expect(eski['adayId'], 1);
      expect(eski['uyari'], contains('değişmiş'));
      final yeni = await s.googleSecimOgrenciAdayi(b, 1, '3004 – YeniAd Test');
      expect(yeni['adayId'], 1);
      expect(yeni['uyari'], isNull);
      await db.update('OgrenciSinifKayit', {'Aktif': 0}, where: 'OgrenciId=1');
      final ayrilan = await s.googleSecimOgrenciAdayi(
        b,
        1,
        '1 – Öğrenci1 Test',
      );
      expect(ayrilan['adayId'], isNull);
      expect(ayrilan['gecmisOgrenciId'], 1);
    },
  );
  test(
    'Etiket yeniden kullanılırsa veya güncel numara çakışırsa otomatik önerilmez',
    () async {
      await secimliForm();
      await db.update('Ogrenci', {'OkulNo': '01'}, where: 'OgrenciId=2');
      expect(
        (await s.googleSecimOgrenciAdayi(b, 1, '1 – Öğrenci1 Test'))['adayId'],
        isNull,
      );
      await db.update('Ogrenci', {'OkulNo': '3'}, where: 'OgrenciId=1');
      await db.update('Ogrenci', {
        'OkulNo': '1',
        'Ad': 'Öğrenci1',
      }, where: 'OgrenciId=2');
      await s.googleOgrenciSecenekleriniHazirla(b, 1);
      final belirsiz = await s.googleSecimOgrenciAdayi(
        b,
        1,
        '1 – Öğrenci1 Test',
      );
      expect(belirsiz['adayId'], isNull);
      expect(belirsiz['uyari'], contains('birden fazla'));
    },
  );
  test(
    'Yeni yanıt atomik kaydedilir, eski cevaplar korunur ve seçim fişe kopyalanmaz',
    () async {
      await secimliForm();
      await s.formKaydet(
        b,
        1,
        1,
        ['Özel soru'],
        {'Özel soru': 'Eski cevap'},
        hassasOnay: true,
      );
      final cevap = {
        RehberlikGoogleFormService.ogrenciSecimSorusu: '1 – Öğrenci1 Test',
        'Adresiniz': 'Yeni adres',
        'Okulunuz': 'Yanlış okul',
        'Sınıfınız': 'Yanlış sınıf',
        'Adınız Soyadınız': 'Yanlış ad',
        'Okul numaranız': '999',
      };
      expect(
        (await s.googleSecimOgrenciAdayi(b, 1, '1 – Öğrenci1 Test'))['adayId'],
        1,
      );
      expect(await db.query('RehberlikForm'), hasLength(1));
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'empty-selection', 1, {
          RehberlikGoogleFormService.ogrenciSecimSorusu: '1 – Öğrenci1 Test',
        }),
        throwsFormatException,
      );
      await db.execute(
        "CREATE TRIGGER fail_new BEFORE INSERT ON RehberlikGoogleYanit BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'new-response', 1, cevap),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), hasLength(1));
      await db.execute('DROP TRIGGER fail_new');
      await s.googleYanitiOnayla(b, 1, 'new-response', 1, cevap);
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'new-response', 1, cevap),
        throwsStateError,
      );
      final saved =
          jsonDecode(
                (await db.query(
                      'RehberlikForm',
                      orderBy: 'Id DESC',
                    )).first['Cevaplar']
                    as String,
              )
              as Map;
      expect(saved['Özel soru'], 'Eski cevap');
      expect(saved['Adresiniz'], 'Yeni adres');
      expect(saved['Okul numaranız'], '1');
      expect(saved['Adınız Soyadınız'], 'Öğrenci1 Test');
      expect(saved['Sınıfınız'], '9-C');
      expect(saved['Okulunuz'], 'Okul');
      expect(
        saved.containsKey(RehberlikGoogleFormService.ogrenciSecimSorusu),
        isFalse,
      );
      expect(
        (await db.query('RehberlikGoogleYanit')).single['DavetId'],
        isNull,
      );
    },
  );
  test(
    'Şüpheli yanıt ancak ayrıca eşleşme değişikliği onayıyla aktarılır',
    () async {
      await secimliForm();
      final cevap = {
        RehberlikGoogleFormService.ogrenciSecimSorusu: '1 – Öğrenci1 Test',
        'Adresiniz': 'Yanıt',
      };
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'wrong', 2, cevap),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), isEmpty);
      await s.googleYanitiOnayla(
        b,
        1,
        'wrong',
        2,
        cevap,
        eslesmeDegisikligiOnayi: true,
      );
      expect((await db.query('RehberlikForm')).single['OgrenciId'], 2);
    },
  );
  test(
    'Aynı sınıf ve yılın yeni ataması mevcut Google formu ve seçim geçmişini kullanır',
    () async {
      await secimliForm();
      await db.update('RehberlikAtama', {
        'BitisTarihi': '2020-01-01',
      }, where: 'RehberlikAtamaId=1');
      final yeni = await db.insert('RehberlikAtama', {
        'OkulId': 'okul',
        'OgretmenProfilId': 1,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026/2027',
        'BaslangicTarihi': '2020-01-02',
        'OlusturmaTarihi': 'test',
      });
      expect(
        (await s.googleFormKaydiGetir(b, yeni))!['GoogleFormId'],
        'form-test',
      );
      await expectLater(
        s.googleFormKimliginiKaydet(b, yeni, 'yeni-form'),
        throwsStateError,
      );
      expect(await db.query('RehberlikGoogleForm'), hasLength(1));
      expect(
        (await s.googleSecimOgrenciAdayi(
          b,
          yeni,
          '1 – Öğrenci1 Test',
        ))['adayId'],
        1,
      );
      await s.googleFormuAktifIsaretle(b, yeni, 'form-test');
      await s.googleYanitiOnayla(b, yeni, 'later-response', 1, {
        RehberlikGoogleFormService.ogrenciSecimSorusu: '1 – Öğrenci1 Test',
        'Adresiniz': 'Yanıt',
      });
      expect((await db.query('RehberlikForm')).single['AtamaId'], yeni);
    },
  );
  test(
    'Ortak veli mesajı düzenlenebilir ve aynı telefona bir kez hazırlanır',
    () async {
      final acilan = <String>[];
      final ms = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
        whatsappAc: (tel, text) async => acilan.add(text),
      );
      final mb = await ms.hazirla();
      final p = MesajOnIzleme(await ms.ogrenciler(mb));
      final q = await ms.kuyrukOlustur(
        mb,
        p,
        'Düzenlenmiş ortak mesaj https://docs.google.com/forms/d/e/test/viewform',
        kaynakModul: 'SinifRehberligim',
        kaynakKayit: 'google-form:form-test:ortak',
      );
      expect(acilan, isEmpty);
      expect(q.alicilar, hasLength(1));
      await ms.aliciyiAc(mb, q.id, q.alicilar.single.id);
      expect(acilan.single, q.metin);
      expect(acilan.single, contains('Düzenlenmiş ortak mesaj'));
    },
  );

  test(
    'Yalnız liste güncellemesi diğer eksik soruları eklemez ve formu yeniden oluşturmaz',
    () async {
      await secimliForm();
      // Google'dan kaldırılmış eski kimlik sorusunun yanıt eşlemesi korunur.
      await s.googleFormEslemeleriniKaydet(b, 1, 'form-test', {
        RehberlikGoogleFormService.ogrenciSecimSorusu: {
          'itemId': 'secim-item',
          'questionId': 'secim-q',
        },
        'Okulunuz': {'itemId': 'old-school', 'questionId': 'old-school-q'},
      });
      final g = RehberlikGoogleFormService(
        client: MockClient((r) async {
          expect(r.method, 'GET');
          return http.Response(
            jsonEncode({
              'formId': 'form-test',
              'items': [
                {
                  'itemId': 'secim-item',
                  'title': RehberlikGoogleFormService.ogrenciSecimSorusu,
                  'questionItem': {
                    'question': {
                      'questionId': 'secim-q',
                      'required': true,
                      'choiceQuestion': {
                        'type': 'DROP_DOWN',
                        'options': [
                          {'value': '1 – Öğrenci1 Test'},
                          {'value': '2 – Öğrenci2 Test'},
                        ],
                      },
                    },
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final m = RehberlikGoogleFormYoneticisi(rehberlik: s, google: g);
      await m.hazirla(
        baglam: b,
        atamaId: 1,
        sinifKodu: '9-C',
        erisimBelirteci: 'fake',
        yalnizOgrenciListesi: true,
      );
      await m.hazirla(
        baglam: b,
        atamaId: 1,
        sinifKodu: '9-C',
        erisimBelirteci: 'fake',
        yalnizOgrenciListesi: true,
      );
      expect(await db.query('RehberlikGoogleForm'), hasLength(1));
      final kayit = await s.googleFormKaydiGetir(b, 1);
      final eslemeler = jsonDecode(kayit!['SoruEslemeleri'] as String) as Map;
      expect(eslemeler['Okulunuz']['questionId'], 'old-school-q');
    },
  );
}
