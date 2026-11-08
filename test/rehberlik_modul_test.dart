import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/rehberlik_belge_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_rehberlik_dosyasi_screen.dart';
import 'package:elpi_okul_yonetim/screens/rehberlik_tanima_form_screen.dart';
import 'package:elpi_okul_yonetim/screens/mesaj_form_screen.dart';
import 'package:elpi_okul_yonetim/screens/ogretmen_gorus_form_screen.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/screens/rehberlik_kayit_editor.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const bool.fromEnvironment('TOPLANTI_GORSEL')) {
      await (FontLoader(
        'NotoSans',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  late Database db;
  late BireyselRehberlikService s;
  late BireyselRehberlikBaglami b;
  late Directory temp;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    temp = await Directory.systemTemp.createTemp('rehberlik_modul_');
    s = BireyselRehberlikService.instance;
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
    for (var i = 1; i <= 2; i++) {
      await db.insert('SinifSube', {
        'SinifKodu': '9/$i',
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'SinifSubeId': i,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ogrenci', {
        'OkulNo': '$i',
        'Ad': 'Öğrenci$i',
        'Soyad': 'Test',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': i,
        'SinifSubeId': i,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('RehberlikAtama', {
        'OkulId': 'okul',
        'OgretmenProfilId': 1,
        'SinifSubeId': i,
        'EgitimOgretimYili': '2026/2027',
        'BaslangicTarihi': '2000-01-01',
        'OlusturmaTarihi': 'test',
      });
    }
    b = await s.hazirla();
  });
  tearDown(() async {
    await LocalDatabase.instance.close();
    await temp.delete(recursive: true);
  });
  test(
    'Google Form davet kodu yalnız öğrenciyle eşleşir ve tekrar onay reddedilir',
    () async {
      await s.googleFormKimliginiKaydet(b, 1, 'form-test-001');
      final kod = await s.googleDavetKoduUret(b, 1, 1);
      expect(kod, hasLength(32));
      final davetler = await db.query('RehberlikFormDavet');
      expect(davetler, hasLength(1));
      expect(davetler.single['KodOzeti'], isNot(kod));
      expect(await s.googleDavetKoduDogrula(b, 1, 1, kod), isPositive);
      await expectLater(
        s.googleDavetKoduDogrula(b, 1, 2, kod),
        throwsStateError,
      );
      await s.formKaydet(
        b,
        1,
        1,
        ['Eski soru'],
        {'Eski soru': 'Korunacak'},
        hassasOnay: true,
      );
      final fisId = await s.googleYanitiOnayla(b, 1, 'response-test-1', 1, {
        'Öğrenci davet kodu': kod,
        'Özel soru': 'Yanıt',
      });
      expect(fisId, isPositive);
      final kayit = (await db.query('RehberlikForm', orderBy: 'Id DESC')).first;
      final cevaplar = jsonDecode(kayit['Cevaplar'] as String) as Map;
      expect(cevaplar['Özel soru'], 'Yanıt');
      expect(cevaplar['Eski soru'], 'Korunacak');
      expect(cevaplar.containsKey('Öğrenci davet kodu'), isFalse);
      expect(
        (await db.query('RehberlikGoogleYanit')).single['Durum'],
        'Onaylandi',
      );
      await expectLater(
        s.googleYanitiOnayla(b, 1, 'response-test-1', 1, {
          'Öğrenci davet kodu': kod,
          'Özel soru': 'Yanıt',
        }),
        throwsStateError,
      );
      expect(await db.query('RehberlikForm'), hasLength(2));
    },
  );

  test('Toplu davet var olan kodu degistirmez ve yeniden olusturmaz', () async {
    await s.googleFormKimliginiKaydet(b, 1, 'form-batch-1');
    final ilk = await s.googleTopluDavetHazirla(b, 1, [1]);
    expect(ilk.keys, contains(1));
    final oncekiSatir = (await db.query('RehberlikFormDavet')).single;
    final tekrar = await s.googleTopluDavetHazirla(b, 1, [1]);
    expect(tekrar, isEmpty);
    final sonrakiSatir = (await db.query('RehberlikFormDavet')).single;
    expect(sonrakiSatir['KodOzeti'], oncekiSatir['KodOzeti']);
    expect(await s.googleDavetKoduDogrula(b, 1, 1, ilk[1]!), isPositive);
    expect(await s.googleYanitOgrenciAdayi(b, 1, ilk[1]!), 1);
    expect(await s.googleYanitOgrenciAdayi(b, 1, 'yanlis'), isNull);
    await expectLater(s.googleTopluDavetHazirla(b, 1, [2]), throwsStateError);
    expect(await db.query('RehberlikFormDavet'), hasLength(1));
  });

  test('Google Form davet şablonu öğrenci koduyla doldurulur', () async {
    const sablon =
        'https://docs.google.com/forms/d/e/test/viewform'
        '?usp=pp_url&entry.123=OKUL_DAVET_KODU';
    final link = s.googleDavetBaglantisi(sablon, 'abc123');
    expect(Uri.parse(link).queryParameters['entry.123'], 'abc123');
    await s.googleDavetSablonuKaydet(b, 1, sablon);
    expect(await s.googleDavetSablonuGetir(b, 1), sablon);
    expect(
      () => s.googleDavetBaglantisi(
        'https://example.com/viewform?entry.123=OKUL_DAVET_KODU',
        'abc123',
      ),
      throwsFormatException,
    );
  });

  Future<int> kayit({
    int atama = 1,
    String tur = 'Gorev',
    bool hassas = false,
  }) => s.kayitKaydet(
    b,
    atama,
    tur: tur,
    baslik: 'Örnek kayıt',
    hassas: hassas,
    hassasOnay: hassas,
    icerik: {'aciklama': 'Açıklama'},
  );

  test(
    'Toplantı, karar takibi ve plan faaliyeti aynı atamada bağlanır',
    () async {
      final t = await kayit(tur: 'Toplanti'),
          g = await kayit(),
          dis = await kayit(atama: 2);
      await s.bagla(b, 1, t, g);
      await s.bagla(b, 1, t, g);
      expect(await s.baglar(b, 1), hasLength(1));
      await expectLater(s.bagla(b, 1, t, dis), throwsStateError);
      await expectLater(s.bagla(b, 1, t, t), throwsFormatException);
      await s.kayitKaydet(
        b,
        1,
        id: g,
        tur: 'Gorev',
        baslik: 'Takip',
        durum: 'Tamamlandi',
        tarih: '2026-10-11',
        icerik: {'sonuc': 'Karar uygulandı'},
      );
      expect(
        (await s.kayitlar(b, 1)).firstWhere((r) => r['Id'] == g)['Durum'],
        'Tamamlandi',
      );
    },
  );
  test('Kapsam dışı öğrenci, eski atama ve hatalı kayıt reddedilir', () async {
    await expectLater(
      s.kayitKaydet(b, 1, tur: 'Gorev', baslik: 'x', ogrenciId: 2),
      throwsStateError,
    );
    await expectLater(
      s.kayitKaydet(b, 1, tur: 'Gorev', baslik: 'x', tarih: '2026-02-30'),
      throwsFormatException,
    );
    await expectLater(
      s.kayitKaydet(b, 1, tur: 'Bilinmeyen', baslik: 'x'),
      throwsFormatException,
    );
    final id = await kayit();
    await db.update('RehberlikAtama', {
      'BitisTarihi': '2000-02-01',
    }, where: 'RehberlikAtamaId=1');
    expect(await s.kayitlar(b, 1), hasLength(1));
    await expectLater(kayit(), throwsStateError);
    await expectLater(
      s.kayitKaydet(b, 2, id: id, tur: 'Gorev', baslik: 'y'),
      throwsStateError,
    );
  });
  group('Tanıma fişinde değişmeyen kayıt', () {
    Future<int> form({
      int atama = 1,
      int ogrenci = 1,
      List<String> sorular = const ['Soru', 'Ek soru'],
      Map<String, String> cevaplar = const {'Soru': 'İlk', 'Ek soru': ''},
      bool hassasOnay = true,
    }) => s.formKaydet(
      b,
      atama,
      ogrenci,
      sorular,
      cevaplar,
      hassasOnay: hassasOnay,
    );

    test('Aynı içerik Id, tarih ve eski JSON içeriğini korur', () async {
      final id = await form();
      final once = await db.query('RehberlikForm');
      expect(await form(), id);
      expect(await form(cevaplar: {'Ek soru': '', 'Soru': 'İlk'}), id);
      expect(await form(cevaplar: {'Soru': 'İlk'}), id);
      expect(await db.query('RehberlikForm'), once);
    });

    test('Eksik cevaba boş metin eklenmesi sürüm oluşturmaz', () async {
      final id = await form(cevaplar: {'Soru': 'İlk'});
      expect(await form(), id);
      final rows = await s.formlar(b, 1, 1, hassasOnay: true);
      expect(rows, hasLength(1));
      expect(jsonDecode(rows.single['Cevaplar'] as String), {'Soru': 'İlk'});
    });

    test(
      'Gerçek değişiklik, silme ve eski cevaba dönüş ayrı sürümlerdir',
      () async {
        final ilk = await form();
        final yeni = await form(cevaplar: {'Soru': 'Yeni'});
        final donus = await form();
        final silme = await form(cevaplar: {});
        expect({ilk, yeni, donus, silme}, hasLength(4));
        expect(await form(cevaplar: {'Soru': '', 'Ek soru': ''}), silme);
        final rows = await s.formlar(b, 1, 1, hassasOnay: true);
        expect(rows.map((r) => r['Id']), [silme, donus, yeni, ilk]);
        expect(jsonDecode(rows.last['Cevaplar'] as String)['Soru'], 'İlk');
        expect(await form(cevaplar: {'Soru': ' '}), isNot(silme));
      },
    );

    test('Soru ekleme ve sıralama değişikliği korunur', () async {
      final ilk = await form();
      final sirali = await form(sorular: ['Ek soru', 'Soru']);
      final ekli = await form(sorular: ['Ek soru', 'Soru', 'Yeni soru']);
      expect({ilk, sirali, ekli}, hasLength(3));
      expect(await form(sorular: ['Ek soru', 'Soru', 'Yeni soru']), ekli);
    });

    test('Aynı içerik başka öğrenci veya atamayla birleştirilmez', () async {
      final ilk = await form();
      await db.insert('OgrenciSinifKayit', {
        'OgrenciId': 2,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      final ogrenci = await form(ogrenci: 2);
      final atama = await form(atama: 2, ogrenci: 2);
      expect({ilk, ogrenci, atama}, hasLength(3));
      expect(await form(), ilk);
      expect(await form(ogrenci: 2), ogrenci);
      expect(await form(atama: 2, ogrenci: 2), atama);
      expect(await db.query('RehberlikForm'), hasLength(3));
    });

    test(
      'Aynı içerikte hassas erişim, üyelik ve yıl kontrolü atlanmaz',
      () async {
        await form();
        final once = await db.query('RehberlikForm');
        await expectLater(form(hassasOnay: false), throwsStateError);
        await expectLater(form(ogrenci: 2), throwsStateError);
        await db.update('OgrenciSinifKayit', {
          'Aktif': 0,
        }, where: 'OgrenciId=1');
        await expectLater(form(), throwsStateError);
        await db.update('OgrenciSinifKayit', {
          'Aktif': 1,
        }, where: 'OgrenciId=1');
        await db.insert('OgretmenProfil', {
          'OgretmenProfilId': 2,
          'AdSoyad': 'Diğer öğretmen',
          'OkulAdi': 'Okul',
          'EgitimOgretimYili': '2026/2027',
          'Aktif': 0,
          'OlusturmaTarihi': 'test',
        });
        await db.update('RehberlikAtama', {
          'OgretmenProfilId': 2,
        }, where: 'RehberlikAtamaId=1');
        await expectLater(form(), throwsStateError);
        await db.update('RehberlikAtama', {
          'OgretmenProfilId': 1,
        }, where: 'RehberlikAtamaId=1');
        await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
        await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
        await expectLater(form(), throwsStateError);
        b = await s.hazirla();
        await expectLater(form(), throwsStateError);
        expect(await s.formlar(b, 1, 1, hassasOnay: true), once);
      },
    );

    test('Eşzamanlı aynı kayıtlar yalnız tek sürüm oluşturur', () async {
      final ids = await Future.wait([form(), form(), form()]);
      expect(ids.toSet(), hasLength(1));
      expect(await db.query('RehberlikForm'), hasLength(1));
    });
  });

  test('Hassas kayıt maskelenir; form sürümleri değiştirilmez', () async {
    await kayit(hassas: true);
    expect((await s.kayitlar(b, 1)).single['Icerik'], '{}');
    expect(
      (await s.kayitlar(b, 1, hassasOnay: true)).single['Icerik'],
      contains('Açıklama'),
    );
    await expectLater(
      s.formKaydet(b, 1, 1, ['Soru'], {'Soru': 'Cevap'}, hassasOnay: false),
      throwsStateError,
    );
    await s.formKaydet(b, 1, 1, ['Soru'], {'Soru': 'İlk'}, hassasOnay: true);
    await s.formKaydet(
      b,
      1,
      1,
      ['Soru', 'Ek soru'],
      {'Soru': 'Yeni'},
      hassasOnay: true,
    );
    final f = await s.formlar(b, 1, 1, hassasOnay: true);
    expect(f, hasLength(2));
    expect(f.last['Cevaplar'], contains('İlk'));
    await expectLater(s.formlar(b, 1, 2, hassasOnay: true), throwsStateError);
    await expectLater(s.formlar(b, 1, 1, hassasOnay: false), throwsStateError);
  });
  test(
    'Plan aynı haftanın iki satırını korur; tekrar import tamamlanmış faaliyeti silmez',
    () async {
      final t = s.planImportTanimi(b, 1);
      final p = await t.hazirla([
        ImportKaynakSatiri('a', '1', {
          'hafta': '1',
          'tarih': '7-11 Eylül',
          'saat': '1',
          'konu': 'Veli toplantısı',
        }),
        ImportKaynakSatiri('b', '2', {
          'hafta': '1',
          'tarih': '7-11 Eylül',
          'saat': '1',
          'konu': 'Öğrenci bilgi formu',
        }),
        ImportKaynakSatiri('c', '3', {'hafta': '', 'konu': 'hatalı'}),
      ]);
      expect(p.kayitlar.last.durum, ImportDurumu.hatali);
      expect((await t.aktar(p, {'a', 'b'})).eklenen, 2);
      final rows = await s.kayitlar(b, 1);
      final plan = rows.first;
      final faaliyet = await kayit(tur: 'Toplanti');
      await s.bagla(b, 1, plan['Id'] as int, faaliyet);
      await s.kayitKaydet(
        b,
        1,
        id: faaliyet,
        tur: 'Toplanti',
        baslik: 'Yapıldı',
        durum: 'Tamamlandi',
      );
      expect((await t.aktar(p, {'a', 'b'})).atlanan, 2);
      expect(await s.kayitlar(b, 1), hasLength(3));
      expect(await s.baglar(b, 1), hasLength(1));
      expect(jsonDecode(plan['Icerik'] as String)['hedef'], 'Toplanti');
    },
  );
  test(
    'Ortak görüş talebi sınıf geneli ve çok öğrencili cevapları taşır',
    () async {
      final m = MesajlasmaService.instance,
          mb = await MesajlasmaService.instance.hazirla();
      final id = await m.formOlustur(
        mb,
        kaynakModul: 'SinifRehberligim',
        kaynakKayit: 'atama:1',
        baslik: 'Görüş',
        aliciTuru: 'Ogretmen',
        ogrenciIdleri: {1, 2},
        sinifGeneli: true,
        soru: 'Değerlendiriniz',
      );
      final yanitId = 'a' * 32;
      await m.cevapKaydet(mb, id, 'Öğretmen', 'Genel görüş', {
        '1': 'Bireysel 1',
        '2': 'Bireysel 2',
      }, cevapId: yanitId);
      await m.cevapKaydet(mb, id, 'Öğretmen', 'Genel görüş', {
        '1': 'Bireysel 1',
        '2': 'Bireysel 2',
      }, cevapId: yanitId);
      expect(await m.cevaplariGetir(mb, id), hasLength(1));
      await expectLater(
        m.cevapKaydet(mb, id, 'Öğretmen', '', {'999': 'Kapsam dışı'}),
        throwsStateError,
      );
      expect(await m.formMetni(mb, id), contains('Öğrenci1'));
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await expectLater(m.cevaplariGetir(mb, id), throwsStateError);
    },
  );
  test('PDF ve BelgeId bağlantısı yedek geri yüklemede korunur', () async {
    final id = await kayit(tur: 'Toplanti');
    final belgeService = BireyselBelgeService(
      databaseGetir: () async => db,
      alanGetir: () async => temp,
      modGetir: () async => CalismaModu.bireyselOgretmen,
    );
    final belgeId = await RehberlikBelgeService.arsiveKaydet(
      s,
      b,
      1,
      '9/1',
      (await s.kayitlar(b, 1)).single,
      belgeService: belgeService,
    );
    final bakim = BireyselBakimService(
      databaseGetir: () async => db,
      alanGetir: () async => temp,
      modGetir: () async => CalismaModu.bireyselOgretmen,
    );
    final arsiv = (await db.query('BelgeArsivi')).single['ArsivId'];
    final yedek = await bakim.yedekle();
    await bakim.geriYukle(
      await bakim.incele(yedek.dosya),
      onayMetni: 'GERİ YÜKLE',
    );
    final r = (await s.kayitlar(b, 1)).single;
    expect(r['Id'], id);
    expect(r['BelgeId'], belgeId);
    expect((await s.bagliBelgeGetir(b, 1, id))['BelgeId'], belgeId);
    expect((await db.query('BireyselBelge')).single['BelgeId'], belgeId);
    expect((await db.query('BelgeArsivi')).single['ArsivId'], isNot(arsiv));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test('Hassas kayıt PDF üretimine alınmaz', () async {
    await kayit(hassas: true);
    await expectLater(
      RehberlikBelgeService.pdfOlustur(
        b,
        '9/1',
        (await s.kayitlar(b, 1, hassasOnay: true)).single,
      ),
      throwsStateError,
    );
  });
  test(
    'Sıfırlama rehberlik bağımlılıklarını temizler, ortak görüş geçmişini korur',
    () async {
      await kayit();
      await s.formKaydet(b, 1, 1, ['s'], {'s': 'c'}, hassasOnay: true);
      final m = MesajlasmaService.instance,
          mb = await MesajlasmaService.instance.hazirla();
      await m.formOlustur(
        mb,
        kaynakModul: 'SinifRehberligim',
        kaynakKayit: 'atama:1',
        baslik: 'G',
        aliciTuru: 'Veli',
        ogrenciIdleri: {1},
        sinifGeneli: true,
        soru: 'S',
      );
      await LocalDatabase.instance.bireyselVerileriSifirla(
        onayMetni: 'SIFIRLA',
      );
      expect(await db.query('RehberlikKayit'), isEmpty);
      expect(await db.query('RehberlikForm'), isEmpty);
      expect(await db.query('MesajForm'), hasLength(1));
    },
  );
  test(
    'Sınıf ek soruları tekrar kullanılır, başka sınıfa ve önceki forma taşmaz',
    () async {
      await s.formKaydet(
        b,
        1,
        1,
        ['İlk soru'],
        {'İlk soru': 'Önceki cevap'},
        hassasOnay: true,
      );
      await s.formSorulariniKaydet(b, 1, [
        ...mebTanimaSorulari,
        'Yeni ek soru',
      ]);
      expect(await s.formSorulari(b, 1), contains('Yeni ek soru'));
      expect(await s.formSorulari(b, 2), isNot(contains('Yeni ek soru')));
      expect(
        (await s.formlar(b, 1, 1, hassasOnay: true)).single['Sorular'],
        jsonEncode(['İlk soru']),
      );
    },
  );
  test(
    'Word rehberlik tablosunda birleşik hafta hücresi satırları birleştirmez',
    () async {
      String cell(String s, {String? merge}) =>
          '<w:tc>${merge == null ? '' : '<w:tcPr><w:vMerge ${merge.isEmpty ? '' : 'w:val="$merge"'}/></w:tcPr>'}<w:p><w:r><w:t>$s</w:t></w:r></w:p></w:tc>';
      final xml =
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:tbl>'
          '<w:tr>${['Tarih', 'Hafta', 'Saat', 'Konu'].map(cell).join()}</w:tr>'
          '<w:tr>${cell('7-11 Eylül')}${cell('1', merge: 'restart')}${cell('1')}${cell('Veli toplantısı')}</w:tr>'
          '<w:tr>${cell('7-11 Eylül')}${cell('', merge: '')}${cell('1')}${cell('Bilgi formu')}</w:tr>'
          '</w:tbl></w:body></w:document>';
      final raw = utf8.encode(xml);
      final zip = Archive()
        ..addFile(ArchiveFile('word/document.xml', raw.length, raw));
      final file = ImportDosya(
        'plan.docx',
        Uint8List.fromList(ZipEncoder().encode(zip)!),
      );
      final tanim = s.planImportTanimi(b, 1);
      final p = await tanim.ozelOku!(file);
      expect(p.kayitlar, hasLength(2));
      expect(p.kayitlar.map((r) => r.degerler['hafta']), everyElement('1'));
      expect(
        (await tanim.aktar(p, p.kayitlar.map((r) => r.id).toSet())).eklenen,
        2,
      );
    },
  );
  test('Ortak cevap şablonu ve bozuk/yanlış talepli dosya kontrolü', () async {
    final m = MesajlasmaService.instance,
        mb = await MesajlasmaService.instance.hazirla();
    final id = await m.formOlustur(
      mb,
      kaynakModul: 'SinifRehberligim',
      kaynakKayit: '1',
      baslik: 'x',
      aliciTuru: 'Veli',
      ogrenciIdleri: {1},
      sinifGeneli: true,
      soru: 's',
    );
    final text = await m.cevapSablonu(mb, id);
    final raw = MesajFormIslemleri.cevapDosyasiOku(text, id);
    raw['yanitlayan'] = 'Veli';
    raw['sinifGorusu'] = 'Genel';
    raw['ogrenciGorusleri'] = {'1': 'Öğrenci görüşü'};
    await m.cevapKaydet(
      mb,
      id,
      raw['yanitlayan'] as String,
      raw['sinifGorusu'] as String,
      Map<String, String>.from(raw['ogrenciGorusleri'] as Map),
      cevapId: raw['cevapId'] as String,
    );
    expect(await m.cevaplariGetir(mb, id), hasLength(1));
    expect(
      () => MesajFormIslemleri.cevapDosyasiOku(text, 'yanlis'),
      throwsFormatException,
    );
    expect(
      () => MesajFormIslemleri.cevapDosyasiOku('{}', id),
      throwsFormatException,
    );
  });
  testWidgets(
    'Tanıma fişi sürüm kaydeder ve arka planda hassas alanları gizler',
    (tester) async {
      final o = (await s.sinifOgrencileri(b, 1)).single;
      await tester.pumpWidget(
        MaterialApp(
          home: RehberlikTanimaFormScreen(
            service: s,
            baglam: b,
            atamaId: 1,
            ogrenci: o,
            saltOkunur: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hassas formu görüntüle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görüntüle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Özel bilgi');
      await tester.scrollUntilVisible(
        find.text('Yeni sürüm olarak kaydet'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Yeni sürüm olarak kaydet'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(await db.query('RehberlikForm'), hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Hassas formu görüntüle'), findsOneWidget);
      await tester.tap(find.text('Hassas formu görüntüle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görüntüle'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Kaydedilmemiş taslak',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hassas formu görüntüle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Görüntüle'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Kaydedilmemiş taslak',
      );
      expect(await db.query('RehberlikForm'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Ortak görüş ekranı talep oluşturur ve çoklu veli gönderimini engeller',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: MesajFormScreen(
            kaynakModul: 'SinifRehberligim',
            kaynakKayit: '1',
            ogrenciIdleri: {1, 2},
            baslik: 'Görüş talebi',
            baslangicSoru: 'Genel ve bireysel görüş',
            aliciTuru: 'Veli',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final ad in ['1 • Öğrenci1 Test', '2 • Öğrenci2 Test']) {
        await tester.ensureVisible(find.text(ad));
        await tester.tap(find.text(ad));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Görüş talebini kaydet'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Görüş talebini kaydet'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(await db.query('MesajForm'), hasLength(1));
      await tester.ensureVisible(find.text('Gönder / kopyala'));
      final gonder = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Gönder / kopyala'),
          )
          .onPressed!;
      await tester.runAsync(() async {
        gonder();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 1500));
      await tester.pumpAndSettle();
      expect(find.textContaining('başka öğrencilerin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Geçmiş yıl görüşleri okunur; cevap ekleme ve gönderim kapalıdır',
    (tester) async {
      final m = MesajlasmaService.instance;
      final once = await m.hazirla();
      final id = (await tester.runAsync(
        () => m.formOlustur(
          once,
          kaynakModul: 'SinifRehberligim',
          kaynakKayit: 'atama:1',
          baslik: 'Geçmiş talep',
          aliciTuru: 'Ogretmen',
          ogrenciIdleri: {1},
          sinifGeneli: true,
          soru: 'Geçmiş soru',
        ),
      ))!;
      await tester.runAsync(
        () => m.cevapKaydet(once, id, 'Öğretmen', 'Geçmiş cevap', {}),
      );
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
      final simdi = await m.hazirla();
      expect(
        await m.formlariGetir(simdi, 'SinifRehberligim', 'atama:1'),
        isEmpty,
      );
      expect(
        await m.formlariGetir(
          simdi,
          'SinifRehberligim',
          'atama:1',
          egitimOgretimYili: '2026/2027',
        ),
        hasLength(1),
      );
      await tester.runAsync(
        () => expectLater(
          m.cevapKaydet(simdi, id, 'Yeni', 'Yazma', {}),
          throwsStateError,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: MesajFormScreen(
            kaynakModul: 'SinifRehberligim',
            kaynakKayit: 'atama:1',
            ogrenciIdleri: {},
            egitimOgretimYili: '2026/2027',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Geçmiş talep'), findsOneWidget);
      expect(find.text('Görüş talebini kaydet'), findsNothing);
      expect(find.text('Gönder / kopyala'), findsNothing);
      expect(find.text('Cevap aktar'), findsNothing);
      await tester.tap(find.text('Cevapları gör'));
      await tester.pumpAndSettle();
      expect(find.text('Geçmiş cevap'), findsOneWidget);
      await db.update('MesajForm', {'OgretmenProfilId': 999});
      await expectLater(
        m.cevaplariGetir(simdi, id, egitimOgretimYili: '2026/2027'),
        throwsStateError,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Tek öğrencili veli talebi ortak ekrana kilitli kapsam taşır', (
    tester,
  ) async {
    final m = MesajlasmaService.instance;
    final mb = await m.hazirla();
    await tester.runAsync(
      () => m.formOlustur(
        mb,
        kaynakModul: 'SinifRehberligim',
        kaynakKayit: 'atama:1',
        baslik: 'Veli görüşü',
        aliciTuru: 'Veli',
        ogrenciIdleri: {1},
        sinifGeneli: false,
        soru: 'Öğrenci1 için görüşünüz',
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: MesajFormScreen(
          kaynakModul: 'SinifRehberligim',
          kaynakKayit: 'atama:1',
          ogrenciIdleri: {1, 2},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Gönder / kopyala'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Gönder / kopyala'))
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mesajlaşmayı aç'));
    await tester.pumpAndSettle();
    final ekran = tester.widget<MesajlasmaScreen>(
      find.byType(MesajlasmaScreen),
    );
    expect(ekran.izinliOgrenciIdleri, {1});
    expect(ekran.baslangicOgrenciIdleri, {1});
    expect(find.text('Kuyruklar / Geçmiş'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Yeni kayıtta hassaslık onayı ekrandan alınır ve kaydedilir', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RehberlikKayitEditor(
          service: s,
          baglam: b,
          atamaId: 1,
          tur: 'Gorev',
          ogrenciler: const [],
          hassasOnay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Özel takip');
    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Onayla'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Kaydet'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final dynamic kaydet = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
          .onPressed;
      await kaydet();
    });
    await tester.pumpAndSettle();
    expect((await db.query('RehberlikKayit')).single['Hassas'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Altı bölüm dar ekranda açılır; toplantı kaydı oluşturulur', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final a = (await s.atamalariGetir(b)).first;
    await tester.pumpWidget(
      MaterialApp(
        home: BireyselRehberlikDosyasiScreen(service: s, baglam: b, atama: a),
      ),
    );
    await tester.pumpAndSettle();
    for (final bolum in [
      'Öğrencilerim',
      'Toplantılar',
      'Görüşler',
      'Rehberlik Planım',
      'Görev ve Belgeler',
    ]) {
      await tester.ensureVisible(find.text(bolum).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(bolum).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Bölümlere dön'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Toplantılar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toplantılar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toplantı oluştur'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Veli toplantısı');
    await tester.scrollUntilVisible(
      find.text('Kaydet'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.runAsync(() async {
      final dynamic kaydet = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
          .onPressed;
      await kaydet();
    });
    await tester.pumpAndSettle();
    expect(await db.query('RehberlikKayit'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Toplantıda yalnız davet, düzenle ve görüş adımları sırayla açılır',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => s.kayitKaydet(
          b,
          1,
          tur: 'Toplanti',
          baslik: 'Sınıf toplantısı',
          icerik: {
            'davet': 'Toplantımıza davetlisiniz.',
            'toplantiTuru': 'Veli',
          },
        ),
      );
      final atama = (await s.atamalariGetir(
        b,
      )).firstWhere((a) => a['RehberlikAtamaId'] == 1);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('toplanti-gorsel'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AnaSayfaTemasi.mavi.olustur(Brightness.light),
            home: BireyselRehberlikDosyasiScreen(
              service: s,
              baglam: b,
              atama: atama,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Toplantılar').last);
      await tester.tap(find.text('Toplantılar').last);
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('TOPLANTI_GORSEL')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('toplanti-gorsel')),
          );
          final img = await boundary.toImage(pixelRatio: 1);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'C:/OkulYonetim/work/toplanti_uc_adim_20261028/toplanti.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          img.dispose();
        });
      }
      for (final ad in [
        'Ayrıntı',
        'Belgeyi görüntüle',
        'İlişkilendir',
        'Karar takibi oluştur',
        'Belge oluştur',
      ]) {
        expect(find.text(ad), findsNothing);
      }
      expect(
        tester.getTopLeft(find.text('1. Davet hazırla')).dy,
        lessThan(tester.getTopLeft(find.text('2. Düzenle')).dy),
      );
      expect(
        tester.getTopLeft(find.text('2. Düzenle')).dy,
        lessThan(tester.getTopLeft(find.text('3. Görüş topla')).dy),
      );
      await tester.ensureVisible(find.text('2. Düzenle'));
      await tester.tap(find.text('2. Düzenle'));
      await tester.pumpAndSettle();
      expect(find.byType(RehberlikKayitEditor), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('3. Görüş topla'));
      await tester.tap(find.text('3. Görüş topla'));
      await tester.pumpAndSettle();
      expect(find.byType(OgretmenGorusFormScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1. Davet hazırla'));
      await tester.tap(find.text('1. Davet hazırla'));
      await tester.pumpAndSettle();
      expect(find.byType(MesajlasmaScreen), findsOneWidget);
      expect((await db.query('RehberlikKayit')).length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Hassas toplantı üç adımlı görünümde güvenle düzenlenir', (
    tester,
  ) async {
    await tester.runAsync(
      () => s.kayitKaydet(
        b,
        1,
        tur: 'Toplanti',
        baslik: 'Özel toplantı',
        hassas: true,
        hassasOnay: true,
        icerik: {'kararlar': 'Özel karar'},
      ),
    );
    final a = (await s.atamalariGetir(
      b,
    )).firstWhere((a) => a['RehberlikAtamaId'] == 1);
    await tester.pumpWidget(
      MaterialApp(
        home: BireyselRehberlikDosyasiScreen(service: s, baglam: b, atama: a),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hassas erişim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erişimi aç'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Toplantılar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toplantılar').last);
    await tester.pumpAndSettle();
    expect(find.text('Karar takibi oluştur'), findsNothing);
    expect(find.text('Ayrıntı'), findsNothing);
    expect(find.text('Belge oluştur'), findsNothing);
    await tester.ensureVisible(find.text('2. Düzenle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. Düzenle'));
    await tester.pumpAndSettle();
    final editor = tester.widget<RehberlikKayitEditor>(
      find.byType(RehberlikKayitEditor),
    );
    expect(editor.tur, 'Toplanti');
    expect(editor.kayit?['Hassas'], 1);
    expect(editor.hassasOnay, true);
    expect((await db.query('RehberlikKayit')).single['Hassas'], 1);
    expect(await db.query('RehberlikBag'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
