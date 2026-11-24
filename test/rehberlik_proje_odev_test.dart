import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elpi_okul_yonetim/services/bilgi_toplama_google_service.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_google_form_service.dart';
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
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'support/windows_memory_database.dart';

class _ProjeYanitTestGoogle extends BilgiToplamaGoogleService {
  @override
  bool get dogrudanYanitOkuma => false;
  final silinen = <String>[];
  final hatali = <String>{};
  final silinenFormlar = <int>[];
  final hataliFormlar = <int>{};
  final manuelDogrulanan = <String>[];
  final manuelMevcut = <String>{};
  bool yanitAcik = true;
  bool yanitAyarHatali = false;
  final yanitAlimiIslemleri = <bool>[];
  @override
  Future<Map<String, dynamic>> kontrolEt(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async => {
    'formId': 'google-proje-form',
    'publishSettings': {
      'publishState': {
        'isPublished': true,
        'isAcceptingResponses': yanitAcik,
      },
    },
  };
  @override
  Future<void> yanitAliminiAyarla(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
    bool acik,
  ) async {
    if (yanitAyarHatali) throw StateError('Google bağlantısı başarısız.');
    yanitAcik = acik;
    yanitAlimiIslemleri.add(acik);
    await yerel.yayinDurumuKaydet(b, id, 'google-proje-form', acik);
  }
  @override
  Future<void> googleSilinmesiniDogrula(
    String token,
    String formId,
    String responseId,
  ) async {
    if (manuelMevcut.contains(responseId)) {
      throw StateError('Yanıt Google’da hâlâ mevcut.');
    }
    manuelDogrulanan.add(responseId);
  }
  @override
  Future<void> formuSil(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async {
    await yerel.formuSil(
      b,
      id,
      googleTemizle: (_) async {
        if (hataliFormlar.contains(id)) {
          throw StateError('Deneme Google hatası');
        }
        silinenFormlar.add(id);
      },
    );
  }

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
    List<Map<String, dynamic>>? dogrudanHedefler,
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

class _IlkSecimGoogle extends _ProjeYanitTestGoogle {
  bool okumaHatasi = false;
  @override
  bool get dogrudanYanitOkuma => true;
  final ilkSecilenler = <String>[];
  final canli = <String, Map<String, dynamic>>{
    for (final (id, zaman) in [
      ('native-old', '2026-11-15T20:38:00.000Z'),
      ('native-new', '2026-11-18T10:00:00.000Z'),
    ])
      id: {
        'source': 'apps-script/v2',
        'formId': 'google-proje-form',
        'responseId': id,
        'submittedTime': zaman,
        'answers': [
          {
            'itemId': '1',
            'title': 'Öğrenciyi seçin',
            'values': ['9/C • 101 • Öğrenci1 Uzun Soyadı'],
          },
          {
            'itemId': '2',
            'title': '1. Ders Tercihi',
            'values': ['Matematik'],
          },
        ],
      },
  };
  @override
  Future<List<Map<String, dynamic>>> dogrudanYanitlariAl(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int formId,
    String token,
  ) async {
    if (okumaHatasi) throw StateError('Test: silme betiği henüz güncellenmemiş.');
    return canli.values.toList();
  }
  @override
  Future<BilgiToplamaTopluSilmeSonucu> yanitlariTopluSil(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    BilgiToplamaSilmePlani plan,
    String token, {
    bool Function()? devamEt,
    void Function(int, int)? ilerleme,
    List<Map<String, dynamic>>? dogrudanHedefler,
  }) async {
    expect(dogrudanHedefler, isNotNull);
    expect(devamEt?.call(), true);
    for (final row in dogrudanHedefler!) {
      ilkSecilenler.add(row['responseId'] as String);
      canli.remove(row['responseId']);
    }
    return BilgiToplamaTopluSilmeSonucu(dogrudanHedefler.length, 0, []);
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

  Future<void> ogretmenEkle(String kisi, int dersId, {int sinifId = 1}) async {
    await db.insert('MesajOgretmenKisi', {
      'KisiId': kisi,
      'OkulId': 'okul',
      'SahipProfilId': 1,
      'AdSoyad': 'Öğretmen $dersId',
      'Telefon': '05321112233',
      'OlusturmaTarihi': 'test',
      'GuncellemeTarihi': 'test',
    });
    await db.insert('MesajOgretmenSinif', {
      'KisiId': kisi,
      'SinifSubeId': sinifId,
      'EgitimOgretimYili': '2026/2027',
      'Kaynak': 'ElleDogrulandi',
      'OlusturmaTarihi': 'test',
    });
    if (dersId > 0) {
      await db.insert('MesajOgretmenSinifDers', {
        'KisiId': kisi,
        'SinifSubeId': sinifId,
        'EgitimOgretimYili': '2026/2027',
        'DersId': dersId,
      });
    }
  }

  Future<void> tamDagitim() async {
    await yanit(1, [1, 2, 3]);
    await yanit(2, [2, 1, 3]);
    await yanit(3, [3, 1, 2]);
    await onay();
    await s.projeDagitiminiKaydet(
      b,
      1,
      fid,
      await s.projeDagitimOnizle(b, 1, fid, null),
    );
  }

  test(
    'Sıfırla yalnız seçili proje formunu temizler ve yeniden yanıt alabilir',
    () async {
      await tamDagitim();
      final digerForm = await projeFormu(dersler);
      final qs = await fs.sorular(fb, digerForm);
      await fs.googleBagla(fb, digerForm, 'google-diger-form', {
        for (final q in qs) q['AlanAnahtari'] as String: 'd${q['Id']}',
      });
      final ogrenciler = await db.query('Ogrenci');
      final once = (await s.projeTalepleri(b, 1))
          .singleWhere((p) => p['formId'] == fid);
      expect(once['onaylar'], isNotEmpty);
      expect(once['dagitimOnayli'], true);

      final birinciYanit = await fs.yanitlar(fb, fid);
      final onizleme = await fs.onizle(
        fb,
        birinciYanit.first['Id'] as int,
      );
      await fs.yanitiSil(fb, onizleme);
      final silmeIsaretleri = await db.query(
        'UygulamaAyarlari',
        where: 'Anahtar LIKE ?',
        whereArgs: ['bilgi_toplama_silinen:$fid:%'],
      );
      expect(silmeIsaretleri, isNotEmpty);

      await s.projeYanitlariniSifirla(b, 1, fid);
      expect(await db.query('BilgiToplamaYanit',
          where: 'FormId=?', whereArgs: [fid]), isEmpty);
      expect(await db.query('BilgiToplamaEsleme',
          where: 'FormId=?', whereArgs: [fid]), isEmpty);
      expect(await db.query('UygulamaAyarlari',
          where: 'Anahtar LIKE ?',
          whereArgs: ['bilgi_toplama_silinen:$fid:%']), isEmpty);
      final yeni = (await s.projeTalepleri(b, 1))
          .singleWhere((p) => p['formId'] == fid);
      expect(yeni['onaylar'], isEmpty);
      expect(yeni['dagitim'], isEmpty);
      expect(yeni['dagitimOnayli'], isNull);
      expect(yeni['sonuclandi'], isNull);
      expect(await db.query('Ogrenci'), ogrenciler);
      expect((await s.projeTalepleri(b, 1)).length, 2);
      expect(await fs.yanitlar(fb, digerForm), isEmpty);

      // Eski silme işareti yeni içe aktarmayı engellememeli.
      await yanit(1, [1, 2, 3]);
      expect(await fs.yanitlar(fb, fid), hasLength(1));
      expect((await s.projeTercihleri(b, 1, fid)).first['hatalar'], isEmpty);
    },
  );

  test(
    'Sıfırla öğrenciye aktarılmış bilgiyi ve yerel yanıtları korur',
    () async {
      await yanit(1, [1, 2, 3]);
      final r = (await fs.yanitlar(fb, fid)).single;
      final soru = (await fs.sorular(fb, fid)).first;
      // Bağlı öğrenci kimliği ve form ilişkisi gerçek FK şartını sağlamalı.
      await db.update('BilgiToplamaYanit', {'OgrenciId': 1},
          where: 'Id=?', whereArgs: [r['Id']]);
      // Aktarılmış kayıt, ham yanıtın silinmesine engel olmalıdır.
      await db.insert('OgrenciEkBilgiDeger', {
        'YanitId': r['Id'],
        'FormId': fid,
        'SoruId': soru['Id'],
        'OgrenciId': 1,
        'Deger': 'Korunacak bilgi',
      });
      await expectLater(
        s.projeYanitlariniSifirla(b, 1, fid),
        throwsStateError,
      );
      expect(await fs.yanitlar(fb, fid), hasLength(1));
      expect(await db.query('OgrenciEkBilgiDeger'), hasLength(1));
    },
  );
  test(
    'değerlendirme gerçek tercih sayılarını ve eksik/hatalı öğrencileri analiz eder',
    () async {
      await yanit(1, [1, 2, 3]);
      await yanit(2, [1, 1, 3]);
      final an = await s.projeAnalizi(b, 1, fid);
      expect(an['bekleyen'], 1);
      expect(an['sorunlu'], 1);
      expect(an['gecerli'], 1);
      expect(an['yerlesen'], 0);
      expect(
        (an['dersler'] as List).firstWhere(
          (d) => d['dersId'] == 1,
        )['tercihler'],
        [1, 0, 0],
      );
      await expectLater(
        s.projeSonuclandir(b, 1, fid, an['imza'] as String),
        throwsStateError,
      );
    },
  );
  test(
    'sonuçlandırılan seçim kalıcıdır; öğretmen mesajı yalnız kendi dersinin öğrencilerini içerir',
    () async {
      const kisi = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await tamDagitim();
      await ogretmenEkle(kisi, 1);
      await expectLater(s.projeSonucMesaji(b, 1, fid, 1), throwsStateError);
      final an = await s.projeAnalizi(b, 1, fid);
      expect(an['sonuclanabilir'], true);
      await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
      expect((await s.projeAnalizi(b, 1, fid))['sonuclandi'], true);
      final paket = await s.projeSonucMesaji(b, 1, fid, 1);
      expect(paket['aliciIds'], [kisi]);
      expect(paket['metin'], contains('101 – Öğrenci1'));
      expect(paket['metin'],
          contains('9/C Sınıfı Matematik dersinizden proje ödevi alan öğrenciler:'));
      expect(paket['metin'],
          contains('İyi çalışmalar.\nÖğretmen 9/C Sınıf Öğretmeni'));
      expect(paket['metin'], isNot(contains('Öğrenci2')));
      expect(paket['metin'], contains('9/C'));
      expect(
        (await s.projeTalepleri(b, 1)).single['sonucGecmisi'],
        hasLength(1),
      );
    },
  );
  testWidgets(
    'onaylı dağıtım sonuçlandırılmadan listelenir, kesin öğretmen mesajı kapalı kalır',
    (tester) async {
      const kisi = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await tamDagitim();
      await ogretmenEkle(kisi, 1);
      final durum = await s.projeAnalizi(b, 1, fid);
      expect(durum['sonuclandi'], false);
      expect(durum['yerlesen'], 3);
      final g = _ProjeYanitTestGoogle();
      addTearDown(g.dispose);
      Future<void> bekle() async {
        for (var i = 0; i < 70; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(MaterialApp(
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
      ));
      await bekle();
      await tester.tap(find.text('Sınıfın proje dersleri'));
      await bekle();
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-4')));
      await bekle();
      expect(find.textContaining('Kesin sonuç mesajları'), findsOneWidget);
      final ilk = find.byKey(const ValueKey('bildirim-ogrenci-1'));
      await tester.ensureVisible(ilk);
      await tester.tap(ilk);
      await bekle();
      expect(find.text('Öğrenciye Mesaj At (1)'), findsOneWidget);
      final buton = find.widgetWithText(FilledButton, 'Öğrenciye Mesaj At (1)');
      await tester.ensureVisible(buton);
      expect(tester.widget<FilledButton>(buton).onPressed, isNull);
      await tester.tap(find.text('Ders Bazlı'));
      await bekle();
      final ders1 = find.byKey(const ValueKey('bildirim-ders-1'));
      await tester.ensureVisible(ders1);
      await tester.tap(ders1);
      await bekle();
      expect(find.text('Öğretmene Mesaj At (1)'), findsOneWidget);
      expect(tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Öğretmene Mesaj At (1)'),
      ).onPressed, isNull);
      expect(find.byType(MesajlasmaScreen), findsNothing);
      expect((await s.projeTalepleri(b, 1)).single['dagitimOnayli'], true);
      expect((await s.projeTalepleri(b, 1)).single['sonuclandi'], false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'beş aşamada sonuçlandırılan atama öğrenci mesajına doğru dersle aktarılır',
    (tester) async {
      await tamDagitim();
      final an = await s.projeAnalizi(b, 1, fid);
      await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
      final g = _ProjeYanitTestGoogle();
      addTearDown(g.dispose);
      Future<void> bekle() async {
        for (var i = 0; i < 70; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(MaterialApp(
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
      ));
      await bekle();
      await tester.tap(find.text('Sınıfın proje dersleri'));
      await bekle();
      expect(find.byKey(const ValueKey('proje-ust-sekme-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('proje-ust-sekme-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('proje-ust-sekme-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('proje-ust-sekme-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('proje-ust-sekme-4')), findsOneWidget);
      expect(find.byTooltip('İşlem değiştir'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-4')));
      await bekle();
      expect(find.text('Öğrenci Bazlı'), findsOneWidget);
      expect(find.text('Ders Bazlı'), findsOneWidget);
      expect(find.text('Yenile'), findsNothing);
      expect(find.text('Öğrenciye Mesaj At (0)'), findsOneWidget);
      final tek = find.byKey(const ValueKey('bildirim-ogrenci-1'));
      await tester.ensureVisible(tek);
      await tester.tap(tek);
      await bekle();
      expect(find.text('Öğrenciye Mesaj At (1)'), findsOneWidget);
      await tester.tap(tek);
      await bekle();
      expect(find.text('Öğrenciye Mesaj At (0)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bildirim-tumunu-sec')));
      await bekle();
      expect(find.text('Öğrenciye Mesaj At (3)'), findsOneWidget);
      // Alt eylem kaydırılabilir ListView içinde değil, sabit çubuktadır.
      expect(
        find.ancestor(
          of: find.text('Öğrenciye Mesaj At (3)'),
          matching: find.byType(ListView),
        ),
        findsNothing,
      );
      // En az bir geçerli veli numarası olduğunda otomatik gönderim
      // ön izlemesinin açılması gerekir; boş takip ekranında kalmamalı.
      await db.update(
        'Ogrenci',
        {'VeliAdi': 'Veli1', 'VeliTelefonu': '05321234567'},
        where: 'OgrenciId=?',
        whereArgs: [1],
      );
      final hazirla = find.text('Öğrenciye Mesaj At (3)');
      await tester.ensureVisible(hazirla);
      await tester.tap(hazirla);
      await bekle();
      final ekran = tester.widget<MesajlasmaScreen>(
        find.byType(MesajlasmaScreen),
      );
      expect(ekran.baslangicOgrenciIdleri, {1, 2, 3});
      expect(ekran.izinliOgrenciIdleri, {1, 2, 3});
      expect(ekran.yalnizGonderimOnayi, true);
      expect(ekran.gonderimOnizlemesiniAc, true);
      expect(ekran.baslangicMetni, 'Proje ödevi bilgilendirmesi');
      expect(find.text('Mesajı gönder'), findsOneWidget);
      expect(ekran.ogrenciMesajlari?[1],
          contains('Sevgili Öğrenci1 Uzun Soyadı,'));
      expect(ekran.ogrenciMesajlari?[1],
          contains('9/C Sınıfı Proje Ödevi'));
      expect(ekran.ogrenciMesajlari?[1],
          contains('Proje ödevi alacağın ders: Matematik'));
      expect(ekran.ogrenciMesajlari?[1],
          contains('Başarılar dilerim.\nÖğretmen\n9/C Sınıf Öğretmeni'));
      expect(ekran.ogrenciMesajlari?[1], isNot(contains('Öğrenci2')));
      expect(ekran.ogrenciMesajlari?[2],
          contains('Sevgili Öğrenci2 Uzun Soyadı,'));
      expect(ekran.gonderimOnizlemesiniAc, true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Formlarım aktif ve arşiv kayıtlarını ayrı gösterir', (tester) async {
    await fs.yayinDurumuKaydet(fb, fid, 'google-proje-form', false);
    await fs.isaretle(fb, fid, 'Arşivle');
    await tester.pumpWidget(MaterialApp(
      home: RehberlikProjeOdevScreen(
        service: s,
        baglam: b,
        formService: fs,
        google: _ProjeYanitTestGoogle(),
        hesapBagla: () async => 'test',
        atama: const {
          'RehberlikAtamaId': 1,
          'SinifSubeId': 1,
          'SinifKodu': '9/C',
          'EgitimOgretimYili': '2026/2027',
        },
      ),
    ));
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.text('Aktif Formlar'), findsOneWidget);
    // Formlarım sadeleşirken durumlar, arşiv ve karttan ayrıntı korunur.
    expect(find.text('Form veya ders ara'), findsNothing);
    expect(find.text('Tercihleri Kontrol Et'), findsNothing);
    expect(find.text('Bilgilendirme / Listeler'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Yanıtlar'), findsNothing);
    expect(find.text('Yenile'), findsOneWidget);
    expect(find.text('Form Talebi Oluştur'), findsOneWidget);
    expect(find.text('Arşiv'), findsOneWidget);
    expect(find.byKey(ValueKey('proje-form-$fid')), findsNothing);
    await tester.tap(find.text('Arşiv'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('proje-form-$fid')), findsOneWidget);
    expect(find.text('Yanıtlar kapalı'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byKey(ValueKey('proje-form-$fid')),
      matching: find.byType(ListTile),
    ).first);
    await tester.pumpAndSettle();
    expect(find.text('Bilgilendirme'), findsOneWidget);
  });

  testWidgets(
    'aynı öğretmenin iki proje dersinin öğrencileri tek mesajda hazırlanır',
    (tester) async {
      const kisi = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await tamDagitim();
      await ogretmenEkle(kisi, 1);
      await s.projeDersOgretmeniEsle(b, 1, fid, 2, {kisi});
      final an = await s.projeAnalizi(b, 1, fid);
      await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
      final g = _ProjeYanitTestGoogle();
      addTearDown(g.dispose);
      Future<void> bekle() async {
        for (var i = 0; i < 70; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(MaterialApp(
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
      ));
      await bekle();
      await tester.tap(find.text('Sınıfın proje dersleri'));
      await bekle();
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-4')));
      await bekle();
      await tester.tap(find.text('Ders Bazlı'));
      await bekle();
      for (final id in [1, 2]) {
        final kart = find.byKey(ValueKey('bildirim-ders-$id'));
        await tester.ensureVisible(kart);
        await tester.tap(kart);
        await bekle();
      }
      expect(find.text('Öğretmene Mesaj At (2)'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Öğretmene Mesaj At (2)'),
          matching: find.byType(ListView),
        ),
        findsNothing,
      );
      // Öğretmeni eşleştirilmemiş ders yanlış alıcıya gönderilemez.
      final eksik = find.byKey(const ValueKey('bildirim-ders-3'));
      await tester.ensureVisible(eksik);
      expect(tester.widget<CheckboxListTile>(eksik).onChanged, isNull);
      expect(find.byTooltip('Öğretmen Eşleştir'), findsOneWidget);
      final hazirla = find.text('Öğretmene Mesaj At (2)');
      await tester.ensureVisible(hazirla);
      await tester.tap(hazirla);
      await bekle();
      final mesaj = tester.widget<MesajlasmaScreen>(
        find.byType(MesajlasmaScreen),
      );
      expect(mesaj.baslangicOgretmenIdleri, {kisi});
      expect(
        mesaj.kaynakKayit,
        startsWith('1:$fid:ogretmen:$kisi:1,2:'),
      );
      expect(mesaj.kaynakKayit!.split(':').last, hasLength(64));
      expect(mesaj.baslangicKisiBaglari, {'Ogretmen:$kisi:1'});
      expect(mesaj.baslangicMetni, contains('101 – Öğrenci1'));
      expect(mesaj.baslangicMetni, contains('102 – Öğrenci2'));
      expect(mesaj.baslangicMetni,
          contains('9/C Sınıfı Matematik dersinizden proje ödevi alan öğrenciler:'));
      expect(mesaj.baslangicMetni,
          contains('9/C Sınıfı Fizik dersinizden proje ödevi alan öğrenciler:'));
      expect('İyi çalışmalar.'.allMatches(mesaj.baslangicMetni!).length, 1);
      expect(mesaj.baslangicMetni, isNot(contains('103 – Öğrenci3')));
      expect(mesaj.yalnizGonderimOnayi, true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  test(
    'birleştirilmiş öğretmen mesajı WhatsApp açar; '
    'değişen atama eski kuyruğu engeller',
    () async {
      const kisi = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await tamDagitim();
      await ogretmenEkle(kisi, 1);
      await s.projeDersOgretmeniEsle(b, 1, fid, 2, {kisi});
      final an = await s.projeAnalizi(b, 1, fid);
      await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
      final paket1 = await s.projeSonucMesaji(b, 1, fid, 1);
      final paket2 = await s.projeSonucMesaji(b, 1, fid, 2);
      final imza = sha256.convert(utf8.encode(jsonEncode([
        [1, paket1['imza']],
        [2, paket2['imza']],
      ]))).toString();
      final kaynak = '1:$fid:ogretmen:$kisi:1,2:$imza';
      final metin = "${paket1['metin']}\n\n---\n\n${paket2['metin']}";
      var whatsappAcildi = 0;
      final ms = MesajlasmaService(
        databaseGetir: () async => db,
        whatsappAc: (telefon, icerik) async {
          whatsappAcildi++;
          expect(telefon, isNotEmpty);
          expect(icerik, contains('101 – Öğrenci1'));
          expect(icerik, contains('102 – Öğrenci2'));
          expect(icerik, isNot(contains('103 – Öğrenci3')));
        },
      );
      final mb = await ms.hazirla();
      final adaylar = await ms.aliciAdaylari(mb, tur: MesajKisiTuru.ogretmen);
      final secim = MesajKisiOnIzleme(
        adaylar.where((k) => k.kisiId == kisi).toList(),
      );
      await expectLater(
        ms.kisilerleKuyrukOlustur(
          mb, secim, metin,
          kaynakModul: 'RehberlikProjeSonuc',
          kaynakKayit: '1:$fid:ogretmen:$kisi',
        ),
        throwsStateError,
      );
      final ilk = await ms.kisilerleKuyrukOlustur(
        mb, secim, metin,
        kaynakModul: 'RehberlikProjeSonuc',
        kaynakKayit: kaynak,
      );
      await ms.aliciyiAc(mb, ilk.id, ilk.alicilar.single.id);
      expect(whatsappAcildi, 1);
      final bekleyen = await ms.kisilerleKuyrukOlustur(
        mb, secim, metin,
        kaynakModul: 'RehberlikProjeSonuc',
        kaynakKayit: kaynak,
      );
      // Sonuç mesajı hazırlandıktan sonra ders öğretmeni değişirse eski
      // kuyruğun gönderim aşamasına geçmesine izin verilmez.
      const digerOgretmen = 'cccccccccccccccccccccccccccccccc';
      await ogretmenEkle(digerOgretmen, 2);
      await s.projeDersOgretmeniEsle(b, 1, fid, 2, {digerOgretmen});
      await expectLater(
        ms.aliciyiAc(mb, bekleyen.id, bekleyen.alicilar.single.id),
        throwsStateError,
      );
      expect(whatsappAcildi, 1);
    },
  );

  test('bekleyen öğretmen mesajı değişen sonuçta gönderilmez', () async {
    const kisi = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await tamDagitim();
    await ogretmenEkle(kisi, 1);
    await ogretmenEkle('cccccccccccccccccccccccccccccccc', 2);
    final an = await s.projeAnalizi(b, 1, fid);
    await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
    final paket = await s.projeSonucMesaji(b, 1, fid, 1);
    var gonderim = 0;
    final ms = MesajlasmaService(
      databaseGetir: () async => db,
      whatsappAc: (_, _) async {
        gonderim++;
      },
    );
    final mb = await ms.hazirla();
    final adaylar = await ms.aliciAdaylari(mb, tur: MesajKisiTuru.ogretmen);
    final kaynak = '1:$fid:1:${paket['imza']}';
    await expectLater(
      ms.kisilerleKuyrukOlustur(
        mb,
        MesajKisiOnIzleme(adaylar.where((k) => k.kisiId != kisi).toList()),
        paket['metin'] as String,
        kaynakModul: 'RehberlikProjeSonuc',
        kaynakKayit: kaynak,
      ),
      throwsStateError,
    );
    final kuyruk = await ms.kisilerleKuyrukOlustur(
      mb,
      MesajKisiOnIzleme(adaylar.where((k) => k.kisiId == kisi).toList()),
      paket['metin'] as String,
      kaynakModul: 'RehberlikProjeSonuc',
      kaynakKayit: kaynak,
    );
    await yanit(1, [2, 1, 3], zaman: '2026-11-17T11:00:00Z');
    await expectLater(
      ms.aliciyiAc(mb, kuyruk.id, kuyruk.alicilar.single.id),
      throwsStateError,
    );
    expect(gonderim, 0);
    expect(
      (await ms.kuyrukGetir(mb, kuyruk.id)).alicilar.single.durum,
      kuyruk.alicilar.single.durum,
    );
  });

  test('sonuçtan sonra değişen cevap veya dağıtım mesajı durdurur', () async {
    await tamDagitim();
    await ogretmenEkle('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1);
    final an = await s.projeAnalizi(b, 1, fid);
    await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
    await yanit(1, [2, 1, 3], zaman: '2026-11-17T11:00:00Z');
    expect((await s.projeAnalizi(b, 1, fid))['sonuclandi'], false);
    await expectLater(s.projeSonucMesaji(b, 1, fid, 1), throwsStateError);
    await expectLater(
      s.projeSonuclandir(b, 1, fid, an['imza'] as String),
      throwsStateError,
    );
  });
  test(
    'öğretmen eşleştirmesi yalnız aynı sınıfı kapsar ve mesaj imzasını değiştirir',
    () async {
      const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          c = 'cccccccccccccccccccccccccccccccc';
      await tamDagitim();
      await ogretmenEkle(a, 1);
      await ogretmenEkle(c, 2);
      final an = await s.projeAnalizi(b, 1, fid);
      await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
      final onceki = await s.projeSonucMesaji(b, 1, fid, 1);
      await s.projeDersOgretmeniEsle(b, 1, fid, 1, {c});
      final yeni = await s.projeSonucMesaji(b, 1, fid, 1);
      expect(yeni['aliciIds'], [c]);
      expect(yeni['imza'], isNot(onceki['imza']));
      await db.insert('SinifSube', {
        'SinifSubeId': 2,
        'SinifKodu': '9/D',
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await ogretmenEkle('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 3, sinifId: 2);
      await expectLater(
        s.projeDersOgretmeniEsle(b, 1, fid, 1, {
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        }),
        throwsStateError,
      );
    },
  );


  test(
    'silinen form proje listesinden çıkar; eski dağıtım ve mesaj kullanılamaz',
    () async {
      await tamDagitim();
      await ogretmenEkle('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1);
      final an = await s.projeAnalizi(b, 1, fid);
      await s.projeSonuclandir(b, 1, fid, an['imza'] as String);
      final kalan = await projeFormu(dersler);
      final ogrenciler = await db.query('Ogrenci');
      await expectLater(
        fs.formuSil(
          fb,
          fid,
          googleTemizle: (_) async {
            throw StateError('Google bağlantı hatası');
          },
        ),
        throwsStateError,
      );
      expect(await s.projeTalepleri(b, 1), hasLength(2));
      await fs.formuSil(fb, fid, googleTemizle: (_) async {});
      expect((await s.projeTalepleri(b, 1)).single['formId'], kalan);
      await expectLater(
        s.projeDagitimOnizle(b, 1, fid, null),
        throwsStateError,
      );
      await expectLater(s.projeSonucMesaji(b, 1, fid, 1), throwsStateError);
      await expectLater(
        db.transaction((tx) => s.projeSonucMesajiniDogrula(tx, b, 1, fid, 1)),
        throwsStateError,
      );
      expect(await db.query('Ogrenci'), ogrenciler);
      expect(await fs.yanitlar(fb, kalan), isEmpty);
    },
  );

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
    'az tercih edilen ders önce işlenir; eşitlikte ders adı belirleyicidir',
    () async {
      // Fizik iki kez, Matematik bir kez birinci tercih edildi.
      await yanit(1, [2, 1, 3]);
      await yanit(2, [1, 2, 3]);
      await yanit(3, [2, 1, 3]);
      await onay();
      final plan = await s.projeDagitimOnizle(b, 1, fid, null);
      expect((plan['dagitim'] as Map).keys.toList(), ['2', '1', '3']);
      expect(plan['dagitim'], {'2': 1, '1': 2, '3': 2});
      expect(plan['kontenjanOnerisi'], isEmpty);
    },
  );
  test(
    'ikinci ve üçüncü tercih turlarında öğrenci yalnız tercihine yerleşir',
    () async {
      await yanit(1, [1, 2, 3]);
      await yanit(2, [1, 2, 3]);
      await yanit(3, [1, 2, 3]);
      await onay();
      final plan = await s.projeDagitimOnizle(
        b, 1, fid, {1: 1, 2: 1, 3: 1},
      );
      expect(plan['dagitim'], {'1': 1, '2': 2, '3': 3});
      expect(plan['acikta'], 0);
      expect(plan['kontenjanOnerisi'], isEmpty);
    },
  );
  test(
    'açıkta kalan için kontenjan önerilir; onaylı artışla yeniden dağıtılır',
    () async {
      await yanit(1, [1, 2, 3]);
      await yanit(2, [1, 2, 3]);
      await yanit(3, [2, 1, 3]);
      await onay();
      final once = await s.projeDagitimOnizle(
        b, 1, fid, {1: 1, 2: 1, 3: 0},
      );
      expect(once['acikta'], 1);
      expect(once['kontenjanOnerisi'], {'1': 1});
      expect(once['dagitim'], {'3': 2, '1': 1});
      expect((await s.projeTalepleri(b, 1)).single['dagitim'], isEmpty);
      final sonra = await s.projeDagitimOnizle(
        b, 1, fid, {1: 2, 2: 1, 3: 0},
      );
      expect(sonra['dagitim'], {'3': 2, '1': 1, '2': 1});
      expect(sonra['acikta'], 0);
      expect(sonra['kontenjanOnerisi'], isEmpty);
      // Ön izleme onaydan önce asıl dağıtım durumunu değiştirmez.
      expect((await s.projeTalepleri(b, 1)).single['dagitim'], isEmpty);
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
  test(
    'temizlenmiş eski ham yanıt mükerrer tercih oluşturmaz',
    () async {
      await yanit(1, [1, 2, 3], id: 'kalan');
      await yanit(1, [2, 1, 3], id: 'silinen');
      expect(
        (await s.projeTercihleri(b, 1, fid)).first['hatalar'],
        contains('Aynı öğrenciye ait birden fazla yanıt var. Ortak formdan inceleyin.'),
      );
      // Eski cihaz kayıtlarında ham temizleme işareti bulunabilir.
      // Bu kayıtlar yanlışlıkla tekrar aktif tercih sayılmamalı.
      await db.update(
        'BilgiToplamaYanit',
        {
          'HamYanit': '{"_yerelTemizlendi":true}',
          'SoruAnlikGoruntusu': '[]',
        },
        where: 'FormId=? AND GoogleYanitId=?',
        whereArgs: [fid, 'silinen'],
      );
      expect(await fs.yanitlar(fb, fid), hasLength(1));
      final rows = await s.projeTercihleri(b, 1, fid);
      expect(rows.first['hatalar'], isEmpty);
      expect(rows.first['bekliyor'], false);
      expect(rows.first['yanitId'], isNotNull);
      expect(
        (await db.query('BilgiToplamaYanit', where: 'FormId=?', whereArgs: [fid])),
        hasLength(2),
      );
    },
  );
  test(
    'Google tam liste ve tekli sorgu çelişirse SQLite korunur',
    () async {
      await yanit(1, [1, 2, 3], id: 'kalan');
      await yanit(1, [2, 1, 3], id: 'silinen');
      final rows = await db.query('BilgiToplamaYanit', where: 'FormId=?',
          whereArgs: [fid]);
      final kalan = jsonDecode(rows.singleWhere(
        (r) => r['GoogleYanitId'] == 'kalan',
      )['HamYanit'] as String);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/responses')) {
          return http.Response(jsonEncode({'responses': [kalan]}), 200);
        }
        if (request.url.path.endsWith('/responses/silinen')) {
          return http.Response(jsonEncode({
            'formId': 'google-proje-form',
            'responseId': 'silinen',
          }), 200);
        }
        return http.Response(jsonEncode({'formId': 'google-proje-form'}), 200);
      });
      addTearDown(client.close);
      await expectLater(
        fs.googleYanitlariniAl(fb, fid, erisimBelirteci: 'test',
            google: RehberlikGoogleFormService(client: client)),
        throwsA(isA<StateError>().having(
          (e) => e.toString(), 'mesaj', contains('uyuşmuyor'))),
      );
      expect(await fs.yanitlar(fb, fid), hasLength(2));
      expect((await s.projeTercihleri(b, 1, fid)).first['hatalar'],
          contains('Aynı öğrenciye ait birden fazla yanıt var. Ortak formdan inceleyin.'));
    },
  );

  test(
    'Google tam liste ve tekli 404 doğrulanırsa eski aktif yanıt temizlenir',
    () async {
      await yanit(1, [1, 2, 3], id: 'kalan');
      await yanit(1, [2, 1, 3], id: 'silinen');
      final rows = await db.query('BilgiToplamaYanit', where: 'FormId=?',
          whereArgs: [fid]);
      final kalan = jsonDecode(rows.singleWhere(
        (r) => r['GoogleYanitId'] == 'kalan',
      )['HamYanit'] as String);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/responses')) {
          return http.Response(jsonEncode({'responses': [kalan]}), 200);
        }
        if (request.url.path.endsWith('/responses/silinen')) {
          return http.Response('{}', 404);
        }
        return http.Response(jsonEncode({'formId': 'google-proje-form'}), 200);
      });
      addTearDown(client.close);
      await fs.googleYanitlariniAl(fb, fid, erisimBelirteci: 'test',
          google: RehberlikGoogleFormService(client: client));
      expect(await fs.yanitlar(fb, fid), hasLength(1));
      final sonuc = await s.projeTercihleri(b, 1, fid);
      expect(sonuc.first['hatalar'], isEmpty);
      expect((await db.query('BilgiToplamaYanit',
          where: 'FormId=?', whereArgs: [fid])), hasLength(2));
    },
  );
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
    'pasif öğrenci yalnız seçili projeden çıkarılır; Google yanıtı ve diğer kayıtlar korunur',
    () async {
      await tamDagitim();
      final oncekiYanitlar = await db.query('BilgiToplamaYanit',
          where: 'FormId=?', whereArgs: [fid]);
      final ogrenciler = await db.query('Ogrenci');
      final kayitlar = await db.query('OgrenciSinifKayit');
      final ikinci = await projeFormu(dersler);
      await expectLater(
        s.projePasifOgrenciyiCikar(b, 1, fid, 2),
        throwsStateError,
      );
      await db.update('OgrenciSinifKayit', {'Aktif': 0},
          where: 'OgrenciId=1 AND SinifSubeId=1');
      await s.projePasifOgrenciyiCikar(b, 1, fid, 1);
      final proje = (await s.projeTalepleri(b, 1))
          .singleWhere((p) => p['formId'] == fid);
      expect(proje['ogrenciler'], [2, 3]);
      expect((proje['onaylar'] as Map).containsKey('1'), isFalse);
      expect((proje['dagitim'] as Map).containsKey('1'), isFalse);
      expect(proje['dagitimOnayli'], false);
      expect(proje['sonuclandi'], false);
      final rows = await s.projeTercihleri(b, 1, fid);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['OgrenciId']).toSet(), {2, 3});
      expect((await s.projeAnalizi(b, 1, fid))['toplam'], 2);
      expect((await s.projeTalepleri(b, 1))
          .singleWhere((p) => p['formId'] == ikinci)['ogrenciler'], [1, 2, 3]);
      expect(await db.query('BilgiToplamaYanit',
          where: 'FormId=?', whereArgs: [fid]), oncekiYanitlar);
      expect(await db.query('Ogrenci'), ogrenciler);
      final yeniKayitlar = await db.query('OgrenciSinifKayit');
      expect(yeniKayitlar.length, kayitlar.length);
      await expectLater(
        s.projePasifOgrenciyiCikar(b, 1, fid, 1),
        throwsStateError,
      );
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
    await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-1')));
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
    expect(
      await db.query('BilgiToplamaYanit', where: 'FormId=?', whereArgs: [fid]),
      hasLength(3),
    );
    await tester.longPress(ilk);
    await bekle();
    expect(find.text('Toplu Onayla (1)'), findsOneWidget);
    expect(find.text('Google Form’da Aç'), findsOneWidget);
    expect(find.text('Google’da Silinmeyi Doğrula'), findsOneWidget);
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
    expect(find.text('Google Form’da Aç'), findsNothing);
    expect(find.text('Google’da Silinmeyi Doğrula'), findsNothing);
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

  testWidgets(
    'Yanıtları Kapat / Aç Google durumunu ve yerel kaydı birlikte günceller',
    (tester) async {
      await yanit(1, [1, 2, 3]);
      final onceki = await fs.yanitlar(fb, fid);
      final g = _ProjeYanitTestGoogle();
      addTearDown(g.dispose);
      Future<void> bekle() async {
        for (var i = 0; i < 50; i++) {
          await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 25),
          ));
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(MaterialApp(
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
      ));
      await bekle();
      await tester.tap(find.text('Sınıfın proje dersleri'));
      await bekle();
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-1')));
      await bekle();
      expect(find.text('Yanıt alımı açık'), findsOneWidget);
      expect(find.text('Yanıtları Kapat'), findsOneWidget);
      await tester.tap(find.text('Yanıtları Kapat'));
      await bekle();
      expect(find.text('Yanıt alımını kapat'), findsOneWidget);
      await tester.tap(find.text('İptal'));
      await bekle();
      expect(g.yanitAlimiIslemleri, isEmpty);
      g.yanitAyarHatali = true;
      await tester.tap(find.text('Yanıtları Kapat'));
      await bekle();
      await tester.tap(find.text('Onayla').last);
      await bekle();
      expect(g.yanitAcik, true);
      expect((await fs.formGetir(fb, fid))['Durum'], 'Aktif');
      g.yanitAyarHatali = false;
      await tester.tap(find.text('Yanıtları Kapat'));
      await bekle();
      await tester.tap(find.text('Onayla').last);
      await bekle();
      expect(g.yanitAcik, false);
      expect(g.yanitAlimiIslemleri, [false]);
      expect((await fs.formGetir(fb, fid))['Durum'], 'Kapali');
      expect(find.text('Yanıt alımı kapalı'), findsOneWidget);
      expect(find.text('Yanıtları Aç'), findsOneWidget);
      expect(await fs.yanitlar(fb, fid), onceki);
      await tester.tap(find.text('Yanıtları Aç'));
      await bekle();
      await tester.tap(find.text('Onayla').last);
      await bekle();
      expect(g.yanitAcik, true);
      expect(g.yanitAlimiIslemleri, [false, true]);
      expect((await fs.formGetir(fb, fid))['Durum'], 'Aktif');
      expect(await fs.yanitlar(fb, fid), onceki);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  Future<void> silmeBaglantisiHazirDegilkenYenilemeyiDogrula(WidgetTester tester) async {
    final g = _IlkSecimGoogle()..okumaHatasi = true;
    addTearDown(g.dispose);
    Future<void> bekle() async {
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(MaterialApp(home: RehberlikProjeOdevScreen(
      service: s, baglam: b, formService: fs, google: g, hesapBagla: () async => 'test',
      atama: const {'RehberlikAtamaId': 1, 'SinifSubeId': 1, 'SinifKodu': '9/C', 'EgitimOgretimYili': '2026/2027'},
    )));
    await bekle();
    await tester.tap(find.text('Proje'));
    await bekle();
    await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-1')));
    await bekle();
    expect(find.textContaining('101 • Öğrenci1'), findsNWidgets(2));
    expect(find.textContaining('Kaydedilmiş yanıtlar görüntüleniyor'), findsOneWidget);
    expect(find.textContaining('İşlem tamamlanamadı'), findsNothing);
    await tester.tap(find.text('Yanıtları Getir'));
    await bekle();
    expect(find.text('Google yanıtları alındı.'), findsOneWidget);
    expect(find.textContaining('101 • Öğrenci1'), findsNWidgets(2));
    await tester.longPress(find.textContaining('101 • Öğrenci1').first);
    await bekle();
    final delete = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Toplu Sil (1)'));
    expect(delete.onPressed, isNull);
    expect(g.ilkSecilenler, isEmpty);
    expect(await tester.runAsync(() => fs.yanitlar(fb, fid)), hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
  testWidgets(
    'ilk seçilen native satır ek seçim olmadan Toplu Sil ile işlenir',
    (tester) async {
      await yanit(1, [1, 2, 3], id: 'rest-old');
      await yanit(1, [1, 2, 3], id: 'rest-new');
      await silmeBaglantisiHazirDegilkenYenilemeyiDogrula(tester);
      final once = await db.query('BilgiToplamaYanit');
      final g = _IlkSecimGoogle();
      addTearDown(g.dispose);
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> bekle() async {
        for (var i = 0; i < 50; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: RehberlikProjeOdevScreen(
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
        ),
      );
      await bekle();
      await tester.tap(find.text('Proje'));
      await bekle();
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-1')));
      await bekle();
      expect(
        find.byKey(const ValueKey('google-yanit-native-old')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('google-yanit-native-new')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('google-yanit-native-old')));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(const ValueKey('google-yanit-native-old')),
      );
      await bekle();
      await tester.tap(find.text('Toplu Sil (1)'));
      await bekle();
      expect(find.text('Seçili yanıtları sil'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Onayla'));
      await bekle();
      expect(g.ilkSecilenler, ['native-old']);
      expect(
        find.byKey(const ValueKey('google-yanit-native-old')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('google-yanit-native-new')),
        findsOneWidget,
      );
      // Eski REST kayıtları benzerlikle dönüştürülmez. Gerçek serviste bunları
      // ayrı GET 404 doğrulaması temizler; bu ekran taklidi kayıtları değiştirmez.
      expect(await db.query('BilgiToplamaYanit'), once);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  Future<void> sonucEkraniniDogrula(
    WidgetTester tester,
    GlobalKey key,
    Future<void> Function(String) capture,
  ) async {
    final onceki = fid;
    var hazir = false;
    final hazirlik = () async {
      try {
        fid = await projeFormu(dersler);
        final qs = await fs.sorular(fb, fid);
        await fs.googleBagla(fb, fid, 'sonuclandirma-form', {
          for (final q in qs) q['AlanAnahtari'] as String: 'q${q['Id']}',
        });
        await yanit(1, [1, 2, 3]);
        await yanit(2, [2, 1, 3]);
        await yanit(3, [3, 1, 2]);
        await onay();
        await ogretmenEkle('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1);
      } finally {
        hazir = true;
      }
    }();
    for (var i = 0; i < 100 && !hazir; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
    expect(hazir, true);
    await hazirlik;
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
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
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff1675ed),
            ),
            fontFamily: 'NotoSans',
          ),
          home: RehberlikProjeOdevScreen(
            service: s,
            baglam: b,
            formService: fs,
            atama: const {
              'RehberlikAtamaId': 1,
              'SinifSubeId': 1,
              'SinifKodu': '9/C',
              'EgitimOgretimYili': '2026/2027',
            },
          ),
        ),
      ),
    );
    await bekle();
    await tester.tap(find.text('Sınıfın proje dersleri'));
    await bekle();
    await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-3')));
    await bekle();
    expect(find.text('Dağıtım Kriterleri'), findsOneWidget);
    await capture('400-5-degerlendirme-hazir');
    expect(find.text('Kontenjan kullan'), findsNothing);
    await tester.tap(find.text('Dağıtım Kriterleri'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Kontenjan kullan'),
          )
          .value,
      true,
    );
    expect(
      tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((a) => a.initialValue),
      ['3', '3', '3'],
    );
    for (var i = 0; i < 3; i++) {
      final alan = find.byType(TextFormField).at(i);
      await tester.ensureVisible(alan);
      await tester.enterText(alan, '1');
      await tester.pump();
    }
    expect(find.text('Toplam kapasite: 3'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    await capture('400-yeni-degerlendirme-kriterler');
    await tester.tap(find.text('Otomatik Dağıt'));
    await bekle();
    expect(find.text('Ders Dağılımı'), findsOneWidget);
    expect(
      find.text('3 öğrenci yerleştirildi. 0 yanıt kontrol bekliyor.'),
      findsOneWidget,
    );
    await capture('400-yeni-degerlendirme-otomatik');
    await tester.tap(find.text('Manuel Düzenle'));
    await bekle();
    expect(find.text('Manuel Düzenleme'), findsOneWidget);
    final ilkSecim = find.byKey(const ValueKey('manuel-1-1'));
    await tester.ensureVisible(ilkSecim);
    await tester.pumpAndSettle();
    final alan = tester.widget<DropdownButtonFormField<int>>(ilkSecim);
    // Dolu seçenekler kullanıcı arayüzünde de seçilemez.
    final dropdown = tester.widget<DropdownButton<int>>(
      find.descendant(of: ilkSecim, matching: find.byType(DropdownButton<int>)),
    );
    expect(alan.initialValue, 1);
    expect(dropdown.items!.where((e) => e.value == 2).single.enabled, false);
    expect(dropdown.items!.where((e) => e.value == 3).single.enabled, false);
    await capture('400-yeni-degerlendirme-manuel');
    final ikinciSecim = find.byKey(const ValueKey('manuel-2-2'));
    await tester.ensureVisible(ikinciSecim);
    await tester.tap(ikinciSecim);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Yerleştirme yok').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(ilkSecim);
    await tester.tap(ilkSecim);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Fizik — 1 boş yer').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('manuel-1-2')), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await bekle();
    await tester.tap(find.text('Manuel Düzenle'));
    await bekle();
    expect(find.byKey(const ValueKey('manuel-1-1')), findsOneWidget);
    await tester.tap(find.text('Ön İzlemeye Uygula'));
    await bekle();
    await tester.tap(find.text('Dağıtımı Onayla'));
    await bekle();
    await tester.tap(find.text('Onayla').last);
    await tester.pump(const Duration(milliseconds: 300));
    await bekle();
    final kayit = (await s.projeTalepleri(
      b,
      1,
    )).singleWhere((p) => p['formId'] == fid);
    expect(kayit['kontenjan'], {'1': 1, '2': 1, '3': 1});
    expect(kayit['dagitim'], {'1': 1, '2': 2, '3': 3});
    final sonucDugmesi = find.widgetWithText(
      FilledButton, 'Proje Seçimini Sonuçlandır',
    ).first;
    await tester.ensureVisible(sonucDugmesi);
    await tester.tap(sonucDugmesi);
    await bekle();
    await tester.tap(find.text('Onayla').last);
    await bekle();
    expect((await s.projeAnalizi(b, 1, fid))['sonuclandi'], true);
    await capture('400-5-degerlendirme-sonuc');
    // Kesin sonuç ve tek düğmeli ders bazlı bilgilendirme.
    await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-4')));
    await bekle();
    await tester.tap(find.text('Ders Bazlı'));
    await bekle();
    final ders = find.byKey(const ValueKey('bildirim-ders-1'));
    await tester.ensureVisible(ders);
    await tester.tap(ders);
    await bekle();
    expect(find.text('Öğretmene Mesaj At (1)'), findsOneWidget);
    final mesaj = find.text('Öğretmene Mesaj At (1)');
    await tester.ensureVisible(mesaj);
    await tester.tap(mesaj);
    await bekle();
    expect(find.byType(MesajlasmaScreen), findsOneWidget);
    final ekran = tester.widget<MesajlasmaScreen>(
      find.byType(MesajlasmaScreen),
    );
    expect(ekran.baslangicKisiBaglari, {
      'Ogretmen:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:1',
    });
    expect(ekran.baslangicMetni, contains('101 – Öğrenci1'));
    expect(ekran.baslangicMetni, isNot(contains('Öğrenci2')));
    expect(ekran.yalnizGonderimOnayi, true);
    expect(tester.takeException(), isNull);
    for (
      var i = 0;
      i < 100 &&
          find.text('Düzelt').evaluate().isEmpty &&
          find.text('Gönderim başlatılamadı').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Gönderim başlatılamadı'),
      findsNothing,
      reason: find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .join(' | '),
    );
    expect(find.text('Mesajı gönder'), findsOneWidget);
    await tester.tap(find.text('Düzelt').last);
    for (
      var i = 0;
      i < 100 && find.byType(MesajlasmaScreen).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
    await bekle();
    expect(find.byType(MesajlasmaScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    fid = onceki;
  }

  Future<void> anaListeyiDogrula(
    WidgetTester tester,
    GlobalKey key,
    Future<void> Function(String) capture,
  ) async {
    final g = _ProjeYanitTestGoogle();
    final diger =
        (await s.projeTalepleri(
              b,
              1,
            )).firstWhere((p) => p['formId'] != fid)['formId']
            as int;
    final ogrenciKayitlari = await db.query('Ogrenci');
    Future<void> bekle() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
        if (find.byType(AlertDialog).evaluate().isNotEmpty ||
            find.byType(SimpleDialog).evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 300));
          return;
        }
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    for (final width in [320.0, 400.0]) {
      tester.view.physicalSize = Size(width, 850);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'NotoSans'),
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
              ),
              child: RehberlikProjeOdevScreen(
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
          ),
        ),
      );
      await bekle();
      await capture('${width.toInt()}-ana-proje-listesi');
      expect(find.byKey(const ValueKey('proje-ana-dagitim')), findsNothing);
      await tester.tap(find.text('Proje'));
      await bekle();
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-3')));
      await bekle();
      expect(find.text('Dağıtım Kriterleri'), findsOneWidget);
      await tester.tap(find.byTooltip('Proje taleplerine dön'));
      await bekle();
      final form = find.byKey(ValueKey('proje-form-$fid'));
      final gesture = await tester.startGesture(
        tester.getCenter(form),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await bekle();
      expect(find.text('Seçilenleri Sil (1)'), findsOneWidget);
      expect(find.text('Dağıtım Kriterleri'), findsNothing);
      await capture('${width.toInt()}-ana-form-secimi');
      await tester.tap(find.text('Tümünü seç (1/2)'));
      await bekle();
      expect(find.text('Seçilenleri Sil (2)'), findsOneWidget);
      await tester.tap(find.text('Seçilenleri Sil (2)'));
      await bekle();
      expect(find.text('Seçili proje formlarını sil'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('İptal'));
      await bekle();
      expect(g.silinenFormlar, isEmpty);
      if (width == 320) {
        await tester.tap(find.byTooltip('Proje taleplerine dön'));
        await bekle();
        expect(find.text('Seçilenleri Sil (2)'), findsNothing);
        expect(find.byKey(const ValueKey('proje-ana-dagitim')), findsNothing);
      } else {
        g.hataliFormlar.add(diger);
        await tester.tap(find.text('Seçilenleri Sil (2)'));
        await bekle();
        await tester.tap(find.text('Onayla').last);
        await tester.pump(const Duration(milliseconds: 300));
        await bekle();
        expect(g.silinenFormlar, [fid]);
        expect(
          find.textContaining('1 form silindi; 1 form kaldı.'),
          findsOneWidget,
          reason: find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .join(' | '),
        );
        expect(find.byKey(ValueKey('proje-form-$fid')), findsNothing);
        expect(find.byKey(ValueKey('proje-form-$diger')), findsOneWidget);
        expect(find.text('Seçilenleri Sil (1)'), findsOneWidget);
        g.hataliFormlar.clear();
        await tester.tap(find.text('Seçilenleri Sil (1)'));
        await bekle();
        await tester.tap(find.text('Onayla').last);
        await tester.pump(const Duration(milliseconds: 300));
        await bekle();
        expect(
          find.text('Henüz proje formu yok. Yeni form talebi oluşturun.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('proje-ana-dagitim')), findsNothing);
        expect(await db.query('Ogrenci'), ogrenciKayitlari);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
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
                google: _ProjeYanitTestGoogle(),
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
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-1')));
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
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-0')));
      await bekle();
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-3')));
      await bekle();
      expect(find.text('Dağıtım Kriterleri'), findsOneWidget);
      await capture('${width.toInt()}-5-degerlendirme');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Manuel Dağıt'));
      await bekle();
      expect(find.text('Manuel Düzenleme'), findsOneWidget);
      await capture('${width.toInt()}-yeni-degerlendirme-manuel');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Vazgeç'));
      await bekle();
      await tester.tap(find.byKey(const ValueKey('proje-ust-sekme-0')));
      await bekle();
      for (final (i, ad) in [
        (0, 'Özet'),
        (1, 'Yanıtlar'),
        (2, 'Onay / Düzenleme'),
        (3, 'Dağıtım / Yazdırma'),
        (4, 'Bilgilendirme'),
      ]) {
        final sekme = find.byKey(ValueKey('proje-ust-sekme-$i'));
        await tester.ensureVisible(sekme);
        await tester.tap(sekme);
        await bekle();
        expect(tester.takeException(), isNull);
        if (i == 2) {
          expect(find.text('Düzenle'), findsNothing);
          expect(find.text('Google Yanıtlarını Yenile'), findsOneWidget);
          expect(find.text('Geçerlileri seç'), findsOneWidget);
          expect(find.textContaining('Onayla ('), findsWidgets);
        }
        if (i == 3) {
          expect(find.text('Dağıtım Kriterleri'), findsOneWidget);
        }
        if (i == 4 && (await s.projeAnalizi(b, 1, fid))['yerlesen'] != 0) {
          expect(find.text('Öğrenci Bazlı'), findsOneWidget);
          expect(find.text('Ders Bazlı'), findsOneWidget);
        }
        await capture('${width.toInt()}-${i + 4}-$ad');
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
    await sonucEkraniniDogrula(tester, key, capture);
    await yanitIslemleriniDogrula(tester);
    await anaListeyiDogrula(tester, key, capture);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.runAsync(() => temp!.delete(recursive: true));
  });
}
