import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ogrenci_islemleri_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_bilgi_toplama_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bilgi_toplama_service.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_google_service.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselBilgiToplamaService s;
  late BilgiToplamaOturumu b;
  late Map<String, dynamic> remote;
  late http.Client client;
  late BilgiToplamaGoogleService google;
  var createCount = 0;
  var cevaplar = <Map<String, dynamic>>[];
  var silmeHatasi = false;
  var scriptSilmeSayisi = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'calisma_modu': CalismaModu.bireyselOgretmen.kayitDegeri,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
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
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifKodu': '9/A',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OkulNo': '001',
      'Ad': 'Ayşe',
      'Soyad': 'Yılmaz',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
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
    s = BireyselBilgiToplamaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
    );
    b = await s.hazirla();
    remote = {
      'formId': 'g1',
      'items': <dynamic>[],
      'responderUri': 'https://docs.google.com/forms/d/e/gercek/viewform',
      'publishSettings': {
        'publishState': {'isPublished': false, 'isAcceptingResponses': false},
      },
    };
    createCount = 0;
    silmeHatasi = false;
    scriptSilmeSayisi = 0;
    cevaplar = [];
    client = MockClient((r) async {
      if (r.url.host == 'script.googleapis.com') {
        scriptSilmeSayisi++;
        if (silmeHatasi) return http.Response('{}', 403);
        final body = jsonDecode(r.body) as Map;
        if (body['function'] == 'okulYanitDuzenlemeBaglantisi') {
          final params = body['parameters'] as List;
          return http.Response(
            jsonEncode({
              'done': true,
              'response': {
                'result': {
                  'protocol': 'okul-yanit-duzelt/v1',
                  'formId': params[0],
                  'responseId': params[1],
                  'editUrl':
                      'https://docs.google.com/forms/d/e/test/viewform?edit2=private-test',
                },
              },
            }),
            200,
          );
        }
        expect(body['function'], 'okulYanitSil');
        expect(body['devMode'], false);
        expect(r.headers['Authorization'], 'Bearer test');
        final params = body['parameters'] as List;
        cevaplar.removeWhere((y) => y['responseId'] == params[1]);
        return http.Response(
          jsonEncode({
            'done': true,
            'response': {
              'result': {
                'protocol': 'okul-yanit-sil/v1',
                'formId': params[0],
                'responseId': params[1],
                'absent': true,
              },
            },
          }),
          200,
        );
      }
      if (r.url.path.contains('/responses/')) {
        final rows = cevaplar.where(
          (y) => y['responseId'] == r.url.pathSegments.last,
        );
        return http.Response(
          rows.isEmpty ? '{}' : jsonEncode(rows.first),
          rows.isEmpty ? 404 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (r.method == 'POST' && r.url.path.endsWith('/forms')) {
        createCount++;
        remote['info'] = jsonDecode(r.body)['info'];
      } else if (r.url.path.endsWith(':batchUpdate')) {
        final req = jsonDecode(r.body)['requests'] as List;
        final items = remote['items'] as List;
        for (final q in req) {
          if (q['createItem'] != null) {
            items.insert(
              q['createItem']['location']['index'] as int,
              q['createItem']['item'],
            );
          }
          if (q['deleteItem'] != null) {
            items.removeAt(q['deleteItem']['location']['index'] as int);
          }
          if (q['updateFormInfo'] != null) {
            remote['info'] = q['updateFormInfo']['info'];
          }
        }
      } else if (r.url.path.endsWith(':setPublishSettings')) {
        remote['publishSettings'] = jsonDecode(r.body)['publishSettings'];
      }
      return http.Response(
        jsonEncode(
          r.url.path.endsWith('/responses') ? {'responses': cevaplar} : remote,
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    google = BilgiToplamaGoogleService(client: client);
  });
  tearDown(() async {
    client.close();
    await LocalDatabase.instance.close();
  });
  Future<int> taslak() => s.formOlustur(
    b,
    baslik: 'Veli Bilgileri',
    sorular: [
      BilgiToplamaSorusu(
        anahtar: 'telefon',
        baslik: 'Öğrenci telefon',
        veriTuru: 'Telefon',
        hedefAlan: 'Telefon',
      ),
    ],
  );
  Future<void> tap(WidgetTester t, String text) async {
    final f = text == 'Geri' ? find.byTooltip('Geri') : find.text(text);
    if (text == 'Yanıtları getir' && find.text('Özet').evaluate().isEmpty) {
      await t.drag(find.byType(ListView).first, const Offset(0, 1800));
      await t.pumpAndSettle();
    }
    if (text == 'Yanıtları getir' && find.text('Özet').evaluate().isNotEmpty) {
      await t.tap(find.text('Özet'));
      await t.pumpAndSettle();
    }
    if (f.evaluate().isEmpty &&
        text == 'Yanıtları getir' &&
        find.text('Özet').evaluate().isNotEmpty) {
      await t.ensureVisible(find.text('Özet'));
      await t.tap(find.text('Özet'));
      await t.pumpAndSettle();
    }
    if (f.evaluate().isEmpty &&
        text.startsWith('001 •') &&
        find.text('Yanıtlar').evaluate().isNotEmpty) {
      await t.ensureVisible(find.text('Yanıtlar'));
      await t.tap(find.text('Yanıtlar'));
      await t.pumpAndSettle();
    }
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
      );
    }
    await t.ensureVisible(f.first);
    await t.pump();
    await t.tap(f.first);
    await t.pump(const Duration(milliseconds: 350));
    if (find.byType(AlertDialog).evaluate().isEmpty &&
        find.byType(SimpleDialog).evaluate().isEmpty) {
      await t.pumpAndSettle();
    }
    if (find.byType(MesajlasmaScreen).evaluate().isNotEmpty &&
        (text == 'Google Formu Hazırla' || text == 'Ön İzle ve Onayla')) {
      final dialog = find.byType(AlertDialog);
      if (dialog.evaluate().isNotEmpty) {
        Navigator.of(t.element(dialog.first)).pop();
        await t.pumpAndSettle();
      }
      if (text == 'Google Formu Hazırla' &&
          find.byType(MesajlasmaScreen).evaluate().isNotEmpty) {
        Navigator.of(t.element(find.byType(MesajlasmaScreen))).pop();
        await t.pumpAndSettle();
      }
    }
  }

  Future<void> hedefSec(WidgetTester t) async {
    await t.enterText(
      find.byKey(const ValueKey('mesaj-ogrenci-arama')),
      'Ayşe',
    );
    await t.pumpAndSettle();
    await tap(t, 'Görünenleri seç');
    await tap(t, 'Öğrencinin kendisine');
  }

  Future<void> aliciSec(WidgetTester t, {bool veli = true}) async {
    await t.enterText(
      find.byKey(const ValueKey('mesaj-ogrenci-arama')),
      'Ayşe',
    );
    await t.pumpAndSettle();
    await tap(t, 'Görünenleri seç');
    await tap(t, veli ? 'Velisine' : 'Öğrencinin kendisine');
    await tap(t, 'Seçimi kaydet (1)');
  }

  Map<String, dynamic> cevap() => {
    'responseId': 'r1',
    'answers': {
      for (final item in remote['items'] as List)
        item['questionItem']['question']['questionId']: {
          'textAnswers': {
            'answers': [
              {
                'value': switch (item['title']) {
                  'Okul numarası' => '001',
                  'Ad soyad' => 'Ayşe Yılmaz',
                  'Sınıf' => '9/A',
                  _ => '05321112233',
                },
              },
            ],
          },
        },
    },
  };
  test(
    'öğrenci seçimi açılır listedir ve aynı isimlerde kayıt kimliğiyle eşleşir',
    () async {
      await db.insert('Ogrenci', {
        'OkulNo': '002',
        'Ad': 'Ayşe',
        'Soyad': 'Yılmaz',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': 2,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      final id = await s.formOlustur(
        b,
        baslik: 'Öğrenci Bilgi Formu',
        hedefTuru: 'OgrenciSec',
        ogrenciIdleri: {1},
        ogrenciListesi: true,
        sorular: [
          BilgiToplamaSorusu(
            anahtar: 'tel',
            baslik: 'Öğrenci telefon',
            veriTuru: 'Telefon',
            hedefAlan: 'Telefon',
          ),
        ],
      );
      await google.hazirla(s, b, id, 'test');
      final sorular = await s.sorular(b, id);
      expect(sorular.map((q) => q['AlanAnahtari']), ['ogrenciSecimi', 'tel']);
      final item = (remote['items'] as List).first;
      final choice = item['questionItem']['question']['choiceQuestion'];
      expect(choice['type'], 'DROP_DOWN');
      expect(item['questionItem']['question']['required'], true);
      expect(choice['options'], [
        {'value': '9/A • 001 • Ayşe Yılmaz'},
      ]);
      Map<String, dynamic> yanit(String secim, String yanitId) => {
        'responseId': yanitId,
        'answers': {
          for (final q in sorular)
            q['GoogleSoruId']: {
              'textAnswers': {
                'answers': [
                  {
                    'value': q['AlanAnahtari'] == 'ogrenciSecimi'
                        ? secim
                        : '05321112233',
                  },
                ],
              },
            },
        },
      };
      final yid = (await s.yanitlariKaydet(b, id, [
        yanit('9/A • 001 • Ayşe Yılmaz', 'liste1'),
      ])).single;
      final p = await s.onizle(b, yid);
      expect(p.ogrenci!['OgrenciId'], 1);
      expect(p.hatalar, isEmpty);
      await s.onayla(b, p);
      final ogrenciler = await db.query('Ogrenci', orderBy: 'OgrenciId');
      expect(ogrenciler.first['Telefon'], '05321112233');
      expect(ogrenciler.last['Telefon'], isNull);
      final hatali = (await s.yanitlariKaydet(b, id, [
        yanit('9/A • 002 • Ayşe Yılmaz', 'liste2'),
      ])).single;
      final gecersiz = await s.onizle(b, hatali);
      expect(gecersiz.ogrenci, isNull);
      expect(gecersiz.hatalar, isNotEmpty);
      await expectLater(s.onayla(b, gecersiz), throwsStateError);
      final yeni = await s.formOlustur(
        b,
        baslik: 'Liste düzenleme',
        hedefTuru: 'OgrenciSec',
        ogrenciIdleri: {1},
        ogrenciListesi: true,
        sorular: [BilgiToplamaSorusu(anahtar: 'aciklama', baslik: 'Açıklama')],
      );
      final plan = await s.formDuzenlemeHazirla(
        b,
        yeni,
        beklenenForm: await s.formGetir(b, yeni),
        baslik: 'Liste düzenleme',
        hedefTuru: 'OgrenciSec',
        ogrenciIdleri: {2},
        sorular: [BilgiToplamaSorusu(anahtar: 'aciklama', baslik: 'Açıklama')],
      );
      final listeSorusu = (plan['sorular'] as List).first as Map;
      expect(listeSorusu['AlanAnahtari'], 'ogrenciSecimi');
      final secenekler =
          jsonDecode(listeSorusu['Secenekler'] as String) as List;
      expect(secenekler.single['ogrenciId'], 2);
      await s.formDuzenlemeyiKaydet(b, yeni);
      expect((await s.sorular(b, yeni)).map((q) => q['AlanAnahtari']), [
        'ogrenciSecimi',
        'aciklama',
      ]);
    },
  );

  testWidgets('hazırla kayıtlı alıcılarla doğrudan onay açar', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final id = await taslak();
    await db.update('Ogrenci', {'Telefon': '05321112233'});
    await s.formAlicilariniKaydet(b, id, {'Ogrenci:1:1'});
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiFormDetayScreen(
          service: s,
          baglam: b,
          formId: id,
          google: google,
          hesapBagla: () async => 'test',
          hazirlayarakAc: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    final mesaj = t.widget<MesajlasmaScreen>(find.byType(MesajlasmaScreen));
    expect(mesaj.baslangicKisiBaglari, {'Ogrenci:1:1'});
    expect(mesaj.gonderimOnizlemesiniAc, true);
    expect(mesaj.yalnizGonderimOnayi, true);
    expect(find.text('Alıcıları seç'), findsNothing);
    expect(find.text('Mesajı gönder'), findsOneWidget);
    expect(find.text('SMS ile gönder'), findsOneWidget);
    expect(find.text('WhatsApp ile gönder'), findsOneWidget);
    expect(find.text('Form alıcıları'), findsNothing);
    Navigator.of(t.element(find.text('Mesajı gönder'))).pop();
    await t.pumpAndSettle();
    expect(find.byType(MesajlasmaScreen), findsNothing);
    expect(find.byTooltip('Alıcıları düzenle'), findsOneWidget);
    expect(find.byTooltip('Yanıt alımını kapat'), findsOneWidget);
    expect(find.byTooltip('Yanıt vermeyenlere hatırlat'), findsOneWidget);
    expect(find.text('Mesaj'), findsNothing);
    expect(find.text('Metni kopyala'), findsNothing);
    await tap(t, 'Mesaj metni');
    expect(find.text('Metni kopyala'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    await tap(t, 'Metni kopyala');
    expect(find.text('Mesaj metni kopyalandı.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('mobil form ayrıntısı üç sekmede taşmadan çalışır', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('FORM_GORSEL')) {
      await t.runAsync(() async {
        final font = FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    await s.yanitlariKaydet(b, id, [cevap()]);
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          home: BireyselBilgiFormDetayScreen(
            service: s,
            baglam: b,
            formId: id,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final sekme in ['Özet', 'Yanıtlar', 'Değerlendirme']) {
      await tap(t, sekme);
      expect(t.takeException(), isNull);
      if (const bool.fromEnvironment('FORM_GORSEL')) {
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final png = await (await boundary.toImage(
            pixelRatio: 1,
          )).toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('C:/OkulYonetim/work/form_modulu_gorseller');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/${sekme == 'Özet'
                ? 'ozet'
                : sekme == 'Yanıtlar'
                ? 'yanitlar'
                : 'degerlendirme'}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }
    }
  });

  Future<void> sonAdimaGit(
    WidgetTester t, {
    BilgiToplamaGoogleService? g,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiToplamaScreen(
          service: s,
          google: g ?? google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Yeni form');
    await tap(t, 'Öğrenci ve veli bilgileri');
    await t.enterText(
      find.widgetWithText(TextField, 'Form adı'),
      'Sabit düğme formu',
    );
    await hedefSec(t);
    await tap(t, 'Devam');
    await tap(t, 'Devam');
  }

  testWidgets(
    'son adım hazırlama düğmesi formu yayımlar ve doğrudan onay açar',
    (t) async {
      await db.update('Ogrenci', {'Telefon': '05321112233'});
      await sonAdimaGit(t);
      await t.tap(find.byKey(const ValueKey('form-sabit-ana-islem')));
      await t.pumpAndSettle();
      expect(createCount, 1);
      expect(remote['publishSettings']['publishState']['isPublished'], true);
      expect(find.text('Mesajı gönder'), findsOneWidget);
      final mesaj = t.widget<MesajlasmaScreen>(find.byType(MesajlasmaScreen));
      expect(mesaj.baslangicKisiBaglari, {'Ogrenci:1:1'});
      expect(mesaj.yalnizGonderimOnayi, true);
      expect(find.text('Alıcıları seç'), findsNothing);
      expect(find.text('SMS ile gönder'), findsOneWidget);
      expect(find.text('WhatsApp ile gönder'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Google hazırlama düğmesi altta sabittir içeriği kapatmaz ve tek kez hazırlar',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await sonAdimaGit(t);
      final buton = find.byKey(const ValueKey('form-sabit-ana-islem'));
      expect(find.text('Taslağı kaydet'), findsNothing);
      expect(find.text('Google Formu Hazırla'), findsOneWidget);
      expect(
        find.byTooltip(
          'Bilgileri arka planda kaydeder ve Google Formu hazırlar.',
        ),
        findsOneWidget,
      );
      final once = t.getRect(buton);
      expect(
        t.getRect(find.byType(ListView).first).bottom,
        lessThanOrEqualTo(once.top),
      );
      await t.drag(find.byType(ListView).first, const Offset(0, -700));
      await t.pumpAndSettle();
      expect(t.getRect(buton), once);
      t.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      expect(t.getRect(buton).bottom, lessThanOrEqualTo(420));
      expect(t.takeException(), isNull);
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await t.tap(buton);
      await t.tap(buton);
      await t.pumpAndSettle();
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        Navigator.of(t.element(find.byType(AlertDialog).first)).pop();
        await t.pumpAndSettle();
      }
      if (find.byType(MesajlasmaScreen).evaluate().isNotEmpty) {
        Navigator.of(t.element(find.byType(MesajlasmaScreen))).pop();
        await t.pumpAndSettle();
      }
      expect(createCount, 1);
      expect(await s.formlar(b), hasLength(1));
      expect((await s.formlar(b)).single['GoogleFormId'], 'g1');
      expect(find.text('Ön İzle ve Onayla'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'otomatik Google hazırlama hatasında yerel kayıt ve sabit tekrar düğmesi korunur',
    (t) async {
      var istekler = 0;
      final g = BilgiToplamaGoogleService(
        client: MockClient((r) async {
          istekler++;
          return http.Response('{}', 503);
        }),
      );
      await sonAdimaGit(t, g: g);
      await tap(t, 'Google Formu Hazırla');
      final f = (await s.formlar(b)).single;
      expect(f['GoogleFormId'], isNull);
      expect(await s.formAliciBaglari(b, f['Id'] as int), {'Ogrenci:1:1'});
      expect(istekler, 1);
      expect(
        find.byKey(const ValueKey('form-sabit-ana-islem')),
        findsOneWidget,
      );
      expect(find.text('Google Formu Hazırla'), findsOneWidget);
      expect(find.textContaining('HTTP 503'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('şablonlar filtreler ve üç ayrıntı sekmesi görünür', (t) async {
    final id = await taslak();
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiToplamaScreen(
          service: s,
          google: google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final ad in [
      'Tümü',
      'Taslak',
      'Yanıt bekleniyor',
      'Tamamlandı',
      'Arşiv',
    ]) {
      expect(find.widgetWithText(ChoiceChip, ad), findsOneWidget);
    }
    await tap(t, 'Yeni form');
    for (final ad in [
      'Öğrenci ve veli bilgileri',
      'Fotoğraflı öğretmen görüşü',
      'Toplantı katılımı',
      'Anket / geri bildirim',
      'Boş form',
    ]) {
      expect(find.text(ad), findsOneWidget);
    }
    await tap(t, 'Anket / geri bildirim');
    await t.enterText(
      find.byKey(const ValueKey('mesaj-ogrenci-arama')),
      'Ayşe',
    );
    await t.pumpAndSettle();
    await tap(t, 'Görünenleri seç');
    await tap(t, 'Öğrencinin kendisine');
    await tap(t, 'Devam');
    await t.scrollUntilVisible(find.text('Genel değerlendirmeniz'), 220);
    expect(find.text('Genel değerlendirmeniz'), findsWidgets);
    for (
      var i = 0;
      i < 20 && find.byTooltip('Yukarı taşı').evaluate().isEmpty;
      i++
    ) {
      await t.drag(
        find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
        const Offset(0, -220),
      );
      await t.pumpAndSettle();
    }
    await t.ensureVisible(find.byTooltip('Yukarı taşı').first);
    expect(find.byTooltip('Yukarı taşı'), findsWidgets);
    await tap(t, 'Devam');
    await tap(t, 'Google Formu Hazırla');
    expect(find.text('Özet'), findsOneWidget);
    expect(find.text('Yanıtlar'), findsOneWidget);
    expect(find.text('Değerlendirme'), findsOneWidget);
    final forms = await s.formlar(b);
    final yeni = forms.firstWhere((f) => f['Id'] != id);
    expect((await s.yonetim(b, yeni['Id'] as int))['sablon'], 'Anket');
    expect(await s.yanitlar(b, yeni['Id'] as int), isEmpty);
    expect(createCount, 1);
    expect(t.takeException(), isNull);
  });

  test('yanıt alımı Google’da doğrulanmadan yerel durum değişmez', () async {
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    final engelli = BilgiToplamaGoogleService(
      client: MockClient((r) async {
        if (r.url.path.endsWith(':setPublishSettings')) {
          return http.Response('{}', 403);
        }
        return client.get(r.url, headers: r.headers);
      }),
    );
    await expectLater(
      engelli.yanitAliminiAyarla(s, b, id, 'test', false),
      throwsStateError,
    );
    expect((await s.formGetir(b, id))['Durum'], 'Aktif');
    await google.yanitAliminiAyarla(s, b, id, 'test', false);
    expect((await s.formGetir(b, id))['Durum'], 'Kapali');
    await expectLater(google.yayinla(s, b, id, 'test'), throwsStateError);
    await google.yanitAliminiAyarla(s, b, id, 'test', true);
    expect((await s.formGetir(b, id))['Durum'], 'Aktif');
  });

  testWidgets('ortak alıcı seçimi boş başlar, öğrenci seçip taslağa kaydeder', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiToplamaScreen(
          service: s,
          google: google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Yeni form');
    await tap(t, 'Öğrenci ve veli bilgileri');
    expect(find.text('Hedef kitle'), findsNothing);
    expect(find.text('Alıcıları seç'), findsOneWidget);
    expect(find.text('0 öğrenci seçili.'), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextField, 'Form adı'),
      'Ortak seçim formu',
    );
    await tap(t, 'Devam');
    expect(find.text('Form adını ve hedef öğrencileri seçin.'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('mesaj-ogrenci-arama')),
      'Ayşe',
    );
    await t.pumpAndSettle();
    await tap(t, 'Görünenleri seç');
    await tap(t, 'Öğrencinin kendisine');
    expect(find.text('1 öğrenci seçili.'), findsOneWidget);
    expect(find.text('Mesaj kime gönderilsin?'), findsNothing);
    await tap(t, 'Devam');
    await tap(t, 'Devam');
    await tap(t, 'Google Formu Hazırla');
    final rows = await db.query('BilgiToplamaForm');
    expect(rows.single['HedefTuru'], 'OgrenciSec');
    expect(await db.query('BilgiToplamaHedef'), hasLength(1));
    expect(createCount, 1);
  });

  testWidgets(
    'ortak tam menü sınıf, alıcı grubu, veli ve öğretmen seçeneklerini korur',
    (t) async {
      final ms = MesajlasmaService.instance;
      final mb = await ms.hazirla();
      final kisi = await t.runAsync(
        () => ms.ogretmenIletisimKaydet(
          mb,
          ad: 'Ders öğretmeni',
          telefon: '05321112233',
          sinifIdleri: {1},
          sinifIliskileriniDogruladim: true,
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiToplamaScreen(
            service: s,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Yeni form');
      await tap(t, 'Öğrenci ve veli bilgileri');
      await t.enterText(
        find.widgetWithText(TextField, 'Form adı'),
        'Öğretmen hedefi',
      );
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('9/A').last);
      await t.pumpAndSettle();
      await tap(t, 'Alıcı grubu');
      expect(find.text('Sınıfta derse giren öğretmenler'), findsOneWidget);
      await tap(t, 'Sınıf öğrencileri');
      expect(find.text('Mesaj kime gönderilsin?'), findsOneWidget);
      await tap(t, 'Velisi');
      expect(find.text('Mesaj alıcısı: Velisi'), findsOneWidget);
      await tap(t, 'Alıcı grubu');
      await tap(t, 'Sınıfta derse giren öğretmenler');
      await tap(t, 'Öğretmen listesi (0/1 seçili)');
      await tap(t, 'Görünenleri seç');
      await tap(t, 'Devam');
      await tap(t, 'Devam');
      await tap(t, 'Google Formu Hazırla');
      final f = (await db.query('BilgiToplamaForm')).single;
      expect(await s.formAliciBaglari(b, f['Id'] as int), {'Ogretmen:$kisi:1'});
      expect(await db.query('BilgiToplamaHedef'), hasLength(1));
      expect(createCount, 1);
    },
  );

  testWidgets('tek öğrenci işlemleri altında iki alt kart ve geri dönüş', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: BireyselOgrenciIslemleriScreen(
          ogrenciler: Scaffold(body: Text('Öğrenci listesi hedefi')),
          formlar: Scaffold(body: Text('Form hedefi')),
        ),
      ),
    );
    expect(find.text('Öğrenci İşlemleri'), findsOneWidget);
    expect(find.text('Öğrencilerim'), findsOneWidget);
    await tap(t, 'Öğrencilerim');
    expect(find.text('Öğrenci listesi hedefi'), findsOneWidget);
    Navigator.of(t.element(find.text('Öğrenci listesi hedefi'))).pop();
    await t.pumpAndSettle();
    await tap(t, 'Formlarla Bilgi Toplama');
    expect(find.text('Form hedefi'), findsOneWidget);
  });
  testWidgets('ana sayfada tek öğrenci kartı alt menüyü açar', (t) async {
    await t.pumpWidget(const MaterialApp(home: BireyselAnaSayfaScreen()));
    await t.pump(const Duration(seconds: 4));
    await t.scrollUntilVisible(
      find.text('Öğrenci İşlemleri'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Öğrencilerim'), findsNothing);
    await t.ensureVisible(
      find.byKey(const ValueKey('modul-Öğrenci İşlemleri')),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Öğrenci İşlemleri'));
    await t.pumpAndSettle();
    expect(find.byType(BireyselOgrenciIslemleriScreen), findsOneWidget);
    expect(find.text('Öğrencilerim'), findsOneWidget);
    expect(find.text('Formlarla Bilgi Toplama'), findsOneWidget);
  });
  testWidgets('dar ekranda hedef seçimi, sorular ve taslak kaydı', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiToplamaScreen(
          service: s,
          google: google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Yeni form');
    await tap(t, 'Öğrenci ve veli bilgileri');
    expect(find.text('Başlığı girin'), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.widgetWithText(TextField, 'Form adı'))
          .controller!
          .text,
      isEmpty,
    );
    await tap(t, 'Devam');
    expect(find.text('Form adını ve hedef öğrencileri seçin.'), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextField, 'Form adı'),
      'Öğrenci ve Veli Bilgileri',
    );
    await hedefSec(t);
    await tap(t, 'Devam');
    await tap(t, 'Serbest soru ekle');
    await t.enterText(
      find.widgetWithText(TextField, 'Soru başlığı'),
      'Okuldan beklentiniz',
    );
    await tap(t, 'Soruyu kaydet');
    await tap(t, 'Devam');
    await tap(t, 'Google Formu Hazırla');
    expect(await db.query('BilgiToplamaForm'), hasLength(1));
    expect(await db.query('BilgiToplamaSoru'), hasLength(11));
    final veliSorusu = (await db.query(
      'BilgiToplamaSoru',
      where: 'AlanAnahtari=?',
      whereArgs: ['veliSecimi'],
    )).single;
    expect(jsonDecode(veliSorusu['Secenekler'] as String), [
      'Annem',
      'Babam',
      'Diğer',
    ]);
    expect(veliSorusu['Zorunlu'], 1);
    expect(find.text('Ön İzle ve Onayla'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'hedef seçimi doğrudan açılır, sınıf sayacı ve yeniden seçim doğru çalışır',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await db.insert('SinifSube', {
        'SinifSubeId': 2,
        'SinifKodu': '9/B',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': 2,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Salı',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      for (final id in [2, 3, 4]) {
        await db.insert('Ogrenci', {
          'OgrenciId': id,
          'OkulNo': '00$id',
          'Ad': 'Öğrenci$id',
          'Soyad': 'Test',
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciSinifKayit', {
          'OgrenciId': id,
          'SinifSubeId': id == 2 ? 1 : 2,
          'EgitimOgretimYili': '2026-2027',
          'OlusturmaTarihi': 'test',
        });
      }
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiToplamaScreen(
            service: s,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Yeni form');
      await tap(t, 'Öğrenci ve veli bilgileri');
      expect(find.text('0 öğrenci seçili.'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'Form adı'),
        'Sınıf bilgi formu',
      );
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('9/A').last);
      await t.pumpAndSettle();
      await tap(t, 'Alıcı grubu');
      await tap(t, 'Sınıf öğrencileri');
      await tap(t, 'Kendisi');
      await tap(t, 'Öğrenci listesi (0/2 seçili)');
      await tap(t, 'Görünenleri seç');
      expect(find.text('2 öğrenci seçili.'), findsOneWidget);
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('9/B').last);
      await t.pumpAndSettle();
      await tap(t, 'Öğrenci listesi (0/2 seçili)');
      await tap(t, 'Görünenleri seç');
      await t.scrollUntilVisible(
        find.text('4 öğrenci seçili.'),
        -200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
      );
      expect(find.text('4 öğrenci seçili.'), findsOneWidget);
      await tap(t, 'Öğrenci listesi (2/2 seçili)');
      await tap(t, 'Seçimi kaldır');
      await t.scrollUntilVisible(
        find.text('2 öğrenci seçili.'),
        -200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
      );
      expect(find.text('2 öğrenci seçili.'), findsOneWidget);
      expect(await db.query('BilgiToplamaForm'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'seçilen hazır alanlar korunur ve yalnız seçilenler Google formuna gider',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiToplamaScreen(
            service: s,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Yeni form');
      await tap(t, 'Öğrenci ve veli bilgileri');
      await t.enterText(
        find.widgetWithText(TextField, 'Form adı'),
        'Alan seçimi formu',
      );
      await hedefSec(t);
      await tap(t, 'Devam');
      await tap(t, 'Baba telefon');
      await tap(t, 'Öğrenci bilgileri');
      await tap(t, 'Doğum tarihiniz');
      await tap(t, 'Okul öncesi eğitim aldınız mı?');
      await tap(t, 'Devam');
      await tap(t, 'Geri');
      await tap(t, 'Devam');
      await tap(t, 'Google Formu Hazırla');
      final sorular = await db.query('BilgiToplamaSoru');
      expect(sorular, hasLength(11));
      expect(sorular.where((q) => q['Baslik'] == 'Baba telefon'), isEmpty);
      expect(
        sorular.singleWhere(
          (q) => q['Baslik'] == 'Doğum tarihiniz',
        )['VeriTuru'],
        'Tarih',
      );
      expect(sorular.where((q) => q['Zorunlu'] == 1), hasLength(2));
      expect(createCount, 1);
      expect(
        (remote['items'] as List).map((q) => q['title']),
        sorular.map((q) => q['Baslik']),
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('tüm hazır alanlardan kısa forma dönülür', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiToplamaScreen(
          service: s,
          google: google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Yeni form');
    await tap(t, 'Öğrenci ve veli bilgileri');
    await t.enterText(
      find.widgetWithText(TextField, 'Form adı'),
      'Kısa bilgi formu',
    );
    await hedefSec(t);
    await tap(t, 'Devam');
    await tap(t, 'Tüm hazır alanları seç');
    await t.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await t.pumpAndSettle();
    expect(find.text('42 soru • Öğrenci seçimi zorunlu'), findsOneWidget);
    await tap(t, 'Kısa form alanları');
    await t.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await t.pumpAndSettle();
    expect(find.text('10 soru • Öğrenci seçimi zorunlu'), findsOneWidget);
    await tap(t, 'Devam');
    await tap(t, 'Google Formu Hazırla');
    expect(await db.query('BilgiToplamaSoru'), hasLength(10));
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'form basılı tutma, tümünü seçme, silme iptali ve taslak temizliği',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await taslak();
      await taslak();
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiToplamaScreen(
            service: s,
            google: google,
            hesapBagla: () async =>
                throw StateError('Taslak için Google istenmemeli'),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.longPress(find.text('Veli Bilgileri').first);
      await t.pumpAndSettle();
      expect(find.text('1 form seçili'), findsOneWidget);
      await t.tap(find.byTooltip('Tümünü seç'));
      await t.pumpAndSettle();
      expect(find.text('2 form seçili'), findsOneWidget);
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Formu düzenle',
              ),
            )
            .onPressed,
        isNull,
      );
      await t.ensureVisible(find.byTooltip('Formları sil'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Formları sil'));
      await t.pumpAndSettle();
      await tap(t, 'İptal');
      expect(await s.formlar(b), hasLength(2));
      await t.ensureVisible(find.byTooltip('Formları sil'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Formları sil'));
      await t.pumpAndSettle();
      await tap(t, 'Onayla');
      await tap(t, 'Tamam');
      expect(await s.formlar(b), isEmpty);
      expect(createCount, 0);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'form silme Google’daki alınmamış yanıtları da temizler; onaylı bilgiler korunur',
    () async {
      final id = await s.formOlustur(
        b,
        baslik: 'Bilgiler',
        sorular: [
          BilgiToplamaSorusu(
            anahtar: 'telefon',
            baslik: 'Öğrenci telefon',
            hedefAlan: 'Telefon',
            veriTuru: 'Telefon',
          ),
          BilgiToplamaSorusu(anahtar: 'hobi', baslik: 'Hobiler'),
        ],
      );
      await google.hazirla(s, b, id, 'test');
      final raw = cevap();
      final yid = (await s.yanitlariKaydet(b, id, [raw])).single;
      await s.onayla(b, await s.onizle(b, yid));
      final ek = await db.query('OgrenciEkBilgiDeger');
      cevaplar = [
        raw,
        {...raw, 'responseId': 'alinmamis'},
      ];
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      await google.formuSil(s, b, id, 'test');
      expect(cevaplar, isEmpty);
      expect(scriptSilmeSayisi, 2);
      expect(remote['publishSettings']['publishState']['isPublished'], false);
      expect(await s.formlar(b), isEmpty);
      expect((await db.query('Ogrenci')).single['Telefon'], '05321112233');
      expect(await db.query('OgrenciEkBilgiDeger'), ek);
      expect(
        jsonDecode(
          (await db.query('BilgiToplamaYanit')).single['HamYanit'] as String,
        ),
        {'_yerelTemizlendi': true},
      );
      await expectLater(s.formGetir(b, id), throwsStateError);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test('silme sonrası HTTP 200 liste yokluğu ile doğrulanır', () async {
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    cevaplar = [cevap()];
    await s.silmeBaglantisiniKaydet(b, 'test-deployment');
    var kontrol = 0;
    final proxy = MockClient((r) async {
      if (r.method == 'GET' && r.url.path.contains('/responses/')) {
        kontrol++;
        return http.Response(jsonEncode({'responseId': 'r1'}), 200);
      }
      return r.method == 'GET'
          ? client.get(r.url, headers: r.headers)
          : client.post(r.url, headers: r.headers, body: r.bodyBytes);
    });
    await BilgiToplamaGoogleService(client: proxy).formuSil(s, b, id, 'test');
    expect(kontrol, 1);
    expect(cevaplar, isEmpty);
    expect(await s.formlar(b), isEmpty);
  });
  test('silme betiğine rağmen API listesinde duran yanıt korunur', () async {
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    cevaplar = [cevap()];
    await s.yanitlariKaydet(b, id, cevaplar);
    final onceki = await db.query('BilgiToplamaYanit');
    await s.silmeBaglantisiniKaydet(b, 'test-deployment');
    final proxy = MockClient((r) async {
      if (r.url.host == 'script.googleapis.com') {
        final params = jsonDecode(r.body)['parameters'] as List;
        return http.Response(
          jsonEncode({
            'done': true,
            'response': {
              'result': {
                'protocol': 'okul-yanit-sil/v1',
                'formId': params[0],
                'responseId': params[1],
                'absent': true,
                'deleted': false,
              },
            },
          }),
          200,
        );
      }
      return r.method == 'GET'
          ? client.get(r.url, headers: r.headers)
          : client.post(r.url, headers: r.headers, body: r.bodyBytes);
    });
    await expectLater(
      BilgiToplamaGoogleService(client: proxy).formuSil(s, b, id, 'test'),
      throwsStateError,
    );
    expect(await s.formlar(b), hasLength(1));
    expect(await db.query('BilgiToplamaYanit'), onceki);
  });
  test(
    'Google form silme hatasında yerel form ve ham cevaplar korunur; yeniden denenebilir',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      cevaplar = [cevap()];
      await s.yanitlariKaydet(b, id, cevaplar);
      final onceki = await db.query('BilgiToplamaYanit');
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      silmeHatasi = true;
      await expectLater(google.formuSil(s, b, id, 'test'), throwsStateError);
      expect(await s.formlar(b), hasLength(1));
      expect(await db.query('BilgiToplamaYanit'), onceki);
      silmeHatasi = false;
      await google.formuSil(s, b, id, 'test');
      expect(await s.formlar(b), isEmpty);
    },
  );
  test(
    'form silme yarım oluşturmayı ve işlem sırasında yıl değişmesini engeller',
    () async {
      final id = await taslak();
      await s.googleOlusturmayiBaslat(b, id);
      await expectLater(
        s.formuSil(b, id, googleTemizle: (_) async {}),
        throwsStateError,
      );
      await s.googleTekrarDenemeyeIzinVer(b, id);
      await google.hazirla(s, b, id, 'test');
      await expectLater(
        s.formuSil(
          b,
          id,
          googleTemizle: (_) async {
            await db.update('OkulProfil', {'EgitimYili': '2027-2028'});
          },
        ),
        throwsStateError,
      );
      await db.update('OkulProfil', {'EgitimYili': '2026-2027'});
      expect(await s.formlar(b), hasLength(1));
    },
  );
  testWidgets(
    'yanıta özel düzeltme bağlantısı yalnız ilgili öğrencinin mesaj ekranına açılır',
    (t) async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      await s.yanitlariKaydet(b, id, [cevap()]);
      await db.update('Ogrenci', {'Telefon': '05321112233'});
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiFormDetayScreen(
            service: s,
            baglam: b,
            formId: id,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, '001 • Ayşe Yılmaz');
      await tap(t, 'Öğrenciye düzeltme bağlantısı gönder');
      final ekran = t.widget<MesajlasmaScreen>(find.byType(MesajlasmaScreen));
      expect(ekran.ogrenciTelefonu, true);
      expect(ekran.izinliOgrenciIdleri, {1});
      expect(ekran.baslangicMetni, contains('?edit2=private-test'));
      await t.scrollUntilVisible(
        find.textContaining('05321112233'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('05321112233'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'öğrenci düzeltmesi tek güncel cevap olur; önceki onay yeniden onaylanana kadar korunur',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      final raw = cevap();
      final oldId = (await s.yanitlariKaydet(b, id, [raw])).single;
      final oldPreview = await s.onizle(b, oldId);
      await s.onayla(b, oldPreview);
      final edited = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      edited['lastSubmittedTime'] = '2026-10-23T18:00:00Z';
      final phoneQuestion = (remote['items'] as List)
          .last['questionItem']['question']['questionId'];
      edited['answers'][phoneQuestion]['textAnswers']['answers'][0]['value'] =
          '05329998877';
      final newId = (await s.yanitlariKaydet(b, id, [edited])).single;
      expect((await s.yanitlar(b, id)).single['Id'], newId);
      expect((await db.query('Ogrenci')).single['Telefon'], '05321112233');
      await expectLater(s.onayla(b, oldPreview), throwsStateError);
      await s.onayla(b, await s.onizle(b, newId), uyarilariKabulEt: true);
      expect((await db.query('Ogrenci')).single['Telefon'], '05329998877');
      await s.yanitlariKaydet(b, id, [raw, edited]);
      await s.yanitlariKaydet(b, id, [
        {...raw, 'lastSubmittedTime': '2026-10-22T12:00:00Z'},
      ]);
      expect(await s.yanitlar(b, id), hasLength(1));
      expect(await db.query('BilgiToplamaYanit'), hasLength(2));
    },
  );
  test(
    'kimlik uyuşmazlığında veya yanlış Google bağlantısında paylaşım engellenir',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      final raw = cevap();
      final nameQuestion =
          (remote['items']
              as List)[1]['questionItem']['question']['questionId'];
      raw['answers'][nameQuestion]['textAnswers']['answers'][0]['value'] =
          'Başka öğrenci';
      final yid = (await s.yanitlariKaydet(b, id, [raw])).single;
      await expectLater(
        s.duzeltmeHedefi(b, await s.onizle(b, yid)),
        throwsStateError,
      );
      await s.eslemeyiDuzelt(
        b,
        await s.onizle(b, yid),
        ogrenciId: 1,
        aciklama: 'Öğretmen kimliği doğruladı',
      );
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      final c = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'done': true,
            'response': {
              'result': {
                'protocol': 'okul-yanit-duzelt/v1',
                'formId': 'g1',
                'responseId': 'r1',
                'editUrl': 'https://example.com/?edit2=bad',
              },
            },
          }),
          200,
        ),
      );
      final g = BilgiToplamaGoogleService(client: c);
      await expectLater(
        g.duzeltmeBaglantisi(s, b, await s.onizle(b, yid), 'test'),
        throwsStateError,
      );
      c.close();
    },
  );
  test(
    'öğrenci telefonu mesaj kuyruğunda veli telefonundan bağımsız korunur',
    () async {
      await db.update('Ogrenci', {
        'Telefon': '05321112233',
        'AnneTelefon': '05324445566',
      });
      final servis = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
        ogrenciTelefonu: true,
      );
      final mb = await servis.hazirla();
      final students = await servis.ogrenciler(mb);
      expect(students.single.telefon, '05321112233');
      final q = await servis.kuyrukOlustur(
        mb,
        MesajOnIzleme(students),
        'Düzeltme bağlantısı',
        kaynakModul: MesajlasmaService.formDuzeltmeOgrenciModulu,
        kaynakKayit: '1:r1',
      );
      expect(q.alicilar.single.telefon, '905321112233');
      final genel = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      expect((await genel.ogrenciler(mb)).single.telefon, '05324445566');
    },
  );
  test(
    'paylaşımda eksik telefon anne ve öğrenci kaydına yazılır; eski kayıt ve kapsam korunur',
    () async {
      final veli = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final mb = await veli.hazirla();
      final eski = await veli.telefonDuzenlemeBilgileri(mb, {1});
      expect(eski.single['tur'], 'Anne');
      await veli.telefonlariKaydet(mb, {1: '05321112233'}, beklenen: eski);
      var o = (await db.query('Ogrenci')).single;
      expect(o['AnneTelefon'], '05321112233');
      expect(o['VeliTelefonu'], isNull);
      expect(o['Telefon'], isNull);
      final ogrenci = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
        ogrenciTelefonu: true,
      );
      final ogrenciEski = await ogrenci.telefonDuzenlemeBilgileri(mb, {1});
      await ogrenci.telefonlariKaydet(mb, {
        1: '05324445566',
      }, beklenen: ogrenciEski);
      o = (await db.query('Ogrenci')).single;
      expect(o['Telefon'], '05324445566');
      expect(o['AnneTelefon'], '05321112233');
      await expectLater(
        veli.telefonlariKaydet(mb, {1: '05327778899'}, beklenen: eski),
        throwsStateError,
      );
      await expectLater(
        ogrenci.telefonlariKaydet(mb, {1: 'hatalı'}, beklenen: ogrenciEski),
        throwsFormatException,
      );
      await expectLater(
        veli.telefonDuzenlemeBilgileri(mb, {999}),
        throwsStateError,
      );
    },
  );
  test(
    'form paylaşım kuyruğu hedefle sınırlı, öğrenci numarası genel ekrandan da korunur',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      await db.update('Ogrenci', {
        'Telefon': '05321112233',
        'AnneTelefon': '05324445566',
      });
      await db.insert('Ogrenci', {
        'OgrenciId': 2,
        'OkulNo': '002',
        'Ad': 'Diğer',
        'Soyad': 'Öğrenci',
        'Telefon': '05327778899',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': 2,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      final servis = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
        ogrenciTelefonu: true,
      );
      final mb = await servis.hazirla(),
          students = await servis.ogrenciler(await servis.hazirla());
      await expectLater(
        servis.kuyrukOlustur(
          mb,
          MesajOnIzleme(students),
          'Form bağlantısı',
          kaynakModul: MesajlasmaService.formPaylasimOgrenciModulu,
          kaynakKayit: '$id',
        ),
        throwsStateError,
      );
      final q = await servis.kuyrukOlustur(
        mb,
        MesajOnIzleme(students.where((o) => o.id == 1).toList()),
        'Form bağlantısı',
        kaynakModul: MesajlasmaService.formPaylasimOgrenciModulu,
        kaynakKayit: '$id',
      );
      String? acilan;
      final genel = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
        whatsappAc: (tel, _) async => acilan = tel,
      );
      await genel.aliciyiAc(mb, q.id, q.alicilar.single.id);
      expect(acilan, '905321112233');
      await db.update(
        'BilgiToplamaForm',
        {'Durum': 'Kapali'},
        where: 'Id=?',
        whereArgs: [id],
      );
      await expectLater(
        genel.aliciyiAc(mb, q.id, q.alicilar.single.id, tekrar: true),
        throwsStateError,
      );
    },
  );
  testWidgets('tek form seçimiyle taslağın adı soruları ve hedefi düzenlenir', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final id = await taslak();
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiToplamaScreen(
          service: s,
          google: google,
          hesapBagla: () async =>
              throw StateError('Yerel taslakta Google istenmemeli'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.longPress(find.text('Veli Bilgileri'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Formu düzenle'));
    await t.pumpAndSettle();
    expect(find.text('Formu düzenle'), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextField, 'Form adı'),
      '9/A Anne bilgileri',
    );
    await hedefSec(t);
    expect(find.text('1 öğrenci seçili.'), findsOneWidget);
    await tap(t, 'Devam');
    await tap(t, 'Anne adı');
    await tap(t, 'Öğrenci telefon');
    await tap(t, 'Devam');
    await tap(t, 'Değişiklikleri kaydet');
    final f = await s.formGetir(b, id);
    expect(f['Baslik'], '9/A Anne bilgileri');
    expect(f['HedefTuru'], 'OgrenciSec');
    expect(await s.formlar(b), hasLength(1));
    expect((await s.sorular(b, id)).last['HedefAlan'], 'AnneAdi');
    expect(await s.bekleyenFormDuzenlemesi(b, id), isNull);
    expect(createCount, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Google’da yanıt varsa yalnız ad düzenlenir ve eski yanıt korunur',
    (t) async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      cevaplar = [cevap()]; // Henüz SQLite'a alınmamış yanıt da kilitler.
      final eskiSorular = await s.sorular(b, id);
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiToplamaScreen(
            service: s,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.longPress(find.text('Veli Bilgileri'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Formu düzenle'));
      await t.pumpAndSettle();
      expect(find.textContaining('Yalnız form adını'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await t.enterText(
        find.widgetWithText(TextField, 'Form adı'),
        'Yeni form adı',
      );
      await tap(t, 'Değişiklikleri kaydet');
      expect((await s.formGetir(b, id))['Baslik'], 'Yeni form adı');
      expect(remote['info']['title'], 'Yeni form adı');
      expect(await s.sorular(b, id), eskiSorular);
      expect(cevaplar, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
  test(
    'yanıtsız Google formunun bağlantısı korunarak sorular ve hedefler güncellenir',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      await google.yayinla(s, b, id, 'test');
      final onceki = await s.formGetir(b, id);
      await google.formDuzenle(
        s,
        b,
        id,
        'test',
        beklenenForm: onceki,
        baslik: 'Yeni sorular',
        hedefTuru: 'OgrenciSec',
        ogrenciIdleri: {1},
        sorular: [BilgiToplamaSorusu(anahtar: 'hobi', baslik: 'Hobileriniz')],
      );
      final f = await s.formGetir(b, id);
      expect(f['GoogleFormId'], onceki['GoogleFormId']);
      expect(f['Surum'], 2);
      expect(
        remote['responderUri'],
        'https://docs.google.com/forms/d/e/gercek/viewform',
      );
      expect(
        remote['publishSettings']['publishState']['isAcceptingResponses'],
        true,
      );
      await google.kontrolEt(s, b, id, 'test');
      final yid = (await s.yanitlariKaydet(b, id, [cevap()])).single;
      await s.onayla(b, await s.onizle(b, yid));
      expect(
        (await db.query('OgrenciEkBilgiDeger')).single['Deger'],
        '05321112233',
      );
      await expectLater(
        google.formDuzenle(
          s,
          b,
          id,
          'test',
          beklenenForm: f,
          baslik: 'Yasak',
          hedefTuru: 'Siniflarim',
          sorular: [BilgiToplamaSorusu(anahtar: 'x', baslik: 'X')],
        ),
        throwsStateError,
      );
      await google.formDuzenle(
        s,
        b,
        id,
        'test',
        beklenenForm: f,
        baslik: 'Yalnız adı değişti',
      );
      expect((await s.formGetir(b, id))['Surum'], 2);
      expect((await s.yanitlar(b, id)).single['Durum'], 'Onaylandi');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'kapatma sırasında yanıt gelirse soru düzenlemesi iptal edilip yayın geri açılır',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      await google.yayinla(s, b, id, 'test');
      final onceki = await s.formGetir(b, id), ss = await s.sorular(b, id);
      final c = MockClient((r) async {
        if (r.url.path.endsWith(':setPublishSettings') &&
            jsonDecode(
                  r.body,
                )['publishSettings']['publishState']['isPublished'] ==
                false) {
          cevaplar = [cevap()];
        }
        return r.method == 'GET'
            ? client.get(r.url, headers: r.headers)
            : client.post(r.url, headers: r.headers, body: r.bodyBytes);
      });
      final g = BilgiToplamaGoogleService(client: c);
      await expectLater(
        g.formDuzenle(
          s,
          b,
          id,
          'test',
          beklenenForm: onceki,
          baslik: 'Yeni',
          hedefTuru: 'Siniflarim',
          sorular: [BilgiToplamaSorusu(anahtar: 'ek1', baslik: 'Yeni soru')],
        ),
        throwsStateError,
      );
      expect(await s.sorular(b, id), ss);
      expect(await s.formGetir(b, id), onceki);
      expect(await s.bekleyenFormDuzenlemesi(b, id), isNull);
      expect(
        remote['publishSettings']['publishState']['isAcceptingResponses'],
        true,
      );
      c.close();
    },
  );
  test(
    'Google kaydından sonra bağlantı koparsa aynı düzenleme güvenle sürdürülür',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      await google.yayinla(s, b, id, 'test');
      final onceki = await s.formGetir(b, id);
      var fail = true, soruYazimi = 0;
      final c = MockClient((r) async {
        final sonuc = r.method == 'GET'
            ? await client.get(r.url, headers: r.headers)
            : await client.post(r.url, headers: r.headers, body: r.bodyBytes);
        if (r.url.path.endsWith(':batchUpdate') &&
            (jsonDecode(r.body)['requests'] as List).any(
              (q) => q['deleteItem'] != null,
            )) {
          soruYazimi++;
          if (fail) {
            fail = false;
            throw http.ClientException('Yanıt kesildi');
          }
        }
        return sonuc;
      });
      final g = BilgiToplamaGoogleService(client: c);
      await expectLater(
        g.formDuzenle(
          s,
          b,
          id,
          'test',
          beklenenForm: onceki,
          baslik: 'Yeni',
          hedefTuru: 'Siniflarim',
          sorular: [BilgiToplamaSorusu(anahtar: 'ek1', baslik: 'Yeni soru')],
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect((await s.formGetir(b, id))['Baslik'], onceki['Baslik']);
      expect(await s.bekleyenFormDuzenlemesi(b, id), isNotNull);
      await expectLater(s.yanitlariKaydet(b, id, [cevap()]), throwsStateError);
      await g.formDuzenlemeyiSurdur(s, b, id, 'test');
      expect(soruYazimi, 1);
      expect((await s.formGetir(b, id))['Baslik'], 'Yeni');
      expect(await s.bekleyenFormDuzenlemesi(b, id), isNull);
      await google.kontrolEt(s, b, id, 'test');
      expect(
        remote['publishSettings']['publishState']['isAcceptingResponses'],
        true,
      );
      c.close();
    },
  );
  test(
    'yerel kayıt tamamlanıp yeniden yayınlama kesilirse yalnız yayınlama sürdürülür',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      await google.yayinla(s, b, id, 'test');
      final eski = await s.formGetir(b, id);
      var fail = true, soruYazimi = 0;
      final c = MockClient((r) async {
        if (r.url.path.endsWith(':setPublishSettings') &&
            jsonDecode(
                  r.body,
                )['publishSettings']['publishState']['isPublished'] ==
                true &&
            fail) {
          fail = false;
          return http.Response('{}', 503);
        }
        if (r.url.path.endsWith(':batchUpdate')) soruYazimi++;
        return r.method == 'GET'
            ? client.get(r.url, headers: r.headers)
            : client.post(r.url, headers: r.headers, body: r.bodyBytes);
      });
      final g = BilgiToplamaGoogleService(client: c);
      await expectLater(
        g.formDuzenle(
          s,
          b,
          id,
          'test',
          beklenenForm: eski,
          baslik: 'Kaydedilen yeni form',
          hedefTuru: 'Siniflarim',
          sorular: [BilgiToplamaSorusu(anahtar: 'ek1', baslik: 'Yeni soru')],
        ),
        throwsStateError,
      );
      expect((await s.formGetir(b, id))['Baslik'], 'Kaydedilen yeni form');
      expect(
        (await s.bekleyenFormDuzenlemesi(b, id))!['yerelKaydedildi'],
        true,
      );
      await g.formDuzenlemeyiSurdur(s, b, id, 'test');
      expect(soruYazimi, 1);
      expect(await s.bekleyenFormDuzenlemesi(b, id), isNull);
      expect(
        remote['publishSettings']['publishState']['isAcceptingResponses'],
        true,
      );
      c.close();
    },
  );
  test(
    'yerel yanıt ve kapsam değişikliği soru düzenlemesini arayüz dışında da engeller',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      final eski = await s.formGetir(b, id);
      await expectLater(
        s.formDuzenlemeHazirla(
          b,
          id,
          beklenenForm: eski,
          baslik: 'Yanlış kapsam',
          hedefTuru: 'OgrenciSec',
          ogrenciIdleri: {999},
          sorular: [BilgiToplamaSorusu(anahtar: 'x', baslik: 'X')],
        ),
        throwsStateError,
      );
      await s.yanitlariKaydet(b, id, [cevap()]);
      await expectLater(
        s.formDuzenlemeHazirla(
          b,
          id,
          beklenenForm: eski,
          baslik: 'Yanıt varken',
          hedefTuru: 'Siniflarim',
          sorular: [BilgiToplamaSorusu(anahtar: 'x', baslik: 'X')],
        ),
        throwsStateError,
      );
      expect(await s.bekleyenFormDuzenlemesi(b, id), isNull);
      await google.formDuzenle(
        s,
        b,
        id,
        'test',
        beklenenForm: eski,
        baslik: 'Yalnız yeni ad',
      );
      final p = await s.onizle(
        b,
        (await s.yanitlar(b, id)).single['Id'] as int,
      );
      expect(p.hatalar, isEmpty);
      await s.onayla(b, p);
      expect((await db.query('Ogrenci')).single['Telefon'], '05321112233');
    },
  );
  testWidgets(
    'paylaşım seçimi iptal edilebilir, öğrenci seçilince yalnız hedef öğrenciler açılır',
    (t) async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      await db.update('Ogrenci', {'Telefon': '05321112233'});
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiFormDetayScreen(
            service: s,
            baglam: b,
            formId: id,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Ön İzle ve Onayla');
      expect(find.text('Form alıcıları'), findsOneWidget);
      Navigator.of(t.element(find.text('Form alıcıları'))).pop();
      await t.pumpAndSettle();
      expect(remote['publishSettings']['publishState']['isPublished'], false);
      expect(await s.formPaylasildiMi(b, id), false);
      await tap(t, 'Ön İzle ve Onayla');
      await aliciSec(t, veli: false);
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      final ekran = t.widget<MesajlasmaScreen>(find.byType(MesajlasmaScreen));
      expect(ekran.baslangicKisiBaglari, {'Ogrenci:1:1'});
      expect(ekran.kaynakModul, 'BilgiFormOrtakPaylasim');
      expect(
        ekran.baslangicMetni,
        contains('https://docs.google.com/forms/d/e/gercek/viewform'),
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('paylaşım başarısızsa form açma ve yanıt getirme gizli kalır', (
    t,
  ) async {
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    final c = MockClient((r) async {
      if (r.url.path.endsWith(':setPublishSettings')) {
        return http.Response('{}', 503);
      }
      return r.method == 'GET'
          ? client.get(r.url, headers: r.headers)
          : client.post(r.url, headers: r.headers, body: r.bodyBytes);
    });
    addTearDown(c.close);
    final g = BilgiToplamaGoogleService(client: c);
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiFormDetayScreen(
          service: s,
          baglam: b,
          formId: id,
          google: g,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Ön İzle ve Onayla');
    await aliciSec(t);
    expect(find.text('Formu aç'), findsNothing);
    expect(find.text('Yanıtları getir'), findsNothing);
    expect(await s.formPaylasildiMi(b, id), false);
    expect(find.textContaining('HTTP 503'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Google hazırla, yayımla, yanıt kontrol et ve onayla', (t) async {
    final id = await taslak();
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiFormDetayScreen(
          service: s,
          baglam: b,
          formId: id,
          google: google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Google Formu Hazırla');
    expect(createCount, 1);
    expect(find.text('Ön İzle ve Onayla'), findsOneWidget);
    expect(find.text('Formu aç'), findsNothing);
    expect(find.text('Yanıtları getir'), findsNothing);
    expect(find.text('Yayımla ve bağlantıyı kopyala'), findsNothing);
    expect(find.text('Bağlantıyı kopyala'), findsNothing);
    await tap(t, 'Ön İzle ve Onayla');
    await aliciSec(t);
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    Navigator.of(t.element(find.byType(AlertDialog).first)).pop();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Formu aç'),
      220,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first,
    );
    expect(find.text('Formu aç'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Yanıtları getir'),
      150,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first,
    );
    expect(find.text('Yanıtları getir'), findsOneWidget);
    expect(await s.formPaylasildiMi(b, id), true);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiFormDetayScreen(
          service: s,
          baglam: b,
          formId: id,
          google: google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Formu aç'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Yanıtları getir'),
      150,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first,
    );
    expect(find.text('Yanıtları getir'), findsOneWidget);
    expect(remote['publishSettings']['publishState']['isPublished'], true);
    expect(
      remote['publishSettings']['publishState']['isAcceptingResponses'],
      true,
    );
    cevaplar = [cevap()];
    await tap(t, 'Yanıtları getir');
    await tap(t, '001 • Ayşe Yılmaz');
    expect(find.textContaining('Kayıtta: 001'), findsOneWidget);
    expect(find.textContaining('05321112233'), findsOneWidget);
    await tap(t, 'Onayla ve kaydet');
    await tap(t, 'Onayla');
    expect((await db.query('Ogrenci')).single['Telefon'], '05321112233');
    expect((await db.query('BilgiToplamaYanit')).single['Durum'], 'Onaylandi');
    expect(t.takeException(), isNull);
  });
  test('yarım kalan soru isteği aynı Google formuyla sürdürülür', () async {
    final id = await taslak();
    var fail = true;
    final wrapper = MockClient((r) async {
      if (fail && r.url.path.endsWith(':batchUpdate')) {
        fail = false;
        return http.Response('{}', 503);
      }
      return r.method == 'GET'
          ? client.get(r.url, headers: r.headers)
          : client.post(r.url, headers: r.headers, body: r.bodyBytes);
    });
    final g = BilgiToplamaGoogleService(client: wrapper);
    await expectLater(g.hazirla(s, b, id, 'test'), throwsStateError);
    expect((await s.formGetir(b, id))['GoogleFormId'], 'g1');
    await g.hazirla(s, b, id, 'test');
    expect(createCount, 1);
    expect((await s.formGetir(b, id))['Durum'], 'Aktif');
    wrapper.close();
  });
  testWidgets(
    'yanıt düzeltme, iptal, doğrulama ve onaylı yanıtı yeniden düzenleme',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      final raw = cevap();
      cevaplar = [raw];
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      final yanitId = (await s.yanitlariKaydet(b, id, [raw])).single;
      await t.pumpWidget(
        MaterialApp(
          home: BireyselBilgiFormDetayScreen(
            service: s,
            baglam: b,
            formId: id,
            google: google,
            hesapBagla: () async => 'test',
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, '001 • Ayşe Yılmaz');
      await tap(t, 'Yanıtları düzenle');
      await t.enterText(
        find.widgetWithText(TextField, 'Öğrenci telefon'),
        'hatalı',
      );
      await tap(t, 'Düzeltmeleri ön izle');
      expect(find.textContaining('Telefon biçimi geçersiz'), findsOneWidget);
      expect(await db.query('BilgiToplamaYanit'), hasLength(1));
      await tap(t, 'İptal');
      await tap(t, 'Yanıtları düzenle');
      expect(find.text('05321112233'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'Öğrenci telefon'),
        '05329998877',
      );
      await tap(t, 'Düzeltmeleri ön izle');
      final rows = await s.yanitlar(b, id);
      expect(rows, hasLength(1));
      expect(
        (await db.query('BilgiToplamaYanit')).first['Durum'],
        'Reddedildi',
      );
      expect((await db.query('Ogrenci')).single['Telefon'], isNull);
      await expectLater(
        s.onayla(b, await s.onizle(b, yanitId)),
        throwsStateError,
      );
      final corrected = rows.first['Id'] as int;
      final p = await s.onizle(b, corrected);
      expect(p.degisiklikler['Telefon']!['yeni'], '05329998877');
      expect(
        jsonDecode(rows.first['HamYanit'] as String)['answers'],
        raw['answers'],
      );
      expect((await s.yanitlariKaydet(b, id, [raw])).single, yanitId);
      await tap(t, 'Onayla ve kaydet');
      await tap(t, 'Onayla');
      expect((await db.query('Ogrenci')).single['Telefon'], '05329998877');
      await tap(t, '001 • Ayşe Yılmaz');
      await tap(t, 'Yanıtları düzenle');
      await t.enterText(
        find.widgetWithText(TextField, 'Öğrenci telefon'),
        '05324445566',
      );
      await tap(t, 'Düzeltmeleri ön izle');
      expect((await db.query('Ogrenci')).single['Telefon'], '05329998877');
      expect(
        (await db.query(
          'BilgiToplamaYanit',
          where: 'Id=?',
          whereArgs: [corrected],
        )).single['Durum'],
        'Onaylandi',
      );
      await tap(t, 'Onayla ve kaydet');
      await tap(t, 'Onayla');
      expect((await db.query('Ogrenci')).single['Telefon'], '05324445566');
      expect(await s.yanitlar(b, id), hasLength(1));
      expect(find.text('001 • Ayşe Yılmaz'), findsOneWidget);
      await tap(t, '001 • Ayşe Yılmaz');
      await tap(t, 'Google Forms ve uygulamadan sil');
      expect(find.textContaining('geri alınamaz'), findsOneWidget);
      await tap(t, 'İptal');
      expect(scriptSilmeSayisi, 0);
      expect(await s.yanitlar(b, id), hasLength(1));
      final silinecek = await s.onizle(
        b,
        (await s.yanitlar(b, id)).single['Id'] as int,
      );
      final silinecekCevaplar = await s.duzenlenecekCevaplar(b, silinecek);
      silmeHatasi = true;
      await tap(t, 'Google Forms ve uygulamadan sil');
      await tap(t, 'Onayla');
      expect(await s.yanitlar(b, id), hasLength(1));
      expect(cevaplar, hasLength(1));
      silmeHatasi = false;
      await tap(t, 'Google Forms ve uygulamadan sil');
      await tap(t, 'Onayla');
      expect(cevaplar, isEmpty);
      expect(await s.yanitlar(b, id), isEmpty);
      expect((await db.query('Ogrenci')).single['Telefon'], '05324445566');
      await expectLater(
        s.yanitiDuzenle(b, silinecek, silinecekCevaplar),
        throwsStateError,
      );
      cevaplar = [raw];
      await t.pumpAndSettle();
      await tap(t, 'Yanıtları getir');
      expect(await s.yanitlar(b, id), isEmpty);
      expect(find.text('001 • Ayşe Yılmaz'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('dar ekranda toplu silme onayı ve iptal', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    cevaplar = [cevap()];
    await s.silmeBaglantisiniKaydet(b, 'test-deployment');
    await t.pumpWidget(
      MaterialApp(
        home: BireyselBilgiFormDetayScreen(
          service: s,
          baglam: b,
          formId: id,
          google: google,
          hesapBagla: () async => 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Yanıtlar');
    await tap(t, 'Toplu sil');
    await tap(t, 'Tüm yanıtları sil');
    await t.pump(const Duration(milliseconds: 350));
    expect(
      find.textContaining('1 yanıt henüz öğrenciye kaydedilmemiş'),
      findsOneWidget,
    );
    await tap(t, 'İptal');
    expect(scriptSilmeSayisi, 0);
    expect(cevaplar, hasLength(1));
    await tap(t, 'Toplu sil');
    await tap(t, 'Tüm yanıtları sil');
    await tap(t, 'Onayla');
    await t.pump(const Duration(milliseconds: 350));
    expect(find.text('Toplu silme sonucu'), findsOneWidget);
    expect(cevaplar, isEmpty);
    await tap(t, 'Tamam');
    expect(await s.yanitlar(b, id), isEmpty);
    expect(t.takeException(), isNull);
  });
  test(
    'toplu silme yalnız kaydedilenleri temizler, öğrenci ve yeni yanıt korunur',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      final raw = cevap();
      final yid = (await s.yanitlariKaydet(b, id, [raw])).single;
      await s.onayla(b, await s.onizle(b, yid), uyarilariKabulEt: true);
      await s.yanitlariKaydet(b, id, [
        {...raw, 'responseId': 'r2'},
      ]);
      final plan = await s.topluSilmePlani(b, id, sadeceKaydedilenler: true);
      expect(plan.googleYanitIdleri, ['r1']);
      expect(plan.kaydedilmemisSayisi, 0);
      await s.yanitlariKaydet(b, id, [
        {...raw, 'responseId': 'r3'},
      ]);
      cevaplar = [
        raw,
        {...raw, 'responseId': 'r2'},
        {...raw, 'responseId': 'r3'},
      ];
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      final sonuc = await google.yanitlariTopluSil(s, b, plan, 'test');
      expect(sonuc.basarili, 1);
      expect(sonuc.kalan, 0);
      expect(cevaplar.map((r) => r['responseId']), ['r2', 'r3']);
      expect((await db.query('Ogrenci')).single['Telefon'], '05321112233');
      final temiz = (await db.query(
        'BilgiToplamaYanit',
        where: 'Id=?',
        whereArgs: [yid],
      )).single;
      expect(jsonDecode(temiz['HamYanit'] as String), {
        '_yerelTemizlendi': true,
      });
      expect(temiz['GirilenAdSoyad'], '');
      expect(temiz['SoruAnlikGoruntusu'], '[]');
      await s.yanitlariKaydet(b, id, [raw]);
      expect(await s.yanitlar(b, id), hasLength(2));
    },
  );
  test(
    'toplu silme durdurulup kalanlarla sürdürülebilir; hata veriyi korur',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      cevaplar = [
        cevap(),
        {...cevap(), 'responseId': 'r2'},
      ];
      await s.yanitlariKaydet(b, id, cevaplar);
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      var plan = await s.topluSilmePlani(b, id, sadeceKaydedilenler: false);
      expect(plan.kaydedilmemisSayisi, 2);
      silmeHatasi = true;
      var sonuc = await google.yanitlariTopluSil(s, b, plan, 'test');
      expect(sonuc.basarili, 0);
      expect(sonuc.kalan, 2);
      expect(await s.yanitlar(b, id), hasLength(2));
      silmeHatasi = false;
      var devam = true;
      sonuc = await google.yanitlariTopluSil(
        s,
        b,
        plan,
        'test',
        devamEt: () => devam,
        ilerleme: (_, _) => devam = false,
      );
      expect(sonuc.basarili, 1);
      expect(sonuc.kalan, 1);
      plan = await s.topluSilmePlani(b, id, sadeceKaydedilenler: false);
      expect(plan.toplam, 1);
      sonuc = await google.yanitlariTopluSil(s, b, plan, 'test');
      expect(sonuc.basarili, 1);
      expect(await s.yanitlar(b, id), isEmpty);
      expect(cevaplar, isEmpty);
    },
  );
  test('onaydan sonra değişen yerel yanıt Google silmesini engeller', () async {
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    final yid = (await s.yanitlariKaydet(b, id, [cevap()])).single;
    final plan = await s.topluSilmePlani(b, id, sadeceKaydedilenler: false);
    await s.onayla(b, await s.onizle(b, yid), uyarilariKabulEt: true);
    var remoteCalled = false;
    await expectLater(
      s.topluSilmeYanitiSil(
        b,
        plan,
        'r1',
        googleSil: (_, _) async {
          remoteCalled = true;
        },
      ),
      throwsStateError,
    );
    expect(remoteCalled, false);
    expect(await s.yanitlar(b, id), hasLength(1));
  });
  test('sonucu belirsiz oluşturma isteği otomatik tekrarlanmaz', () async {
    final id = await taslak();
    var calls = 0;
    final c = MockClient((r) async {
      calls++;
      throw http.ClientException('Bağlantı kesildi');
    });
    final g = BilgiToplamaGoogleService(client: c);
    await expectLater(
      g.hazirla(s, b, id, 'test'),
      throwsA(isA<http.ClientException>()),
    );
    await expectLater(g.hazirla(s, b, id, 'test'), throwsStateError);
    expect(calls, 1);
    c.close();
  });
  test(
    'ayrı Google yanıtları birleşmez; silinenin yeni kaynak sürümü geri gelmez',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      final raw = cevap();
      final ilkId = (await s.yanitlariKaydet(b, id, [raw])).single;
      final ikinci = {...cevap(), 'responseId': 'r2'};
      await s.yanitlariKaydet(b, id, [ikinci]);
      expect(await s.yanitlar(b, id), hasLength(2));
      final eski = await s.onizle(b, ilkId);
      await s.yanitiSil(b, eski);
      await expectLater(
        s.onayla(b, eski, uyarilariKabulEt: true),
        throwsStateError,
      );
      await s.yanitlariKaydet(b, id, [
        {...raw, 'lastSubmittedTime': '2026-10-23T10:00:00Z'},
      ]);
      final kalan = await s.yanitlar(b, id);
      expect(kalan, hasLength(1));
      expect(kalan.single['GoogleYanitId'], 'r2');
      expect((await db.query('Ogrenci')).single['Telefon'], isNull);
      final kapsamDisi = await s.formOlustur(
        b,
        baslik: 'Diğer form',
        sorular: [BilgiToplamaSorusu(anahtar: 'ek', baslik: 'Ek')],
      );
      expect(await s.yanitlar(b, kapsamDisi), isEmpty);
    },
  );
  test('silme bağlantısı eksikse Google isteği yapılmaz', () async {
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    final yid = (await s.yanitlariKaydet(b, id, [cevap()])).single;
    await expectLater(
      google.yanitiSil(s, b, await s.onizle(b, yid), 'test'),
      throwsStateError,
    );
    expect(scriptSilmeSayisi, 0);
    expect(await s.yanitlar(b, id), hasLength(1));
  });
  for (final durum in [
    'scriptError',
    'pending',
    'wrongId',
    'stillExists',
    'denied',
    'network',
    'lostReply',
  ]) {
    test('Google silme doğrulanmazsa yerel yanıt korunur: $durum', () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      final raw = cevap();
      final yid = (await s.yanitlariKaydet(b, id, [raw])).single;
      final p = await s.onizle(b, yid);
      await s.silmeBaglantisiniKaydet(b, 'test-deployment');
      var removed = false;
      final c = MockClient((r) async {
        if (r.url.host == 'script.googleapis.com') {
          expect((await s.yanitlar(b, id)), hasLength(1));
          if (durum == 'network') {
            throw http.ClientException('Bağlantı kesildi');
          }
          if (durum == 'lostReply') {
            removed = true;
            throw http.ClientException('Silme sonrası yanıt kesildi');
          }
          return http.Response(
            jsonEncode({
              'done': durum != 'pending',
              if (durum == 'scriptError') 'error': {'code': 3},
              'response': {
                'result': {
                  'protocol': 'okul-yanit-sil/v1',
                  'formId': 'g1',
                  'responseId': durum == 'wrongId' ? 'r2' : 'r1',
                  'absent': true,
                },
              },
            }),
            200,
          );
        }
        if (r.url.path.endsWith('/responses')) {
          return http.Response(
            jsonEncode({
              'responses': [raw],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (r.url.path.contains('/responses/')) {
          return http.Response('{}', durum == 'denied' ? 403 : 200);
        }
        return http.Response(
          jsonEncode(remote),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final g = BilgiToplamaGoogleService(client: c);
      await expectLater(
        g.yanitiSil(s, b, p, 'test'),
        throwsA(anyOf(isA<Exception>(), isA<StateError>())),
      );
      expect(await s.yanitlar(b, id), hasLength(1));
      if (removed) {
        // İlk istek silmiş olsa da yeniden deneme aynı kimlikle tamamlanır.
        await google.yanitiSil(s, b, await s.onizle(b, yid), 'test');
        expect(await s.yanitlar(b, id), isEmpty);
      }
      c.close();
    });
  }
  test('Google silinirken yıl değişirse yerel kayıt silinmez', () async {
    final id = await taslak();
    await google.hazirla(s, b, id, 'test');
    final yid = (await s.yanitlariKaydet(b, id, [cevap()])).single;
    final p = await s.onizle(b, yid);
    await expectLater(
      s.yanitiGoogleIleSil(
        b,
        p,
        googleSil: (gid, rid) async {
          expect(gid, 'g1');
          expect(rid, 'r1');
          await db.update('OkulProfil', {'EgitimYili': '2027-2028'});
        },
      ),
      throwsStateError,
    );
    await db.update('OkulProfil', {'EgitimYili': '2026-2027'});
    expect(await s.yanitlar(b, id), hasLength(1));
  });
  test(
    'Google sorusu değiştiğinde yanıt aktarılmaz; yayımlanmadan link paylaşılmaz',
    () async {
      final id = await taslak();
      await google.hazirla(s, b, id, 'test');
      expect(
        () => BilgiToplamaGoogleService.paylasimBaglantisi(remote),
        throwsStateError,
      );
      (remote['items'] as List).first['title'] = 'Yanlış soru';
      await expectLater(google.yanitlariAl(s, b, id, 'test'), throwsStateError);
      expect(await db.query('BilgiToplamaYanit'), isEmpty);
    },
  );
}
