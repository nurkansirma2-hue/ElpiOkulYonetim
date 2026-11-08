import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/screens/rapor_olustur_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bilgi_toplama_service.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_google_form_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselBilgiToplamaService service;
  late BilgiToplamaOturumu b;
  late int formId;
  late Map<String, String> ids;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;
  Future<void> ogrenci(int id, String no, int sinif) async {
    await db.insert('Ogrenci', {
      'OgrenciId': id,
      'OkulNo': no,
      'Ad': 'Ad$id',
      'Soyad': 'Soyad',
      'Telefon': '05321112233',
      'AnneAdi': 'Eski Anne',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': id,
      'SinifSubeId': sinif,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
  }

  List<BilgiToplamaSorusu> sorular() => [
    BilgiToplamaSorusu(
      anahtar: 'anne',
      baslik: 'Anne adı',
      hedefAlan: 'AnneAdi',
    ),
    BilgiToplamaSorusu(
      anahtar: 'baba',
      baslik: 'Baba adı',
      hedefAlan: 'BabaAdi',
    ),
    BilgiToplamaSorusu(
      anahtar: 'anneTel',
      baslik: 'Anne telefon',
      veriTuru: 'Telefon',
      hedefAlan: 'AnneTelefon',
    ),
    BilgiToplamaSorusu(
      anahtar: 'babaTel',
      baslik: 'Baba telefon',
      veriTuru: 'Telefon',
      hedefAlan: 'BabaTelefon',
    ),
    BilgiToplamaSorusu(
      anahtar: 'telefon',
      baslik: 'Öğrenci telefon',
      veriTuru: 'Telefon',
      hedefAlan: 'Telefon',
    ),
    BilgiToplamaSorusu(anahtar: 'beklenti', baslik: 'Beklenti'),
  ];
  Map<String, dynamic> yanit({
    String id = 'r1',
    String no = '001',
    String ad = 'Ad1 Soyad',
    String sinif = '9/A',
    Map<String, String> ek = const {},
  }) {
    final degerler = {
      'okulNo': no,
      'adSoyad': ad,
      'sinif': sinif,
      'anne': 'Yeni Anne',
      'telefon': '05329998877',
      'beklenti': 'Daha çok etkinlik',
      ...ek,
    };
    return {
      'responseId': id,
      'lastSubmittedTime': '2026-10-22T10:00:00Z',
      'answers': {
        for (final e in degerler.entries)
          ids[e.key]: {
            'textAnswers': {
              'answers': [
                {'value': e.value},
              ],
            },
          },
      },
    };
  }

  Future<int> al(Map<String, dynamic> r) async =>
      (await service.yanitlariKaydet(b, formId, [r])).single;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'calisma_modu': CalismaModu.bireyselOgretmen.kayitDegeri,
    });
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    mod = CalismaModu.bireyselOgretmen;
    service = BireyselBilgiToplamaService(
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
      'OgretmenProfilId': 1,
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    for (final s in [1, 2]) {
      await db.insert('SinifSube', {
        'SinifSubeId': s,
        'SinifKodu': s == 1 ? '9/A' : '9/B',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
    }
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'Gun': 'Pazartesi',
      'DersSaatiId': 1,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await ogrenci(1, '001', 1);
    await ogrenci(2, '002', 1);
    await ogrenci(3, '003', 2);
    b = await service.hazirla();
    formId = await service.formOlustur(
      b,
      baslik: 'Veli bilgileri',
      sorular: sorular(),
      hedefTuru: 'OgrenciSec',
      ogrenciIdleri: {1, 2},
    );
    ids = {
      for (final s in await service.sorular(b, formId))
        s['AlanAnahtari'] as String: 'q${s['Id']}',
    };
    await service.googleBagla(b, formId, 'google-form', ids);
  });
  tearDown(() async => LocalDatabase.instance.close());

  test(
    'aynı taslak isteği ikinci kayıt oluşturmaz farklı içerik sessizce yazılmaz',
    () async {
      Future<int> olustur(String baslik) => service.formOlustur(
        b,
        baslik: baslik,
        sorular: sorular(),
        hedefTuru: 'OgrenciSec',
        ogrenciIdleri: {1},
        istekKimligi: 'a' * 32,
      );
      final bir = await olustur('Tek taslak');
      expect(await olustur('Tek taslak'), bir);
      await expectLater(olustur('Değişen içerik'), throwsStateError);
      expect(
        (await service.formlar(b)).where((f) => f['Baslik'] == 'Tek taslak'),
        hasLength(1),
      );
    },
  );

  test('yanıt alımı kapalıyken mevcut yanıt kontrollü onaylanabilir', () async {
    final id = await al(yanit());
    await service.yayinDurumuKaydet(b, formId, 'google-form', false);
    final p = await service.onizle(b, id);
    expect(p.kaydedilebilir, true);
    await service.onayla(b, p);
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneAdi'],
      'Yeni Anne',
    );
    expect((await service.formGetir(b, formId))['Durum'], 'Kapali');
  });

  test('form yönetimi kapatma tamamlama ve arşivi silmeden ayırır', () async {
    await expectLater(service.isaretle(b, formId, 'Arşivle'), throwsStateError);
    await service.yayinDurumuKaydet(b, formId, 'google-form', false);
    await service.isaretle(b, formId, 'Tamamla');
    expect((await service.formOzeti(b, formId))['durum'], 'Tamamlandı');
    await service.isaretle(b, formId, 'Arşivle');
    expect((await service.formOzeti(b, formId))['durum'], 'Arşiv');
    expect(await service.formlar(b), hasLength(1));
    await service.yayinDurumuKaydet(b, formId, 'google-form', true);
    final o = await service.formOzeti(b, formId);
    expect(o['durum'], 'Yanıt bekleniyor');
    expect(o['yayinAcik'], true);
    await expectLater(
      service.yayinDurumuKaydet(b, formId, 'baska-form', false),
      throwsStateError,
    );
  });

  test(
    'aynı kişinin tekrarları sayıyı şişirmez belirsiz kimlik sayılmaz',
    () async {
      await al(yanit());
      await al(yanit(id: 'tekrar'));
      await al(yanit(id: 'belirsiz', ad: 'Başka biri'));
      final o = await service.formOzeti(b, formId);
      expect(o['yanitSayisi'], 3);
      expect(o['yanitlayan'], 1);
      expect(o['beklenen'], 2);
      expect(o['eslesmeyen'], 1);
      expect(o['sonYanit'], '2026-10-22T10:00:00Z');
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneAdi'],
        'Eski Anne',
      );
    },
  );

  test('seçili yanıt silme planı sadece seçileni içerir', () async {
    final bir = await al(yanit());
    await al(yanit(id: 'r2'));
    final plan = await service.topluSilmePlani(
      b,
      formId,
      sadeceKaydedilenler: false,
      seciliYanitIdleri: {bir},
    );
    expect(plan.googleYanitIdleri, ['r1']);
    await service.topluSilmeYanitiSil(
      b,
      plan,
      'r1',
      googleSil: (fid, rid) async {
        expect(fid, 'google-form');
        expect(rid, 'r1');
      },
    );
    expect((await service.yanitlar(b, formId)).map((y) => y['GoogleYanitId']), [
      'r2',
    ]);
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneAdi'],
      'Eski Anne',
    );
  });

  Future<void> veliFormu() async {
    formId = await service.formOlustur(
      b,
      baslik: 'Veli seçimi',
      sorular: [...sorular(), ...BireyselBilgiToplamaService.veliSorulari],
    );
    ids = {
      for (final q in await service.sorular(b, formId))
        q['AlanAnahtari'] as String: 'v${q['Id']}',
    };
    await service.googleBagla(b, formId, 'veli-secim-formu', ids);
  }

  for (final secim in ['Annem', 'Babam']) {
    test('$secim seçimi onayla güncellenir; telefon kopyalanmaz', () async {
      await veliFormu();
      await db.update('Ogrenci', {
        'VeliTuru': 'Diger',
        'VeliAdi': 'Eski veli',
        'VeliTelefonu': '05320000000',
      }, where: 'OgrenciId=1');
      final id = await al(
        yanit(
          ek: {
            'veliSecimi': secim,
            'anneTel': '05321112233',
            'babaTel': '05324445566',
            'digerVeliAdi': 'Yanlışlıkla yazılmış',
            'digerVeliTelefonu': 'hatalı',
          },
        ),
      );
      final p = await service.onizle(b, id);
      expect(p.kaydedilebilir, true);
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['VeliTuru'],
        'Diger',
      );
      expect(p.degisiklikler.keys, isNot(contains('VeliTelefonu')));
      await service.onayla(b, p);
      final detay = await BireyselListeService.ogrenciBilgileri(
        await BireyselListeService.hazirla(),
        1,
      );
      expect(detay['VeliTuru'], secim == 'Annem' ? 'Anne' : 'Baba');
      expect(
        detay['VeliTelefonu'],
        secim == 'Annem' ? '05321112233' : '05324445566',
      );
      final kayit = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
      expect(
        kayit['VeliTelefonu'],
        '05320000000',
      ); // Diğer kişinin kaydı korunur.
      expect((await db.query('OgrenciEkBilgiDeger')).map((e) => e['Deger']), [
        'Daha çok etkinlik',
      ]);
    });
  }
  test(
    'diğer veli kimliği ve yakınlığı onayda kaydedilir; anne baba korunur',
    () async {
      await veliFormu();
      final id = await al(
        yanit(
          ek: {
            'veliSecimi': 'Diğer',
            'digerVeliAdi': 'Ayşe Veli',
            'digerVeliYakinlik': 'Teyzesi',
            'digerVeliTelefonu': '05325556677',
          },
        ),
      );
      final p = await service.onizle(b, id);
      expect(p.kaydedilebilir, true);
      await service.onayla(b, p);
      final o = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
      expect(o['VeliTuru'], 'Diger');
      expect(o['VeliAdi'], 'Ayşe Veli');
      expect(o['VeliTelefonu'], '05325556677');
      expect(o['AnneAdi'], 'Yeni Anne');
      expect(
        (await db.query('OgrenciEkBilgiDeger')).map((e) => e['Deger']),
        contains('Teyzesi'),
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'veli seçimi eksik veya diğer veli eksikse onay engellenir; düzeltilebilir',
    () async {
      await veliFormu();
      final bos = await al(yanit());
      expect((await service.onizle(b, bos)).kaydedilebilir, false);
      final eksik = await al(yanit(id: 'eksik', ek: {'veliSecimi': 'Diğer'}));
      final p = await service.onizle(b, eksik);
      expect(p.hatalar.join(), contains('yakınlık'));
      await expectLater(service.onayla(b, p), throwsStateError);
      final cevaplar = await service.duzenlenecekCevaplar(b, p);
      await expectLater(
        service.yanitiDuzenle(b, p, cevaplar),
        throwsFormatException,
      );
      final yeni = await service.yanitiDuzenle(b, p, {
        ...cevaplar,
        'digerVeliAdi': 'Veli',
        'digerVeliYakinlik': 'Amcası',
        'digerVeliTelefonu': '05325556677',
      });
      await service.onayla(
        b,
        await service.onizle(b, yeni),
        uyarilariKabulEt: true,
      );
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['VeliTuru'],
        'Diger',
      );
    },
  );
  test('veli soruları kısmi veya farklı seçeneklerle oluşturulamaz', () async {
    await expectLater(
      service.formOlustur(
        b,
        baslik: 'Eksik veli',
        sorular: [BireyselBilgiToplamaService.veliSorulari.first],
      ),
      throwsFormatException,
    );
  });

  test(
    'ön izleme ana kaydı değiştirmez; beş hazır alan ve ek yanıt atomik kaydedilir',
    () async {
      final id = await al(
        yanit(
          ek: {
            'baba': 'Baba',
            'anneTel': '05321112233',
            'babaTel': '05324445566',
          },
        ),
      );
      var o = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
      expect(o['AnneAdi'], 'Eski Anne');
      final p = await service.onizle(b, id);
      expect(p.kaydedilebilir, isTrue);
      expect(p.uyarilar, isEmpty);
      expect(p.degisiklikler['Telefon']!['eski'], '05321112233');
      await service.onayla(b, p);
      o = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
      expect(o['Telefon'], '05329998877');
      expect(o['AnneAdi'], 'Yeni Anne');
      expect(o['BabaAdi'], 'Baba');
      expect(o['AnneTelefon'], '05321112233');
      expect(o['BabaTelefon'], '05324445566');
      expect(o['VeliAdi'], isNull);
      expect(o['VeliTelefonu'], isNull);
      final detay = await BireyselListeService.ogrenciBilgileri(
        await BireyselListeService.hazirla(),
        1,
      );
      expect(detay['VeliAdi'], 'Yeni Anne');
      expect(detay['VeliTelefonu'], '05321112233');
      expect(o['Ad'], 'Ad1');
      expect(o['Soyad'], 'Soyad');
      expect(o['OkulNo'], '001');
      expect(
        (await db.query(
          'SinifSube',
          where: 'SinifSubeId=1',
        )).single['SinifKodu'],
        '9/A',
      );
      expect(
        (await db.query('OgrenciEkBilgiDeger')).single['Deger'],
        'Daha çok etkinlik',
      );
      await expectLater(service.onayla(b, p), throwsStateError);
    },
  );
  test(
    'veli anne kaydından okunur; farklı veli ve kapsam dışı korunur',
    () async {
      final id = await al(yanit(ek: {'anneTel': '05321112233'}));
      await service.onayla(b, await service.onizle(b, id));
      await db.update('Ogrenci', {
        'VeliAdi': '',
        'VeliTelefonu': '',
      }, where: 'OgrenciId=1');
      await db.update('Ogrenci', {
        'AnneTelefon': '05324445566',
      }, where: 'OgrenciId=2');
      await service.hazirla();
      var o = await BireyselListeService.ogrenciBilgileri(
        await BireyselListeService.hazirla(),
        1,
      );
      expect(o['VeliTelefonu'], '05321112233');
      expect(
        (await db.query(
          'Ogrenci',
          where: 'OgrenciId=1',
        )).single['VeliTelefonu'],
        '',
      );
      await db.update('Ogrenci', {
        'VeliAdi': 'Başka veli',
        'VeliTelefonu': '05325556677',
      }, where: 'OgrenciId=1');
      await service.hazirla();
      o = await BireyselListeService.ogrenciBilgileri(
        await BireyselListeService.hazirla(),
        1,
      );
      expect(o['VeliTelefonu'], '05325556677');
      expect(o['VeliAdi'], 'Başka veli');
    },
  );
  test(
    'öğrenci detayında yalnız onaylı son ek cevaplar görünür ve silmeden sonra korunur',
    () async {
      final id = await al(yanit(ek: {'anneTel': '05321112233'}));
      final oturum = await BireyselListeService.hazirla();
      expect(
        (await BireyselListeService.ogrenciBilgileri(oturum, 1))['EkBilgiler'],
        isEmpty,
      );
      await service.onayla(b, await service.onizle(b, id));
      final ikinci = await al(yanit(id: 'r2', ek: {'beklenti': 'Son değer'}));
      await service.onayla(
        b,
        await service.onizle(b, ikinci),
        uyarilariKabulEt: true,
      );
      await service.yanitiSil(b, await service.onizle(b, ikinci));
      final o = await BireyselListeService.ogrenciBilgileri(oturum, 1);
      expect((o['EkBilgiler'] as List).single['Deger'], 'Son değer');
      expect(o['AnneTelefon'], '05321112233');
      await expectLater(
        BireyselListeService.ogrenciBilgileri(oturum, 3),
        throwsStateError,
      );
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
      await expectLater(
        BireyselListeService.ogrenciBilgileri(oturum, 1),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'öğrenci listesine dokununca iletişim ve onaylı form bilgileri açılır',
    (t) async {
      t.view.physicalSize = const Size(320, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final id = await al(
        yanit(ek: {'anneTel': '05321112233', 'babaTel': '05324445566'}),
      );
      await service.onayla(b, await service.onizle(b, id));
      const ekran = ValueKey('ogrenci-detay-gorunumu');
      final gorsel = Platform.environment['OGRENCI_GORSEL_KONTROL'] == 'true';
      if (gorsel) {
        final font = FontLoader('TestNoto')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      }
      await t.pumpWidget(
        RepaintBoundary(
          key: ekran,
          child: MaterialApp(
            theme: gorsel ? ThemeData(fontFamily: 'TestNoto') : null,
            home: const RaporOlusturScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Ad1 Soyad'));
      await t.pumpAndSettle();
      expect(find.text('Öğrenci bilgileri'), findsOneWidget);
      expect(find.text('Veli adı'), findsNothing);
      expect(find.text('Veli telefonu'), findsNothing);
      expect(find.text('05321112233'), findsOneWidget);
      expect(find.text('Veli'), findsOneWidget);
      if (Platform.environment['OGRENCI_GORSEL_KONTROL'] == 'true') {
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(ekran),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/ogrenci-detay-gorunumu.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.tap(find.byKey(const ValueKey('kisi-Anne')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('iletisim-AnneTelefon')),
        'abc',
      );
      await t.tap(find.text('Kaydet').last);
      await t.pumpAndSettle();
      expect(find.text('Geçerli tek telefon numarası girin.'), findsOneWidget);
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneTelefon'],
        '05321112233',
      );
      await t.enterText(
        find.byKey(const ValueKey('iletisim-AnneAdi')),
        'Son Anne',
      );
      await t.enterText(
        find.byKey(const ValueKey('iletisim-AnneTelefon')),
        '05321110000',
      );
      await t.tap(find.text('Kaydet').last);
      await t.pumpAndSettle();
      expect(find.text('Son Anne'), findsOneWidget);
      expect(find.text('05321110000'), findsOneWidget);
      expect(
        (await BireyselListeService.ogrenciBilgileri(
          await BireyselListeService.hazirla(),
          1,
        ))['VeliTelefonu'],
        '05321110000',
      );
      await t.scrollUntilVisible(
        find.text('Veli ilişkisini değiştir'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Veli ilişkisini değiştir'));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButton<String>).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Baba').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Kaydet').last);
      await t.pumpAndSettle();
      final kayit = (await db.query('Ogrenci', where: 'OgrenciId=1')).single;
      expect(kayit['VeliTuru'], 'Baba');
      expect(kayit['VeliTelefonu'], isNull);
      expect(
        (await BireyselListeService.ogrenciBilgileri(
          await BireyselListeService.hazirla(),
          1,
        ))['VeliTelefonu'],
        '05324445566',
      );
      await t.scrollUntilVisible(
        find.text('Daha çok etkinlik'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Daha çok etkinlik'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  test('iletişim düzenleme kapsamı, telefon ve eski veri denetlenir', () async {
    final oturum = await BireyselListeService.hazirla();
    final o = await BireyselListeService.ogrenciBilgileri(oturum, 1);
    await expectLater(
      BireyselListeService.iletisimKaydet(oturum, 1, 'Anne', {
        'AnneAdi': 'A',
        'AnneTelefon': 'abc',
      }, onceki: o),
      throwsFormatException,
    );
    await expectLater(
      BireyselListeService.iletisimKaydet(oturum, 1, 'Ogrenci', {
        'Ad': 'Değişmesin',
      }, onceki: o),
      throwsFormatException,
    );
    await expectLater(
      BireyselListeService.iletisimKaydet(oturum, 3, 'Ogrenci', {
        'Telefon': '',
      }, onceki: o),
      throwsStateError,
    );
    await BireyselListeService.iletisimKaydet(oturum, 1, 'Anne', {
      'AnneAdi': 'A',
      'AnneTelefon': '05321110000',
    }, onceki: o);
    await expectLater(
      BireyselListeService.iletisimKaydet(oturum, 1, 'Anne', {
        'AnneAdi': 'Eski',
        'AnneTelefon': '',
      }, onceki: o),
      throwsStateError,
    );
    final yeni = await BireyselListeService.ogrenciBilgileri(oturum, 1);
    await BireyselListeService.iletisimKaydet(oturum, 1, 'Anne', {
      'AnneAdi': 'A',
      'AnneTelefon': '',
    }, onceki: yeni);
    expect(
      (await BireyselListeService.ogrenciBilgileri(oturum, 1))['VeliTelefonu'],
      '',
    );
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=1')).single['VeliTelefonu'],
      isNull,
    );
  });
  test('boş cevap mevcut bilgileri silmez', () async {
    final id = await al(yanit(ek: {'anne': '', 'telefon': '', 'beklenti': ''}));
    await service.onayla(b, await service.onizle(b, id));
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=1')).single['Telefon'],
      '05321112233',
    );
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneAdi'],
      'Eski Anne',
    );
    expect(await db.query('OgrenciEkBilgiDeger'), isEmpty);
  });
  test(
    'yanlış no ad/sınıftan eşleştirilmez; elle düzeltme özgün cevabı korur',
    () async {
      final id = await al(yanit(no: '999'));
      final p = await service.onizle(b, id);
      expect(p.ogrenci, isNull);
      await expectLater(service.onayla(b, p), throwsStateError);
      await service.eslemeyiDuzelt(
        b,
        p,
        ogrenciId: 1,
        aciklama: 'Numara yanlış yazılmış',
      );
      final yeni = await service.onizle(b, id);
      expect(yeni.girilen['okulNo'], '999');
      expect(yeni.ogrenci!['OkulNo'], '001');
      await expectLater(service.onayla(b, yeni), throwsStateError);
      await service.onayla(b, yeni, uyarilariKabulEt: true);
      expect(
        (await db.query('BilgiToplamaYanit')).single['GirilenOkulNo'],
        '999',
      );
      expect((await db.query('BilgiToplamaEsleme')).single['YeniOgrenciId'], 1);
    },
  );
  test('başka öğrenciye ait geçerli no kimlik uyarısı üretir', () async {
    final id = await al(yanit(no: '002'));
    final p = await service.onizle(b, id);
    expect(p.ogrenci!['OgrenciId'], 2);
    expect(p.uyarilar, isNotEmpty);
    await expectLater(service.onayla(b, p), throwsStateError);
    await service.eslemeyiDuzelt(
      b,
      p,
      ogrenciId: 1,
      aciklama: 'Kimlik kontrolü',
    );
    await service.onayla(
      b,
      await service.onizle(b, id),
      uyarilariKabulEt: true,
    );
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=2')).single['AnneAdi'],
      'Eski Anne',
    );
  });
  test('baştaki sıfır korunur; 1 numarası 001 olarak varsayılmaz', () async {
    final id = await al(yanit(no: '1'));
    expect((await service.onizle(b, id)).ogrenci, isNull);
  });
  test(
    'tekrar alma aynı kaydı döndürür; değişen yanıt ayrı kontrol ister',
    () async {
      final r = yanit();
      final id = await al(r);
      expect(await al(r), id);
      expect(await db.query('BilgiToplamaYanit'), hasLength(1));
      await service.onayla(b, await service.onizle(b, id));
      final ikinci = await al(yanit(ek: {'anne': 'Son Anne'}));
      expect(ikinci, isNot(id));
      final p = await service.onizle(b, ikinci);
      expect(p.uyarilar, isNotEmpty);
      expect(p.serbestOncekiDegerler.values, contains('Daha çok etkinlik'));
      await expectLater(service.onayla(b, p), throwsStateError);
      await service.onayla(b, p, uyarilariKabulEt: true);
      expect(await db.query('OgrenciEkBilgiDeger'), hasLength(2));
    },
  );
  test('hedef dışı ve ders kapsamı dışı erişim engellenir', () async {
    await expectLater(
      service.formOlustur(
        b,
        baslik: 'X',
        sorular: sorular(),
        hedefTuru: 'OgrenciSec',
        ogrenciIdleri: {3},
      ),
      throwsStateError,
    );
    await expectLater(
      service.formOlustur(
        b,
        baslik: 'X',
        sorular: sorular(),
        hedefTuru: 'TumOkul',
      ),
      throwsStateError,
    );
    await db.delete(
      'BilgiToplamaHedef',
      where: 'FormId=? AND OgrenciId=2',
      whereArgs: [formId],
    );
    final id = await al(yanit(no: '002'));
    final p = await service.onizle(b, id);
    expect(p.kaydedilebilir, isFalse);
    await expectLater(
      service.eslemeyiDuzelt(b, p, ogrenciId: 3, aciklama: 'X'),
      throwsStateError,
    );
  });
  test('kurumsal mod ve yıl değişimi engellenir', () async {
    final id = await al(yanit());
    final p = await service.onizle(b, id);
    mod = null;
    await expectLater(service.onayla(b, p), throwsStateError);
    mod = CalismaModu.bireyselOgretmen;
    await db.update('OkulProfil', {'EgitimYili': '2027-2028'});
    await expectLater(service.onayla(b, p), throwsStateError);
  });
  test(
    'başka profilin formu okunmaz; ders kalkınca eski ön izleme kullanılamaz',
    () async {
      final id = await al(yanit());
      final p = await service.onizle(b, id);
      await db.update('DersProgrami', {'Aktif': 0});
      await expectLater(service.onayla(b, p), throwsStateError);
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Diğer',
        'OkulAdi': 'Okul',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      final yeni = await service.hazirla();
      await expectLater(service.onizle(yeni, id), throwsStateError);
      await expectLater(service.yanitlar(yeni, formId), throwsStateError);
    },
  );
  test('eşleşen numara belirsizse otomatik öğrenci seçilmez', () async {
    await ogrenci(4, ' 001 ', 1);
    final id = await al(yanit());
    expect((await service.onizle(b, id)).ogrenci, isNull);
  });
  test(
    'ön izleme sonrası öğrenci, soru ve başka yanıt değişimi durdurulur',
    () async {
      final id = await al(yanit());
      final p = await service.onizle(b, id);
      await db.update('Ogrenci', {
        'Telefon': '05320000000',
      }, where: 'OgrenciId=1');
      await expectLater(service.onayla(b, p), throwsStateError);
      final p2 = await service.onizle(b, id);
      await al(yanit(id: 'r2'));
      await expectLater(service.onayla(b, p2), throwsStateError);
      await db.update(
        'BilgiToplamaSoru',
        {'Baslik': 'Başlık değişti'},
        where: 'AlanAnahtari=?',
        whereArgs: ['anne'],
      );
      expect((await service.onizle(b, id)).kaydedilebilir, isFalse);
    },
  );
  test('telefon ve zorunlu cevap hataları ana kayda yazılmaz', () async {
    final id = await al(yanit(ek: {'telefon': 'abc', 'adSoyad': ''}));
    final p = await service.onizle(b, id);
    expect(p.hatalar.length, greaterThanOrEqualTo(2));
    await expectLater(service.onayla(b, p), throwsStateError);
  });
  test(
    'transaction hata verirse öğrenci, onay ve ek değerler geri alınır',
    () async {
      final id = await al(yanit());
      final p = await service.onizle(b, id);
      await db.execute(
        "CREATE TRIGGER test_hata BEFORE INSERT ON OgrenciEkBilgiDeger BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(service.onayla(b, p), throwsA(anything));
      expect(
        (await db.query('Ogrenci', where: 'OgrenciId=1')).single['AnneAdi'],
        'Eski Anne',
      );
      expect((await db.query('BilgiToplamaYanit')).single['Durum'], 'Bekliyor');
      expect(await db.query('OgrenciEkBilgiDeger'), isEmpty);
    },
  );
  test('reddedilmiş yanıt kaydedilemez', () async {
    final id = await al(yanit());
    await service.reddet(b, await service.onizle(b, id));
    final p = await service.onizle(b, id);
    expect(p.kaydedilebilir, isFalse);
    await expectLater(service.onayla(b, p), throwsStateError);
  });
  test('sayı, tarih, evet/hayır ve seçenek değerleri doğrulanır', () async {
    final f = await service.formOlustur(
      b,
      baslik: 'Türler',
      sorular: [
        BilgiToplamaSorusu(anahtar: 'sayi', baslik: 'Sayı', veriTuru: 'Sayi'),
        BilgiToplamaSorusu(
          anahtar: 'tarih',
          baslik: 'Tarih',
          veriTuru: 'Tarih',
        ),
        BilgiToplamaSorusu(
          anahtar: 'evet',
          baslik: 'Evet?',
          veriTuru: 'EvetHayir',
        ),
        BilgiToplamaSorusu(
          anahtar: 'sec',
          baslik: 'Seç',
          veriTuru: 'Secenek',
          secenekler: ['A', 'B'],
        ),
      ],
      hedefTuru: 'SinifSec',
      sinifIdleri: {1},
    );
    final soruIds = {
      for (final s in await service.sorular(b, f))
        s['AlanAnahtari'] as String: 't${s['Id']}',
    };
    await service.googleBagla(b, f, 'turler', soruIds);
    Map<String, dynamic> r(String id, Map<String, String> values) => {
      'responseId': id,
      'answers': {
        for (final e in {
          'okulNo': '001',
          'adSoyad': 'Ad1 Soyad',
          'sinif': '9/A',
          ...values,
        }.entries)
          soruIds[e.key]: {
            'textAnswers': {
              'answers': [
                {'value': e.value},
              ],
            },
          },
      },
    };
    final hatali = (await service.yanitlariKaydet(b, f, [
      r('h', {
        'sayi': 'abc',
        'tarih': '2026-02-30',
        'evet': 'Belki',
        'sec': 'C',
      }),
    ])).single;
    expect((await service.onizle(b, hatali)).hatalar, hasLength(4));
    final iyi = (await service.yanitlariKaydet(b, f, [
      r('i', {
        'sayi': '12,5',
        'tarih': '2026-02-28',
        'evet': 'Hayır',
        'sec': 'A',
      }),
    ])).single;
    final p = await service.onizle(b, iyi);
    expect(p.hatalar, isEmpty);
    await service.onayla(b, p, uyarilariKabulEt: true);
    expect(await db.query('OgrenciEkBilgiDeger'), hasLength(4));
  });
  test('karışık hatalı aktarım transaction olarak geri alınır', () async {
    await expectLater(
      service.yanitlariKaydet(b, formId, [
        yanit(),
        {'responseId': ''},
      ]),
      throwsFormatException,
    );
    expect(await db.query('BilgiToplamaYanit'), isEmpty);
  });
  test('tanımsız cevap ve çoklu cevap sessizce atlanmaz', () async {
    final r = yanit();
    (r['answers'] as Map)['yabanci'] = {
      'textAnswers': {
        'answers': [
          {'value': 'X'},
        ],
      },
    };
    final id = await al(r);
    expect((await service.onizle(b, id)).kaydedilebilir, isFalse);
    final r2 = yanit(id: 'multi');
    r2['answers'][ids['anne']] = {
      'textAnswers': {
        'answers': [
          {'value': 'A'},
          {'value': 'B'},
        ],
      },
    };
    expect((await service.onizle(b, await al(r2))).kaydedilebilir, isFalse);
  });
  test(
    'soru anahtarından öğrenci kimliği güncelleme hedefi oluşturulamaz',
    () async {
      await expectLater(
        service.formOlustur(
          b,
          baslik: 'X',
          sorular: [
            BilgiToplamaSorusu(anahtar: 'ekAd', baslik: 'Ad', hedefAlan: 'Ad'),
          ],
        ),
        throwsFormatException,
      );
      await expectLater(
        service.formOlustur(
          b,
          baslik: 'X',
          sorular: [BilgiToplamaSorusu(anahtar: 'okulNo', baslik: 'İkinci no')],
        ),
        throwsFormatException,
      );
    },
  );
  test('Google isteği sırasında mod değişirse yanıt kaydedilmez', () async {
    final client = MockClient((request) async {
      mod = null;
      return http.Response(
        jsonEncode({
          'responses': [yanit()],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    try {
      await expectLater(
        service.googleYanitlariniAl(
          b,
          formId,
          erisimBelirteci: 'test',
          google: RehberlikGoogleFormService(client: client),
        ),
        throwsStateError,
      );
      expect(await db.query('BilgiToplamaYanit'), isEmpty);
    } finally {
      client.close();
    }
  });
  test(
    'Google yanıtları mevcut istemci üzerinden alınır, token saklanmaz',
    () async {
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.url.path, '/v1/forms/google-form/responses');
        return http.Response(
          jsonEncode({
            'responses': [yanit()],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final google = RehberlikGoogleFormService(client: client);
      final ids = await service.googleYanitlariniAl(
        b,
        formId,
        erisimBelirteci: 'test-token',
        google: google,
      );
      expect(ids, hasLength(1));
      expect(
        jsonEncode(await db.query('BilgiToplamaYanit')),
        isNot(contains('test-token')),
      );
      client.close();
    },
  );
}
