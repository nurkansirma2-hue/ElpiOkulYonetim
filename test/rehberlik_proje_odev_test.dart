import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_google_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bilgi_toplama_service.dart';
import 'package:elpi_okul_yonetim/services/proje_odev_rapor_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/screens/rehberlik_proje_odev_screen.dart';
import 'support/windows_memory_database.dart';

class _ProjeYanitTestGoogle extends BilgiToplamaGoogleService {
  final silinen = <String>[];
  final hatali = <String>{};
  @override
  Future<List<int>> yanitlariAl(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async => [];
  @override
  Future<BilgiToplamaTopluSilmeSonucu> yanitlariTopluSil(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    BilgiToplamaSilmePlani plan,
    String token, {
    bool Function()? devamEt,
    void Function(int, int)? ilerleme,
  }) async {
    var n = 0;
    final hatalar = <String>[];
    for (final id in plan.googleYanitIdleri) {
      if (devamEt != null && !devamEt()) break;
      try {
        await yerel.topluSilmeYanitiSil(
          b,
          plan,
          id,
          googleSil: (fid, rid) async {
            if (hatali.contains(rid)) {
              throw StateError('Deneme bağlantı hatası');
            }
            silinen.add(rid);
          },
        );
        n++;
      } catch (e) {
        hatalar.add('$e');
      }
    }
    return BilgiToplamaTopluSilmeSonucu(n, plan.toplam - n, hatalar);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselRehberlikService s;
  late BireyselRehberlikBaglami b;
  late BireyselBilgiToplamaService fs;
  late BilgiToplamaOturumu fb;
  late int fid;
  const dersler = {1: 'Matematik', 2: 'Fizik', 3: 'İngilizce'};
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
      'SinifKodu': '9/C',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'SiraNo': 1});
    for (final e in dersler.entries) {
      await db.insert('Ders', {
        'DersId': e.key,
        'DersAdi': e.value,
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': 1,
        'DersId': e.key,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
    }
    for (var i = 1; i <= 3; i++) {
      await db.insert('Ogrenci', {
        'OkulNo': '${100 + i}',
        'Ad': 'Öğrenci$i',
        'Soyad': 'Uzun Soyadı',
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
    s = BireyselRehberlikService.instance;
    b = await s.hazirla();
    fs = BireyselBilgiToplamaService.instance;
    fb = await fs.hazirla();
    fid = await fs.formOlustur(
      fb,
      baslik: 'Proje',
      hedefTuru: 'OgrenciSec',
      ogrenciIdleri: {1, 2, 3},
      ogrenciListesi: true,
      sorular: [
        for (var i = 1; i <= 3; i++)
          BilgiToplamaSorusu(
            anahtar: 'projeTercih$i',
            baslik: '$i. Ders',
            veriTuru: 'Secenek',
            zorunlu: true,
            secenekler: dersler.values.toList(),
          ),
      ],
    );
    await s.projeFormunuBagla(b, 1, fid, dersler, 'Açıklama');
    final qs = await fs.sorular(fb, fid);
    await fs.googleBagla(fb, fid, 'google-proje-form', {
      for (final q in qs) q['AlanAnahtari'] as String: 'q${q['Id']}',
    });
  });
  tearDown(() async {
    await LocalDatabase.instance.close();
  });

  Future<void> yanit(
    int oid,
    List<int> secim, {
    String? id,
    String? zaman,
    Map<int, String> dersAdlari = dersler,
  }) async {
    final qs = await fs.sorular(fb, fid);
    final kimlik = qs.first;
    final etiket = (jsonDecode(kimlik['Secenekler'] as String) as List)
        .singleWhere((o) => o['ogrenciId'] == oid)['etiket'];
    final answers = <String, dynamic>{};
    for (final q in qs) {
      final key = q['AlanAnahtari'] as String;
      final value = key == 'ogrenciSecimi'
          ? etiket
          : dersAdlari[secim[int.parse(key.substring(key.length - 1)) - 1]];
      answers[q['GoogleSoruId'] as String] = {
        'textAnswers': {
          'answers': [
            {'value': value},
          ],
        },
      };
    }
    await fs.yanitlariKaydet(fb, fid, [
      {
        'responseId': id ?? 'r$oid',
        if (zaman != null) 'lastSubmittedTime': zaman,
        'answers': answers,
      },
    ]);
  }

  Future<void> onay() async {
    final r = await s.projeTercihleri(b, 1, fid);
    await s.projeTercihleriniOnayla(b, 1, fid, {
      for (final x in r.where((x) => (x['hatalar'] as List).isEmpty))
        x['OgrenciId'] as int: x['imza'] as String,
    });
  }

  Future<int> projeFormu(Map<int, String> secim) async {
    final id = await fs.formOlustur(
      fb,
      baslik: 'Sınıfın proje dersleri',
      ogrenciListesi: true,
      hedefTuru: 'OgrenciSec',
      ogrenciIdleri: {1, 2, 3},
      sorular: [
        for (var i = 1; i <= 3; i++)
          BilgiToplamaSorusu(
            anahtar: 'projeTercih$i',
            baslik: '$i. Ders',
            veriTuru: 'Secenek',
            zorunlu: true,
            secenekler: secim.values.toList(),
          ),
      ],
    );
    await s.projeFormunuBagla(b, 1, id, secim, 'Açıklama');
    return id;
  }

  test(
    'sınıf ders kaydındaki bütün dersler gelir; altı ders sınırı yoktur',
    () async {
      for (var i = 4; i <= 8; i++) {
        await db.insert('Ders', {
          'DersId': i,
          'DersAdi': 'Sınıf dersi $i',
          'OlusturmaTarihi': 'test',
        });
        await db.insert('DersSinif', {
          'DersId': i,
          'SinifSubeId': 1,
          'EgitimOgretimYili': '2026/2027',
          'OlusturmaTarihi': 'test',
        });
      }
      await db.insert('Ders', {
        'DersId': 9,
        'DersAdi': 'Geçmiş yıl dersi',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersSinif', {
        'DersId': 9,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2025/2026',
        'OlusturmaTarihi': 'test',
      });
      final liste = await s.projeDersleri(b, 1);
      expect(liste, hasLength(8));
      expect(liste.any((d) => d['DersId'] == 9), false);
      final secim = {
        for (final d in liste) d['DersId'] as int: d['DersAdi'] as String,
      };
      final id = await projeFormu(secim);
      expect(
        (await s.projeTalepleri(
          b,
          1,
        )).singleWhere((p) => p['formId'] == id)['dersler'],
        hasLength(8),
      );
    },
  );
  test(
    'elle eklenen ders yalnız bu formda kalır ve dağıtıma bağlanır',
    () async {
      const secim = {1: 'Matematik', 2: 'Fizik', -1: 'Kimya'};
      final onceki = await db.query('Ders');
      fid = await projeFormu(secim);
      final qs = await fs.sorular(fb, fid);
      await fs.googleBagla(fb, fid, 'elle-dersli-google-form', {
        for (final q in qs) q['AlanAnahtari'] as String: 'q${q['Id']}',
      });
      await yanit(1, [-1, 1, 2], dersAdlari: secim);
      await onay();
      final plan = await s.projeDagitimOnizle(b, 1, fid, null);
      expect(plan['dagitim'], {'1': -1});
      await s.projeDagitiminiKaydet(b, 1, fid, plan);
      expect(await db.query('Ders'), onceki);
      expect(
        (await s.projeTalepleri(
          b,
          1,
        )).singleWhere((p) => p['formId'] == fid)['dersler'],
        {'1': 'Matematik', '2': 'Fizik', '-1': 'Kimya'},
      );
    },
  );
  test(
    'elle eklenen ders adı tekrarlanamaz; ilgisiz katalog dersi bağlanamaz',
    () async {
      await expectLater(
        projeFormu({1: 'Matematik', 2: 'Fizik', -1: 'matematik'}),
        throwsFormatException,
      );
      await db.insert('Ders', {
        'DersId': 4,
        'DersAdi': 'İlgisiz ders',
        'OlusturmaTarihi': 'test',
      });
      await expectLater(
        projeFormu({1: 'Matematik', 2: 'Fizik', 4: 'İlgisiz ders'}),
        throwsStateError,
      );
    },
  );

  test('sınıfın diğer ders öğretmenine bağlı ders de listeye alınır', () async {
    const kisi = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await db.insert('Ders', {
      'DersId': 10,
      'DersAdi': 'Biyoloji',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('MesajOgretmenKisi', {
      'KisiId': kisi,
      'OkulId': 'okul',
      'SahipProfilId': 1,
      'AdSoyad': 'Diğer Öğretmen',
      'OlusturmaTarihi': 'test',
      'GuncellemeTarihi': 'test',
    });
    await db.insert('MesajOgretmenSinif', {
      'KisiId': kisi,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026/2027',
      'Kaynak': 'ElleDogrulandi',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('MesajOgretmenSinifDers', {
      'KisiId': kisi,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026/2027',
      'DersId': 10,
    });
    expect((await s.projeDersleri(b, 1)).any((d) => d['DersId'] == 10), true);
    final id = await projeFormu({1: 'Matematik', 2: 'Fizik', 10: 'Biyoloji'});
    expect(
      (await s.projeTalepleri(
        b,
        1,
      )).singleWhere((p) => p['formId'] == id)['dersler'],
      containsPair('10', 'Biyoloji'),
    );
  });
  test(
    'aynı ders reddedilir; eksik yanıt bekleyen sayılır, tekrar getirme sayıyı artırmaz',
    () async {
      await yanit(1, [1, 2, 3]);
      await yanit(1, [1, 2, 3]);
      await yanit(2, [1, 1, 3]);
      final rows = await s.projeTercihleri(b, 1, fid);
      expect(rows, hasLength(3));
      expect(rows[0]['hatalar'], isEmpty);
      expect(rows[1]['hatalar'], contains('Üç farklı ders seçilmelidir.'));
      expect(rows[2]['bekliyor'], true);
      await onay();
      expect(
        (await s.projeTercihleri(b, 1, fid)).where((r) => r['onayli'] == true),
        hasLength(1),
      );
      expect(await db.query('OgrenciEkBilgiDeger'), isEmpty);
    },
  );
  test(
    'kontenjan isteğe bağlı; tercih turu ve açıkta kalanlar gerçek veriden hesaplanır',
    () async {
      for (var i = 1; i <= 3; i++) {
        await yanit(i, [1, 2, 3]);
      }
      await onay();
      final serbest = await s.projeDagitimOnizle(b, 1, fid, null);
      expect((serbest['dagitim'] as Map).values.toList(), [1, 1, 1]);
      final kisit = await s.projeDagitimOnizle(b, 1, fid, {1: 1, 2: 1, 3: 0});
      expect(kisit['dagitim'], {'1': 1, '2': 2});
      expect(kisit['acikta'], 1);
      await s.projeDagitiminiKaydet(b, 1, fid, kisit);
      expect((await s.projeTalepleri(b, 1)).single['dagitimOnayli'], true);
      await expectLater(
        s.projeDagitiminiKaydet(b, 1, fid, kisit),
        throwsStateError,
      );
    },
  );
  test(
    'yeni yanıt eski onayı ve bekleyen dağıtım ön izlemesini geçersiz kılar',
    () async {
      await yanit(1, [1, 2, 3]);
      await onay();
      final plan = await s.projeDagitimOnizle(b, 1, fid, null);
      await yanit(1, [2, 1, 3], zaman: '2026-11-16T10:00:00Z');
      expect((await s.projeTercihleri(b, 1, fid)).first['onayli'], false);
      await expectLater(
        s.projeDagitiminiKaydet(b, 1, fid, plan),
        throwsStateError,
      );
    },
  );
  test(
    'çoklu yanıt otomatik seçilmez; geçmiş atama ve farklı profil yazamaz',
    () async {
      await yanit(1, [1, 2, 3]);
      await yanit(1, [2, 1, 3], id: 'ikinci');
      expect((await s.projeTercihleri(b, 1, fid)).first['hatalar'], isNotEmpty);
      await db.update('RehberlikAtama', {
        'BitisTarihi': '2001-01-01',
      }, where: 'RehberlikAtamaId=1');
      await expectLater(
        s.projeTercihleriniOnayla(b, 1, fid, {1: 'sahte'}),
        throwsStateError,
      );
      expect(await s.projeTalepleri(b, 1), hasLength(1));
      await db.update('OgretmenProfil', {
        'EgitimOgretimYili': '2027/2028',
      }, where: 'OgretmenProfilId=1');
      await expectLater(s.projeTalepleri(b, 1), throwsStateError);
    },
  );
  test(
    'manuel atama tercihler dışına veya kontenjan üzerine çıkamaz',
    () async {
      await yanit(1, [1, 2, 3]);
      await yanit(2, [1, 2, 3]);
      await onay();
      final plan = await s.projeDagitimOnizle(b, 1, fid, {1: 1, 2: 1, 3: 0});
      (plan['dagitim'] as Map)['2'] = 1;
      await expectLater(
        s.projeDagitiminiKaydet(b, 1, fid, plan),
        throwsStateError,
      );
      (plan['dagitim'] as Map)['2'] = 999;
      await expectLater(
        s.projeDagitiminiKaydet(b, 1, fid, plan),
        throwsStateError,
      );
    },
  );
  test('gerçek xlsx docx pdf çıktıları üretir', () async {
    for (final ext in ['xlsx', 'docx', 'pdf']) {
      final bytes = await ProjeOdevRaporService.olustur(
        ext,
        'Türkçe Proje Raporu',
        'Okul • 2026/2027',
        [
          ['No', 'Öğrenci'],
          ['101', 'Şule Öğrenci'],
        ],
      );
      expect(bytes.length, greaterThan(100));
      expect(
        String.fromCharCodes(bytes.take(ext == 'pdf' ? 4 : 2)),
        ext == 'pdf' ? '%PDF' : 'PK',
      );
    }
  });
  test('silinen ve reddedilen yanıtlar tercih onayına alınmaz', () async {
    await yanit(1, [1, 2, 3]);
    final r = (await s.projeTercihleri(b, 1, fid)).first;
    final p = await fs.onizle(fb, r['yanitId'] as int);
    await fs.reddet(fb, p);
    expect(
      (await s.projeTercihleri(b, 1, fid)).first['hatalar'],
      contains('Yanıt ortak formda reddedilmiş.'),
    );
    await fs.yanitiSil(fb, await fs.onizle(fb, r['yanitId'] as int));
    expect((await s.projeTercihleri(b, 1, fid)).first['bekliyor'], true);
  });
  test(
    'sınıftan ayrılan öğrenci görünür kalır; eski onay kullanılamaz ve mod kontrol edilir',
    () async {
      await yanit(1, [1, 2, 3]);
      await onay();
      await db.update('OgrenciSinifKayit', {'Aktif': 0}, where: 'OgrenciId=1');
      final r = await s.projeTercihleri(b, 1, fid);
      expect(r, hasLength(3));
      expect(r.first['onayli'], false);
      expect(r.first['hatalar'], contains('Öğrenci kaydı pasif.'));
      final yetkisiz = BireyselRehberlikService(
        databaseGetir: () async => db,
        modGetir: () async => null,
      );
      await expectLater(yetkisiz.projeTalepleri(b, 1), throwsStateError);
    },
  );
  test(
    'tam SQLite yedeği formu, tercih onaylarını ve kesin dağıtımı geri yükler',
    () async {
      final temp = await Directory.systemTemp.createTemp('proje_yedek_test_');
      try {
        await yanit(1, [1, 2, 3]);
        await onay();
        final plan = await s.projeDagitimOnizle(b, 1, fid, null);
        await s.projeDagitiminiKaydet(b, 1, fid, plan);
        final onceki = await s.projeTalepleri(b, 1);
        final bakim = BireyselBakimService(
          databaseGetir: () async => db,
          alanGetir: () async => temp,
        );
        final yedek = await bakim.yedekle();
        await bakim.geriYukle(
          await bakim.incele(yedek.dosya),
          onayMetni: 'GERİ YÜKLE',
        );
        final yeniden = BireyselRehberlikService(databaseGetir: () async => db);
        expect(
          await yeniden.projeTalepleri(await yeniden.hazirla(), 1),
          onceki,
        );
        expect(
          (await yeniden.projeTercihleri(
            await yeniden.hazirla(),
            1,
            fid,
          )).first['onayli'],
          true,
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  test(
    'Google hazırlama üç ders açılır listesi ve açıklamayı ortak adaptörde oluşturur',
    () async {
      final id = await fs.formOlustur(
        fb,
        baslik: 'Yeni proje',
        ogrenciListesi: true,
        hedefTuru: 'OgrenciSec',
        ogrenciIdleri: {1, 2, 3},
        sorular: [
          for (var i = 1; i <= 3; i++)
            BilgiToplamaSorusu(
              anahtar: 'projeTercih$i',
              baslik: '$i. Ders',
              veriTuru: 'Secenek',
              zorunlu: true,
              secenekler: dersler.values.toList(),
            ),
        ],
      );
      final remote = <String, dynamic>{
        'formId': 'yeni-google-form',
        'info': {'title': 'Yeni proje'},
        'items': <dynamic>[],
      };
      var olusturma = 0;
      final g = BilgiToplamaGoogleService(
        client: MockClient((r) async {
          if (r.method == 'POST' && r.url.path == '/v1/forms') {
            olusturma++;
            return http.Response(
              jsonEncode({'formId': 'yeni-google-form'}),
              200,
            );
          }
          if (r.method == 'POST' && r.url.path.endsWith(':batchUpdate')) {
            final requests = jsonDecode(r.body)['requests'] as List;
            for (final q in requests) {
              if (q['updateFormInfo'] != null) {
                (remote['info'] as Map)['description'] =
                    q['updateFormInfo']['info']['description'];
              }
              if (q['createItem'] != null) {
                (remote['items'] as List).add(q['createItem']['item']);
              }
            }
            return http.Response('{}', 200);
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode(remote)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await g.hazirla(
        fs,
        fb,
        id,
        'test-token',
        aciklama: 'Üç farklı ders seçiniz.',
      );
      expect(olusturma, 1);
      expect((remote['info'] as Map)['description'], 'Üç farklı ders seçiniz.');
      expect(remote['items'], hasLength(4));
      for (final q in remote['items'] as List) {
        expect(
          q['questionItem']['question']['choiceQuestion']['type'],
          'DROP_DOWN',
        );
      }
      await g.hazirla(
        fs,
        fb,
        id,
        'test-token',
        aciklama: 'Üç farklı ders seçiniz.',
      );
      expect(olusturma, 1);
    },
  );
  test('yerel düzeltme özgün yanıtı korur; tekrar onay gerektirir', () async {
    await yanit(1, [1, 2, 3]);
    await onay();
    final r = (await s.projeTercihleri(b, 1, fid)).first;
    final p = await fs.onizle(fb, r['yanitId'] as int);
    final eski = await fs.duzenlenecekCevaplar(fb, p);
    await fs.yanitiDuzenle(fb, p, {
      ...eski,
      'projeTercih1': 'Fizik',
      'projeTercih2': 'Matematik',
    });
    final yeni = (await s.projeTercihleri(b, 1, fid)).first;
    expect(yeni['onayli'], false);
    expect(yeni['tercihler'], [2, 1, 3]);
    expect(await db.query('BilgiToplamaYanit'), hasLength(2));
    expect((await s.projeTalepleri(b, 1)).single['onaylar'], isNotEmpty);
  });
  Future<void> yanitIslemleriniDogrula(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await yanit(1, [1, 2, 3]);
      await yanit(2, [1, 1, 3]);
    });
    final g = _ProjeYanitTestGoogle();
    Future<void> bekle() async {
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pump();
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 300));
          return;
        }
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: RehberlikProjeOdevScreen(
          service: s,
          baglam: b,
          formService: fs,
          google: g,
          hesapBagla: () async => 'test',
          atama: const {
            'RehberlikAtamaId': 1,
            'SinifSubeId': 1,
            'SinifKodu': '9/C',
            'EgitimOgretimYili': '2026/2027',
          },
        ),
      ),
    );
    await bekle();
    await tester.tap(find.text('Proje'));
    await bekle();
    await tester.tap(find.text('Yanıtlar'));
    await bekle();
    expect(find.text('Ortak form ayrıntısı / yanıt düzenleme'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    final ilk = find.textContaining('101 • Öğrenci1');
    await tester.tap(ilk);
    await bekle();
    expect(find.text('101 • Tercih düzenle'), findsOneWidget);
    await tester.tap(find.text('İptal'));
    await bekle();
    await tester.tap(ilk);
    await bekle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Fizik').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Matematik').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Düzeltmeyi kaydet'));
    await bekle();
    expect(await fs.yanitlar(fb, fid), hasLength(2));
    expect(await db.query('BilgiToplamaYanit'), hasLength(3));
    await tester.longPress(ilk);
    await bekle();
    expect(find.text('Toplu Onayla (1)'), findsOneWidget);
    await tester.tap(find.text('Toplu Onayla (1)'));
    await bekle();
    await tester.tap(find.text('Onayla').last);
    await bekle();
    expect(find.text('Onaylı'), findsOneWidget);
    await tester.longPress(ilk);
    await bekle();
    await tester.tap(find.text('Tümünü seç (1/2)'));
    await bekle();
    await tester.tap(find.text('Toplu Onayla (2)'));
    await bekle();
    expect(
      find.textContaining('1 sorunlu yanıt onaylanmayacak'),
      findsOneWidget,
    );
    await tester.tap(find.text('Onayla').last);
    await bekle();
    await tester.longPress(ilk);
    await bekle();
    await tester.tap(find.text('Tümünü seç (1/2)'));
    await bekle();
    expect(find.text('Toplu Sil (2)'), findsOneWidget);
    await tester.tap(find.text('Toplu Sil (2)'));
    await bekle();
    expect(find.text('Seçili yanıtları sil'), findsOneWidget);
    await tester.tap(find.text('İptal'));
    await bekle();
    expect(g.silinen, isEmpty);
    expect(await fs.yanitlar(fb, fid), hasLength(2));
    g.hatali.add('r2');
    await tester.tap(find.text('Toplu Sil (2)'));
    await bekle();
    await tester.tap(find.text('Onayla').last);
    await bekle();
    expect(g.silinen, ['r1']);
    expect(await fs.yanitlar(fb, fid), hasLength(1));
    expect(
      find.textContaining('1 yanıt silindi; 1 yanıt kaldı.'),
      findsOneWidget,
    );
    expect(find.textContaining('101 • Öğrenci1'), findsNothing);
    expect(find.textContaining('102 • Öğrenci2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    g.dispose();
  }

  testWidgets('320 ve büyük yazıda proje listesi, kontrol ve dağıtım taşmaz', (
    tester,
  ) async {
    const visual = bool.fromEnvironment('PROJE_GORSEL');
    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('proje_arsiv_test_'),
    );
    final belgeler = BireyselBelgeService(
      databaseGetir: () async => db,
      alanGetir: () async => temp!,
      geciciAlanGetir: () async => temp!,
    );
    await tester.runAsync(() async {
      await yanit(1, [1, 2, 3]);
      await yanit(2, [1, 1, 3]);
      await onay();
      final dagitim = await s.projeDagitimOnizle(b, 1, fid, null);
      await s.projeDagitiminiKaydet(b, 1, fid, dagitim);
    });
    if (visual) {
      await (FontLoader('NotoSans')
            ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    final key = GlobalKey();
    Future<void> bekle() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    Future<void> capture(String ad) async {
      if (!visual) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('test-artifacts/proje');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/$ad.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        img.dispose();
      });
    }

    for (final width in [320.0, 400.0]) {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff1675ed),
              ),
              fontFamily: 'NotoSans',
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 850),
                textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
              ),
              child: RehberlikProjeOdevScreen(
                service: s,
                baglam: b,
                formService: fs,
                belgeService: belgeler,
                atama: const {
                  'RehberlikAtamaId': 1,
                  'SinifSubeId': 1,
                  'SinifKodu': '9/C',
                  'EgitimOgretimYili': '2026/2027',
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Proje'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Proje'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('${width.toInt()}-5-yanitlar');
      await tester.tap(find.text('Yanıtlar'));
      await bekle();
      expect(find.text('Ortak form ayrıntısı / yanıt düzenleme'), findsNothing);
      await capture('${width.toInt()}-5-yanit-listesi');
      await tester.longPress(find.textContaining('101 • Öğrenci1'));
      await bekle();
      expect(find.text('Toplu Sil (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('${width.toInt()}-5-yanit-secimi');
      await tester.tap(find.byTooltip('Seçimi kapat'));
      await bekle();
      await tester.tap(find.text('Özet'));
      await bekle();
      for (final (i, ad) in [
        (0, 'Form Daveti'),
        (2, 'Tercih Kontrolü'),
        (3, 'Ders Dağıtımı'),
        (4, 'Liste ve Raporlar'),
      ]) {
        await tester.tap(find.byTooltip('İşlem değiştir'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ad).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('${width.toInt()}-${i + 4}-$ad');
        if (i == 4) {
          await tester.tap(find.text('Belgelerim’e Kaydet'));
          await bekle();
          expect(tester.takeException(), isNull);
          expect(await db.query('BireyselBelge'), isNotEmpty);
          expect(
            (await db.query('BireyselBelge')).first['EgitimOgretimYili'],
            '2026/2027',
          );
        }
      }
      await tester.tap(find.byTooltip('Proje taleplerine dön'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Form Talebi Oluştur'));
      await bekle();
      expect(tester.takeException(), isNull);
      await capture('${width.toInt()}-1-kapsam');
      await tester.tap(find.text('İleri'));
      await bekle();
      expect(tester.takeException(), isNull);
      await capture('${width.toInt()}-2-sorular');
      await tester.ensureVisible(find.text('Ders Ekle'));
      await tester.tap(find.text('Ders Ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Kimya (elle)');
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();
      final eklenen = find.widgetWithText(CheckboxListTile, 'Kimya (elle)');
      await tester.ensureVisible(eklenen);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(eklenen).value, true);
      await tester.tap(eklenen);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(eklenen).value, false);
      await tester.tap(find.text('İleri'));
      await bekle();
      expect(tester.takeException(), isNull);
      await capture('${width.toInt()}-3-kontrol');
      final dersAciliri = tester
          .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .skip(1);
      expect(dersAciliri, hasLength(3));
      for (final alan in dersAciliri) {
        expect(alan.items, hasLength(3));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    await yanitIslemleriniDogrula(tester);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.runAsync(() => temp!.delete(recursive: true));
  });
}
