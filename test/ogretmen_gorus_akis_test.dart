import 'dart:convert';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bilgi_toplama_service.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_ogretmen_gorus_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_bilgi_toplama_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/ogretmen_gorus_google_service.dart';
import 'package:elpi_okul_yonetim/services/ogretmen_gorus_fotograf.dart';
import 'package:elpi_okul_yonetim/screens/ogretmen_gorus_form_screen.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselRehberlikService s;
  late BireyselRehberlikBaglami b;
  late MesajlasmaService ms;
  late int toplanti;
  CalismaModu? mod;
  final acilan = <String>[];
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    mod = CalismaModu.bireyselOgretmen;
    s = BireyselRehberlikService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
    );
    acilan.clear();
    ms = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
      whatsappAc: (tel, metin) async => acilan.add('$tel|$metin'),
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
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'SiraNo': 1});
    for (var i = 1; i <= 2; i++) {
      await db.insert('SinifSube', {
        'SinifKodu': '9-$i',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': i,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': i == 1 ? 'Pazartesi' : 'Salı',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ogrenci', {
        'OkulNo': '$i',
        'Ad': 'Öğrenci$i',
        'Soyad': 'Test',
        'AnneAdi': 'ÖZEL VELİ',
        'AnneTelefon': '05321112233',
        'VeliTuru': 'Anne',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': i,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('RehberlikAtama', {
        'OkulId': 'okul',
        'OgretmenProfilId': 1,
        'SinifSubeId': i,
        'EgitimOgretimYili': '2026-2027',
        'BaslangicTarihi': '2000-01-01',
        'OlusturmaTarihi': 'test',
      });
    }
    b = await s.hazirla();
    toplanti = await s.kayitKaydet(
      b,
      1,
      tur: 'Toplanti',
      baslik: 'Sınıf toplantısı',
      icerik: {},
    );
    final mb = await ms.hazirla();
    for (var i = 1; i <= 2; i++) {
      await ms.ogretmenIletisimKaydet(
        mb,
        ad: 'Ders öğretmeni $i',
        telefon: '0532111223$i',
        sinifIdleri: {i},
        sinifIliskileriniDogruladim: true,
      );
    }
  });
  tearDown(() async => LocalDatabase.instance.close());
  Map<String, dynamic> istek() => {
    'requestId': 'a' * 32,
    'kapsam': s.ogretmenGorusKapsamAnahtari(b, 1, toplanti),
    'baslik': 'Sınıf görüşü',
    'sinif': '9-1',
    'yil': b.egitimOgretimYili,
    'ogrenciler': [
      {'id': 1, 'no': '1', 'ad': 'Öğrenci1 Test', 'foto': null},
    ],
  };
  Map<String, dynamic> sonuc(String requestId, {bool yayin = false}) => {
    'protocol': 'okul-ogretmen-gorus/v1',
    'requestId': requestId,
    'formId': 'form_1',
    'ready': true,
    'published': yayin,
    'acceptingResponses': yayin,
    'editUrl': 'https://docs.google.com/forms/d/form_1/edit',
    'responderUrl': 'https://docs.google.com/forms/d/e/form_1/viewform',
  };
  Future<void> kaydet() async {
    await s.ogretmenGorusIstegiKaydet(
      b,
      1,
      toplanti,
      hesap: 'test@okul.com',
      istek: istek(),
    );
    await s.ogretmenGorusSonucKaydet(
      b,
      1,
      toplanti,
      requestId: 'a' * 32,
      hesap: 'test@okul.com',
      sonuc: sonuc('a' * 32),
    );
  }

  test(
    'aynı toplantı isteği korunur; başka toplantı ve hesap karışmaz',
    () async {
      await kaydet();
      final yeniden = await s.ogretmenGorusIstegiKaydet(
        b,
        1,
        toplanti,
        hesap: 'test@okul.com',
        istek: {...istek(), 'requestId': 'b' * 32},
      );
      expect((yeniden['istek'] as Map)['requestId'], 'a' * 32);
      await expectLater(
        s.ogretmenGorusIstegiKaydet(
          b,
          1,
          toplanti,
          hesap: 'baska@okul.com',
          istek: istek(),
        ),
        throwsStateError,
      );
      final diger = await s.kayitKaydet(
        b,
        1,
        tur: 'Toplanti',
        baslik: 'Başka',
        icerik: {},
      );
      expect((await s.ogretmenGorusDurumu(b, 1, diger))['form'], isNull);
      await expectLater(
        s.ogretmenGorusSonucKaydet(
          b,
          1,
          toplanti,
          requestId: 'a' * 32,
          hesap: 'test@okul.com',
          sonuc: {...sonuc('a' * 32), 'formId': 'baska'},
        ),
        throwsStateError,
      );
    },
  );
  test(
    'başka sınıf öğrencisi, yanlış atama ve değişen yıl reddedilir',
    () async {
      final g = istek();
      (g['ogrenciler'] as List).add({
        'id': 2,
        'no': '2',
        'ad': 'Başka',
        'foto': null,
      });
      await expectLater(
        s.ogretmenGorusIstegiKaydet(
          b,
          1,
          toplanti,
          hesap: 'test@okul.com',
          istek: g,
        ),
        throwsStateError,
      );
      await expectLater(
        s.ogretmenGorusDurumu(b, 2, toplanti),
        throwsStateError,
      );
      await db.update('OkulProfil', {'EgitimYili': '2027-2028'});
      await expectLater(
        s.ogretmenGorusDurumu(b, 1, toplanti),
        throwsStateError,
      );
    },
  );
  test('bitmiş atama okunur ama form hazırlama/gönderim engellenir', () async {
    await kaydet();
    await db.update('RehberlikAtama', {
      'BitisTarihi': '2001-01-01',
    }, where: 'RehberlikAtamaId=1');
    expect((await s.ogretmenGorusDurumu(b, 1, toplanti))['form'], isNotNull);
    await expectLater(
      s.ogretmenGorusDurumu(b, 1, toplanti, yazma: true),
      throwsStateError,
    );
  });
  test('hassas kayıt ve kurumsal mod erişimi denetlenir', () async {
    await db.update(
      'RehberlikKayit',
      {'Hassas': 1},
      where: 'Id=?',
      whereArgs: [toplanti],
    );
    await expectLater(s.ogretmenGorusDurumu(b, 1, toplanti), throwsStateError);
    expect(
      await s.ogretmenGorusDurumu(b, 1, toplanti, hassasOnay: true),
      isNotEmpty,
    );
    mod = null;
    await expectLater(
      s.ogretmenGorusDurumu(b, 1, toplanti, hassasOnay: true),
      throwsStateError,
    );
  });
  testWidgets('fotoğraf küçültülür; URL kaynağı alınmaz', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xff0055aa), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(500, 700);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      final r = await ogretmenGorusFotografi({
        'FotoVerisi': png!.buffer.asUint8List(),
      });
      expect(r!['mime'], 'image/png');
      expect(base64Decode(r['base64']!).length, lessThanOrEqualTo(102400));
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        base64Decode(r['base64']!),
      );
      final d = await ui.ImageDescriptor.encoded(buffer);
      expect(d.height, 240);
      expect(d.width, lessThan(240));
      d.dispose();
      buffer.dispose();
      await expectLater(
        ogretmenGorusFotografi({'DosyaYolu': 'https://example.com/a.png'}),
        throwsFormatException,
      );
    });
  });

  Future<void> bekle(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  BireyselBilgiToplamaService ortakFormlar() => BireyselBilgiToplamaService(
    databaseGetir: () async => db,
    modGetir: () async => mod,
  );

  test(
    'ortak katalog eski toplantı formunu tek kayıtla gösterir ve kapsamı korur',
    () async {
      final f = ortakFormlar();
      final fb = await f.hazirla();
      expect(await f.ogretmenGorusFormlari(fb), isEmpty);
      expect(
        await f.ogretmenGorusFormlari(fb, yalnizKayitli: false),
        hasLength(1),
      );
      await kaydet();
      await kaydet();
      final liste = await f.ogretmenGorusFormlari(fb);
      expect(liste, hasLength(1));
      expect(liste.single['ToplantiId'], toplanti);
      expect(liste.single['Hazir'], true);
      expect(liste.single['SaltOkunur'], false);
      // Hassas toplantının başlığı ortak listede kilit açılmadan gösterilmez.
      await db.update(
        'RehberlikKayit',
        {'Hassas': 1},
        where: 'Id=?',
        whereArgs: [toplanti],
      );
      expect(await f.ogretmenGorusFormlari(fb), isEmpty);
      await db.update(
        'RehberlikKayit',
        {'Hassas': 0},
        where: 'Id=?',
        whereArgs: [toplanti],
      );
      await db.update('RehberlikAtama', {
        'BitisTarihi': '2000-01-02',
      }, where: 'RehberlikAtamaId=1');
      expect((await f.ogretmenGorusFormlari(fb)).single['SaltOkunur'], true);
      await db.update('OkulProfil', {'EgitimYili': '2027-2028'}, where: 'Id=1');
      await expectLater(f.ogretmenGorusFormlari(fb), throwsStateError);
    },
  );

  test(
    'görüş yanıtı kısmi silmede doğrulanır başarısız kayıt korunur',
    () async {
      await kaydet();
      final eski = [
        for (final id in ['r1', 'r2'])
          <String, dynamic>{
            'responseId': id,
            'ogretmen': 'Ders öğretmeni 1',
            'ders': 'Matematik',
            'ogrenciler': <String, String>{'1': 'Görüş'},
          },
      ];
      await s.ogretmenGorusYonet(
        b,
        1,
        toplanti,
        requestId: 'a' * 32,
        formId: 'form_1',
        yanitlar: eski,
      );
      final silinen = <String>{};
      final google = OgretmenGorusGoogleService(
        client: MockClient((r) async {
          if (r.url.host == 'script.googleapis.com') {
            final rid = (jsonDecode(r.body)['parameters'] as List)[1];
            if (rid == 'r2') return http.Response('{}', 403);
            silinen.add(rid as String);
            return http.Response(
              jsonEncode({
                'done': true,
                'response': {
                  'result': {
                    'protocol': 'okul-yanit-sil/v1',
                    'formId': 'form_1',
                    'responseId': rid,
                    'absent': true,
                  },
                },
              }),
              200,
            );
          }
          if (r.url.path.contains('/responses/')) {
            return http.Response(
              '{}',
              silinen.contains(r.url.pathSegments.last) ? 404 : 200,
            );
          }
          return http.Response(jsonEncode({'formId': 'form_1'}), 200);
        }),
      );
      final f = BilgiToplamaOgretmenGorusService(
        formlar: ortakFormlar(),
        kaynak: s,
        baglam: b,
        atamaId: 1,
        toplantiId: toplanti,
        google: google,
      );
      final hatalar = await f.yanitlariSil('test', 'a' * 32, 'form_1', {
        'r1',
        'r2',
      });
      expect(hatalar, hasLength(1));
      final v = (await s.ogretmenGorusDurumu(b, 1, toplanti))['form'] as Map;
      expect((v['yanitlar'] as List).map((y) => y['responseId']), ['r2']);
      await s.ogretmenGorusYonet(
        b,
        1,
        toplanti,
        requestId: 'a' * 32,
        formId: 'form_1',
        yanitlar: eski,
      );
      final tekrar =
          (await s.ogretmenGorusDurumu(b, 1, toplanti))['form'] as Map;
      expect((tekrar['yanitlar'] as List).map((y) => y['responseId']), ['r2']);
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneAdi'],
        'ÖZEL VELİ',
      );
      await expectLater(
        f.yanitlariSil('test', 'a' * 32, 'baska', {'r2'}),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'ortak form listesinden mevcut öğretmen görüşü aynı şablonla açılır',
    (tester) async {
      await tester.runAsync(kaydet);
      await tester.pumpWidget(
        MaterialApp(home: BireyselBilgiToplamaScreen(service: ortakFormlar())),
      );
      await bekle(tester);
      expect(find.textContaining('Öğretmen görüşü • Taslak'), findsOneWidget);
      await tester.runAsync(
        () => tester.tap(find.text('9-1 • Sınıf toplantısı')),
      );
      await bekle(tester);
      expect(find.byType(OgretmenGorusFormScreen), findsOneWidget);
      expect(find.text('Mesaj at'), findsOneWidget);
      expect(find.textContaining('Fotoğraflı forma'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('yeni form öğretmen görüşü şablonu toplantıyı seçerek açılır', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BireyselBilgiToplamaScreen(service: ortakFormlar())),
    );
    await bekle(tester);
    await tester.tap(find.text('Yeni form'));
    await tester.pumpAndSettle();
    expect(find.text('Öğrenci ve veli bilgileri'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.text('Fotoğraflı öğretmen görüşü')),
    );
    await bekle(tester);
    expect(find.text('Toplantıyı seç'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.text('9-1 • Sınıf toplantısı')),
    );
    await bekle(tester);
    expect(find.byType(OgretmenGorusFormScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yayımlama başarısızsa kayıt korunur ve mesajlaşma açılmaz', (
    tester,
  ) async {
    await tester.runAsync(kaydet);
    var yayinCagri = 0;
    final google = OgretmenGorusGoogleService(
      client: MockClient((r) async {
        yayinCagri++;
        expect(
          (jsonDecode(r.body) as Map)['function'],
          'okulOgretmenGorusYayinla',
        );
        return http.Response(
          jsonEncode({
            'done': true,
            'error': {'message': 'hata'},
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OgretmenGorusFormScreen(
          service: s,
          formService: ortakFormlar(),
          baglam: b,
          atamaId: 1,
          toplantiId: toplanti,
          mesajService: ms,
          google: google,
          hesapBagla: () async => (token: 'token', hesap: 'test@okul.com'),
        ),
      ),
    );
    await bekle(tester);
    await tester.runAsync(() => tester.tap(find.text('Mesaj at')));
    await bekle(tester);
    expect(yayinCagri, 1);
    expect(find.byType(MesajlasmaScreen), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 1600));
    await bekle(tester);
    expect(find.textContaining('İşlem tamamlanamadı'), findsOneWidget);
    expect(
      (await tester.runAsync(
        () => s.ogretmenGorusDurumu(b, 1, toplanti),
      ))!['form'],
      isNotNull,
    );
    expect(acilan, isEmpty);
  });

  testWidgets(
    'fotoğraflı form hazırlanır, yalnız ders öğretmeniyle mesaj ön izlemesine geçilir',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var olustur = 0, yayinla = 0;
      final google = OgretmenGorusGoogleService(
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map;
          final islev = body['function'];
          Map<String, dynamic> result;
          if (islev == 'okulOgretmenGorusKurulumKontrol') {
            result = {
              'protocol': 'okul-ogretmen-gorus/v1',
              'ready': true,
              'version': 1,
            };
          } else if (islev == 'okulOgretmenGorusFormOlustur') {
            olustur++;
            final g = (body['parameters'] as List).single as Map;
            expect((g['ogrenciler'] as List).length, 1);
            expect(jsonEncode(g), isNot(contains('ÖZEL VELİ')));
            result = sonuc('${g['requestId']}');
          } else {
            expect(islev, 'okulOgretmenGorusYayinla');
            yayinla++;
            result = sonuc(
              '${(body['parameters'] as List).first}',
              yayin: true,
            );
          }
          return http.Response(
            jsonEncode({
              'done': true,
              'response': {'result': result},
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OgretmenGorusFormScreen(
            service: s,
            baglam: b,
            atamaId: 1,
            toplantiId: toplanti,
            mesajService: ms,
            google: google,
            hesapBagla: () async => (token: 'token', hesap: 'test@okul.com'),
          ),
        ),
      );
      await bekle(tester);
      expect(find.text('Öğretmen listesi (1/1 seçili)'), findsOneWidget);
      expect(find.textContaining('Ders öğretmeni 2'), findsNothing);
      final metin = find.byKey(const ValueKey('ogretmen-gorus-mesaj'));
      await tester.scrollUntilVisible(
        metin,
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
      );
      await tester.enterText(metin, 'Özel öğretmen mesajı\n{FormBaglantisi}');
      await tester.runAsync(() => tester.tap(find.text('Mesaj at')));
      await bekle(tester);
      await bekle(tester);
      expect(olustur, 1);
      expect(find.text('Öğretmenlere gönder'), findsNothing);

      await bekle(tester);
      expect(yayinla, 1);
      expect(find.byType(MesajlasmaScreen), findsOneWidget);
      final akis = tester.widget<MesajlasmaScreen>(
        find.byType(MesajlasmaScreen),
      );
      expect(akis.gonderimOnizlemesiniAc, true);
      expect(akis.yalnizGonderimOnayi, true);
      expect(akis.takipPenceresi, true);
      expect(find.text('Yeni Mesaj'), findsNothing);
      expect(find.text('Gönderim Geçmişi'), findsNothing);
      expect(find.text('Ön İzle ve Onayla'), findsNothing);
      expect(find.text('Mesajı gönder'), findsOneWidget);
      expect(akis.baslangicMetni, startsWith('Özel öğretmen mesajı'));
      expect(akis.baslangicMetni, isNot(contains('{FormBaglantisi}')));
      expect(
        find.textContaining(
          'https://docs.google.com/forms/d/e/form_1/viewform',
        ),
        findsWidgets,
      );
      expect(find.textContaining('Ders öğretmeni 2'), findsNothing);
      expect(acilan, isEmpty); // Ön izleme gönderim yapmaz.
      await tester.tap(find.text('WhatsApp ile gönder'));
      await bekle(tester);
      expect(acilan, hasLength(1));
      expect(acilan.single, startsWith('905321112231|'));
      expect(
        acilan.single,
        contains('https://docs.google.com/forms/d/e/form_1/viewform'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'telefon ön izlemesi eksikleri ayırır ve tekrar numarayı birleştirir',
    () {
      MesajKisi kisi(String id, String tel) => MesajKisi(
        tur: MesajKisiTuru.ogretmen,
        kisiId: id,
        sinifId: 1,
        ad: id,
        telefon: tel,
        aciklama: '9-1',
      );
      final p = MesajKisiOnIzleme([
        kisi('1', '05321112233'),
        kisi('2', '+90 532 111 22 33'),
        kisi('3', ''),
        kisi('4', 'yanlış'),
      ]);
      expect(p.telefonGruplari.length, 1);
      expect(p.gecersizler.length, 2);
      expect(MesajKisiOnIzleme([kisi('1', '')]).telefonGruplari, isEmpty);
    },
  );
  testWidgets('tümünü kaldır uyarır; Google hatası mesajlaşmayı engeller', (
    tester,
  ) async {
    var googleCagri = 0;
    final google = OgretmenGorusGoogleService(
      client: MockClient((r) async {
        googleCagri++;
        return http.Response(
          jsonEncode({
            'done': true,
            'error': {'message': 'hata'},
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OgretmenGorusFormScreen(
          service: s,
          baglam: b,
          atamaId: 1,
          toplantiId: toplanti,
          mesajService: ms,
          google: google,
          hesapBagla: () async => (token: 'token', hesap: 'test@okul.com'),
        ),
      ),
    );
    await bekle(tester);
    await tester.tap(find.text('Öğretmen listesi (1/1 seçili)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Seçimi kaldır'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seçimi kaldır'));
    await tester.pump();
    await tester.tap(find.text('Mesaj at'));
    await bekle(tester);
    expect(find.text('Lütfen en az bir öğretmen seçin.'), findsOneWidget);
    expect(googleCagri, 0);
    expect(find.byType(MesajlasmaScreen), findsNothing);
    await tester.ensureVisible(find.text('Görünenleri seç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Görünenleri seç'));
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('Mesaj at')));
    await bekle(tester);
    expect(find.byType(MesajlasmaScreen), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 1600));
    await bekle(tester);
    expect(find.textContaining('İşlem tamamlanamadı'), findsOneWidget);
    expect(googleCagri, greaterThan(0));
    expect(acilan, isEmpty);
  });
  testWidgets(
    'üç sekmenin işlemleri ve ön izleme dar ekranda sabit alt çubuktadır',
    (tester) async {
      await tester.runAsync(kaydet);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: w!,
          ),
          home: OgretmenGorusFormScreen(
            service: s,
            baglam: b,
            atamaId: 1,
            toplantiId: toplanti,
            mesajService: ms,
          ),
        ),
      );
      await bekle(tester);
      final bar = find.byKey(const ValueKey('gorus-alt-islemler'));
      final preview = find.byKey(const ValueKey('gorus-form-onizleme'));
      final rect = tester.getRect(bar);
      expect(find.descendant(of: bar, matching: preview), findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.text('Mesaj at')),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byType(ListView).first).bottom,
        lessThanOrEqualTo(rect.top),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(bar), rect);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1600));
      await tester.pumpAndSettle();
      for (final tab in ['Yanıtlar', 'Değerlendirme']) {
        await tester.ensureVisible(find.widgetWithText(Tab, tab));
        await tester.tap(find.widgetWithText(Tab, tab));
        await tester.pumpAndSettle();
        expect(find.descendant(of: bar, matching: preview), findsOneWidget);
        expect(tester.getRect(bar), rect);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Form işlemleri'));
      await tester.pumpAndSettle();
      expect(find.text('Yanıt alımını kapat'), findsOneWidget);
      expect(find.text('Tamamlandı olarak işaretle'), findsOneWidget);
      expect(acilan, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('geçmiş formda gönderme yok; büyük yazıda taşma yok', (
    tester,
  ) async {
    await tester.runAsync(kaydet);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: w!,
        ),
        home: OgretmenGorusFormScreen(
          service: s,
          baglam: b,
          atamaId: 1,
          toplantiId: toplanti,
          saltOkunur: true,
        ),
      ),
    );
    await bekle(tester);
    expect(find.text('Öğretmenlere gönder'), findsNothing);
    expect(find.byTooltip('Form işlemleri'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'hatırlatma ad eşleştirmesi Türkçe harf, boşluk ve tekrar yanıtları korur',
    () {
      MesajKisi ogretmen(String id, String ad) => MesajKisi(
        tur: MesajKisiTuru.ogretmen,
        kisiId: id,
        sinifId: 1,
        ad: ad,
        telefon: '05321112231',
        aciklama: '9-1 • Matematik',
      );
      final ids = BilgiToplamaOgretmenGorusService.yanitlayanOgretmenIdleri(
        [
          ogretmen('1', 'IŞIK İPEK'),
          ogretmen('2', 'Ayşe Demir'),
          ogretmen('3', 'Ali Kaya'),
        ],
        [
          {'ogretmen': '  ışık   ipek '},
          {'ogretmen': 'Ayşe Demir'},
          {'ogretmen': 'Ayşe Demir'},
          {'ogretmen': ''},
          {'ogretmen': 'Bilinmeyen kişi'},
        ],
      );
      expect(ids, {'1', '2'});
    },
  );

  for (final senaryo in ['tum-yanit', 'okuma-hatasi', 'bir-yanit']) {
    testWidgets('Hatırlat yalnız güncel yanıtsızlara gider: $senaryo', (
      t,
    ) async {
      final mb = await t.runAsync(ms.hazirla);
      await t.runAsync(
        () => ms.ogretmenIletisimKaydet(
          mb!,
          ad: 'Diğer öğretmen',
          telefon: '05321112239',
          sinifIdleri: {1},
          sinifIliskileriniDogruladim: true,
        ),
      );
      await t.runAsync(kaydet);
      var okumalar = 0;
      final google = OgretmenGorusGoogleService(
        client: MockClient((req) async {
          final body = jsonDecode(req.body) as Map;
          final fonksiyon = body['function'];
          Map<String, dynamic> result;
          if (fonksiyon == 'okulOgretmenGorusYayinla') {
            result = sonuc('a' * 32, yayin: true);
          } else {
            expect(fonksiyon, 'okulOgretmenGorusYanitlari');
            okumalar++;
            if (senaryo == 'okuma-hatasi') {
              return http.Response('Erisim yok', 503);
            }
            result = {
              'protocol': 'okul-ogretmen-gorus/v1',
              'requestId': 'a' * 32,
              'formId': 'form_1',
              'nextOffset': null,
              'yanitlar': [
                {
                  'responseId': 'r1',
                  'tarih': '2026-10-31T12:00:00',
                  'ogretmen': 'Ders öğretmeni 1',
                  'ders': 'Matematik',
                  'sinifGorusu': 'Sınıf görüşü',
                  'ogrenciler': <String, dynamic>{},
                },
                if (senaryo == 'tum-yanit')
                  {
                    'responseId': 'r2',
                    'tarih': '2026-10-31T12:01:00',
                    'ogretmen': 'Diğer öğretmen',
                    'ders': 'Matematik',
                    'sinifGorusu': 'Diğer görüş',
                    'ogrenciler': <String, dynamic>{},
                  },
              ],
            };
          }
          return http.Response(
            jsonEncode({
              'done': true,
              'response': {'result': result},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: OgretmenGorusFormScreen(
            service: s,
            baglam: b,
            atamaId: 1,
            toplantiId: toplanti,
            mesajService: ms,
            formService: ortakFormlar(),
            google: google,
            hesapBagla: () async => (token: 'token', hesap: 'test@okul.com'),
          ),
        ),
      );
      await bekle(t);
      await t.runAsync(() => t.tap(find.text('Hatırlat')));
      await bekle(t);
      await bekle(t);
      expect(okumalar, greaterThan(0));
      expect(acilan, isEmpty);
      if (senaryo == 'tum-yanit') {
        expect(find.byType(MesajlasmaScreen), findsNothing);
        expect(
          find.textContaining('Hatırlatma gönderilecek öğretmen yok'),
          findsOneWidget,
        );
      } else if (senaryo == 'okuma-hatasi') {
        expect(find.byType(MesajlasmaScreen), findsNothing);
        expect(
          find.textContaining('Google bağlantısı başarısız'),
          findsOneWidget,
        );
      } else {
        expect(
          find.byType(MesajlasmaScreen),
          findsOneWidget,
          reason: t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '),
        );
        final akis = t.widget<MesajlasmaScreen>(find.byType(MesajlasmaScreen));
        final adaylar = await t.runAsync(
          () => ms.aliciAdaylari(mb!, tur: MesajKisiTuru.ogretmen, sinifId: 1),
        );
        final yanitsiz = adaylar!.singleWhere((k) => k.ad == 'Diğer öğretmen');
        expect(akis.baslangicOgretmenIdleri, {yanitsiz.kisiId});
        expect(akis.baslangicMetni, startsWith('Hatırlatma: '));
        await t.runAsync(() => t.tap(find.text('WhatsApp ile gönder')));
        await bekle(t);
        await bekle(t);
        expect(acilan, hasLength(1));
        expect(acilan.single, startsWith('905321112239|Hatırlatma: '));
      }
      final scherm = find.byType(MesajlasmaScreen);
      if (scherm.evaluate().isNotEmpty) {
        await t.runAsync(() async {
          Navigator.of(t.element(scherm)).pop();
        });
        await bekle(t);
        await bekle(t);
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
