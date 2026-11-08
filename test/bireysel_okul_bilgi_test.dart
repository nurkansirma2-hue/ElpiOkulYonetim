import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/okul_bilgi_model.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_liste_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_okul_bilgi_service.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  Directory? alan;

  Future<void> eskiMudurEkle([String mudur = 'Eski Müdür']) async {
    await db.insert('UygulamaAyarlari', {
      'Anahtar': 'liste_muduru:1:${Uri.encodeComponent('test okulu')}',
      'Deger': mudur,
      'GuncellemeTarihi': 'test',
    });
  }

  Future<void> yilDegistir(String yil) async {
    await db.update('OkulProfil', {'EgitimYili': yil});
    await db.update('OgretmenProfil', {'EgitimOgretimYili': yil});
  }

  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    alan = null;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Test Okulu',
      'OkulKisaAdi': 'TO',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Test Öğretmen',
      'Brans': 'Matematik',
      'OkulAdi': 'Test Okulu',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
  });

  tearDown(() async {
    await LocalDatabase.instance.close();
    final directory = alan;
    if (directory != null) {
      expect(
        p.isWithin(Directory.systemTemp.absolute.path, directory.absolute.path),
        isTrue,
      );
      expect(p.basename(directory.path), startsWith('okul_bilgi_test_'));
      await directory.delete(recursive: true);
    }
  });

  test(
    'İlk okuma eski müdürü gösterir; yeni ayar veya şema oluşturmaz',
    () async {
      await eskiMudurEkle();
      final oncekiTablolar = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master ORDER BY name",
      );
      final oncekiAyarlar = await db.query('UygulamaAyarlari');
      final oturum = await BireyselOkulBilgiService.getir();
      expect(oturum.okulId, 'okul-1');
      expect(oturum.ogretmenId, 1);
      expect(oturum.yil, '2026/2027');
      expect(oturum.okul.okulId, 0);
      expect(oturum.okul.okulAdi, 'Test Okulu');
      expect(oturum.okul.kisaAd, 'TO');
      expect(oturum.okul.mudurAdi, 'Eski Müdür');
      expect(oturum.okul.aktifDonem, '1');
      expect(await db.query('UygulamaAyarlari'), oncekiAyarlar);
      expect(
        await db.rawQuery("SELECT name, sql FROM sqlite_master ORDER BY name"),
        oncekiTablolar,
      );
    },
  );

  test(
    'Temel alanlar kalıcıdır; okul kimliği, kısa ad ve diğer profil alanları korunur',
    () async {
      final oturum = await BireyselOkulBilgiService.getir();
      await BireyselOkulBilgiService.kaydet(
        oturum,
        oturum.okul.copyWith(
          okulAdi: '  Yeni Test Okulu  ',
          kisaAd: 'Değişmemeli',
          mudurAdi: '  Ayşe Yönetici  ',
          mudurYardimcilari: 'Ali\nVeli',
          telefon: '  0312 123 45 67  ',
          email: '  okul@example.edu.tr  ',
          webSitesi: 'www.example.edu.tr',
          adres: '  Ankara, Türkiye  ',
          konum: 'https://maps.google.com/?q=Ankara',
          toplamOgrenciSayisi: 999,
        ),
      );
      final result = await BireyselOkulBilgiService.getir();
      expect(result.okulId, oturum.okulId);
      expect(result.okul.kisaAd, 'TO');
      expect(result.okul.okulAdi, 'Yeni Test Okulu');
      expect(result.okul.mudurAdi, 'Ayşe Yönetici');
      expect(result.okul.mudurYardimcilari, 'Ali\nVeli');
      expect(result.okul.telefon, '0312 123 45 67');
      expect(result.okul.email, 'okul@example.edu.tr');
      expect(result.okul.webSitesi, 'www.example.edu.tr');
      expect(result.okul.adres, 'Ankara, Türkiye');
      expect(result.okul.konum, 'https://maps.google.com/?q=Ankara');
      expect(result.okul.toplamOgrenciSayisi, 0);
      final teacher = (await db.query('OgretmenProfil')).single;
      expect(teacher['OkulAdi'], result.okul.okulAdi);
      expect(teacher['AdSoyad'], 'Test Öğretmen');
      expect(teacher['Brans'], 'Matematik');
      expect(teacher['EgitimOgretimYili'], oturum.yil);
      final ayar = (await db.query('UygulamaAyarlari')).single;
      expect(ayar['Anahtar'], 'okul_bilgileri:okul-1:1');
      expect(
        (jsonDecode(ayar['Deger'] as String) as Map).keys,
        unorderedEquals([
          'mudurAdi',
          'mudurYardimcilari',
          'telefon',
          'email',
          'webSitesi',
          'adres',
          'konum',
        ]),
      );
    },
  );

  test(
    'Eski müdür ilk kayıtta aktarılır; bilinçli boşaltınca geri gelmez',
    () async {
      await eskiMudurEkle();
      final oturum = await BireyselOkulBilgiService.getir();
      await BireyselOkulBilgiService.kaydet(
        oturum,
        oturum.okul.copyWith(telefon: '123'),
      );
      expect((await BireyselListeService.hazirla()).mudur, 'Eski Müdür');
      final current = await BireyselOkulBilgiService.getir();
      await BireyselOkulBilgiService.kaydet(
        current,
        current.okul.copyWith(mudurAdi: ''),
      );
      expect((await BireyselOkulBilgiService.getir()).okul.mudurAdi, isEmpty);
      expect((await BireyselListeService.hazirla()).mudur, isEmpty);
      expect(
        (await db.query(
          'UygulamaAyarlari',
          where: 'Anahtar LIKE ?',
          whereArgs: ['liste_muduru:%'],
        )).single['Deger'],
        'Eski Müdür',
      );
    },
  );

  test(
    'Rapor müdürü ortak kaynağı günceller ve diğer okul alanlarını korur',
    () async {
      var oturum = await BireyselOkulBilgiService.getir();
      await BireyselOkulBilgiService.kaydet(
        oturum,
        oturum.okul.copyWith(
          telefon: '0312 123 45 67',
          mudurYardimcilari: 'Ali',
          adres: 'Ankara',
          email: 'okul@example.com',
        ),
      );
      final liste = await BireyselListeService.hazirla();
      expect(liste.okulId, 'okul-1');
      await BireyselListeService.mudurKaydet(liste, '  Yeni Müdür  ');
      oturum = await BireyselOkulBilgiService.getir();
      expect(oturum.okul.mudurAdi, 'Yeni Müdür');
      expect(oturum.okul.telefon, '0312 123 45 67');
      expect(oturum.okul.mudurYardimcilari, 'Ali');
      expect(oturum.okul.adres, 'Ankara');
      expect(oturum.okul.email, 'okul@example.com');
      expect(await db.query('UygulamaAyarlari'), hasLength(1));
    },
  );

  test(
    'Okul adı düzelince müdür korunur; eski form ve rapor oturumu yazamaz',
    () async {
      await eskiMudurEkle();
      final okul = await BireyselOkulBilgiService.getir();
      final liste = await BireyselListeService.hazirla();
      await BireyselOkulBilgiService.kaydet(
        okul,
        okul.okul.copyWith(okulAdi: 'Yeni Ad'),
      );
      expect((await BireyselListeService.hazirla()).mudur, 'Eski Müdür');
      await expectLater(
        BireyselOkulBilgiService.kaydet(okul, okul.okul),
        throwsStateError,
      );
      await expectLater(
        BireyselListeService.mudurKaydet(liste, 'Eski Oturum'),
        throwsStateError,
      );
      expect((await BireyselOkulBilgiService.getir()).okul.okulAdi, 'Yeni Ad');
    },
  );

  test(
    'Yeni yılda bilgiler hatırlanır; önceki yılın form ve raporu yazamaz',
    () async {
      final okul = await BireyselOkulBilgiService.getir();
      final liste = await BireyselListeService.hazirla();
      await BireyselListeService.mudurKaydet(liste, 'Yıllar arası müdür');
      await yilDegistir('2027/2028');
      expect(
        (await BireyselOkulBilgiService.getir()).okul.mudurAdi,
        'Yıllar arası müdür',
      );
      expect(
        (await BireyselListeService.hazirla()).mudur,
        'Yıllar arası müdür',
      );
      await expectLater(
        BireyselOkulBilgiService.kaydet(okul, okul.okul),
        throwsStateError,
      );
      await expectLater(
        BireyselListeService.mudurKaydet(liste, 'Eski yıl'),
        throwsStateError,
      );
    },
  );

  test(
    'Başka öğretmen veya okul kimliği aynı adlı okulun verisini devralamaz',
    () async {
      final old = await BireyselOkulBilgiService.getir();
      final liste = await BireyselListeService.hazirla();
      await BireyselListeService.mudurKaydet(liste, 'Özel Müdür');
      await db.update('OgretmenProfil', {'Aktif': 0});
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Diğer Öğretmen',
        'OkulAdi': 'Test Okulu',
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      expect((await BireyselOkulBilgiService.getir()).okul.mudurAdi, isEmpty);
      await expectLater(
        BireyselOkulBilgiService.kaydet(old, old.okul),
        throwsStateError,
      );
      await expectLater(
        BireyselListeService.mudurKaydet(liste, 'Yanlış profil'),
        throwsStateError,
      );
      await db.update('OgretmenProfil', {
        'Aktif': 0,
      }, where: 'OgretmenProfilId = 2');
      await db.update('OgretmenProfil', {
        'Aktif': 1,
      }, where: 'OgretmenProfilId = 1');
      await db.update('OkulProfil', {'OkulId': 'yeni-okul-kimligi'});
      expect((await BireyselOkulBilgiService.getir()).okul.mudurAdi, isEmpty);
      await expectLater(
        BireyselOkulBilgiService.kaydet(old, old.okul),
        throwsStateError,
      );
      await expectLater(
        BireyselListeService.mudurKaydet(liste, 'Yanlış okul'),
        throwsStateError,
      );
    },
  );

  test(
    'Rapor müdürü değişince açık form eski değerlerle üzerine yazamaz',
    () async {
      final oturum = await BireyselOkulBilgiService.getir();
      await BireyselListeService.mudurKaydet(
        await BireyselListeService.hazirla(),
        'Güncel Müdür',
      );
      await expectLater(
        BireyselOkulBilgiService.kaydet(
          oturum,
          oturum.okul.copyWith(telefon: '123'),
        ),
        throwsStateError,
      );
      expect(
        (await BireyselOkulBilgiService.getir()).okul.mudurAdi,
        'Güncel Müdür',
      );
    },
  );

  test(
    'Kurumsal veya seçilmemiş mod okul bilgilerini okuyamaz ve yazamaz',
    () async {
      final oturum = await BireyselOkulBilgiService.getir();
      final liste = await BireyselListeService.hazirla();
      for (final mod in ['okul', '']) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('calisma_modu', mod);
        await expectLater(BireyselOkulBilgiService.getir(), throwsStateError);
        await expectLater(
          BireyselOkulBilgiService.kaydet(oturum, oturum.okul),
          throwsStateError,
        );
        await expectLater(
          BireyselListeService.mudurKaydet(liste, 'Yazılmamalı'),
          throwsStateError,
        );
      }
      expect(await db.query('UygulamaAyarlari'), isEmpty);
    },
  );

  test(
    'Hatalı ve sınırı aşan girişler hiçbir profil veya ayarı değiştirmez',
    () async {
      final oturum = await BireyselOkulBilgiService.getir();
      final invalid = <OkulBilgiModel>[
        oturum.okul.copyWith(okulAdi: '  '),
        oturum.okul.copyWith(okulAdi: 'a' * 201),
        oturum.okul.copyWith(mudurAdi: 'a' * 161),
        oturum.okul.copyWith(mudurYardimcilari: 'a' * 1001),
        oturum.okul.copyWith(telefon: '1' * 51),
        oturum.okul.copyWith(email: 'okul@'),
        oturum.okul.copyWith(email: '${'a' * 250}@a.com'),
        oturum.okul.copyWith(webSitesi: 'javascript://alert.example.com'),
        oturum.okul.copyWith(webSitesi: 'https://.'),
        oturum.okul.copyWith(webSitesi: 'https://exa mple.com'),
        oturum.okul.copyWith(konum: 'ftp://maps.example.com'),
        oturum.okul.copyWith(konum: 'https://example.com/${'a' * 2048}'),
        oturum.okul.copyWith(adres: 'a' * 2001),
      ];
      for (final model in invalid) {
        await expectLater(
          BireyselOkulBilgiService.kaydet(oturum, model),
          throwsFormatException,
        );
      }
      expect(await db.query('UygulamaAyarlari'), isEmpty);
      expect((await db.query('OkulProfil')).single['OkulAdi'], 'Test Okulu');
      expect(
        (await db.query('OgretmenProfil')).single['OkulAdi'],
        'Test Okulu',
      );
    },
  );

  test(
    'İkinci profil güncellemesi başarısızsa ilk güncelleme de geri alınır',
    () async {
      final oturum = await BireyselOkulBilgiService.getir();
      await db.execute(
        '''CREATE TRIGGER TestProfilHatasi BEFORE UPDATE ON OgretmenProfil
      BEGIN SELECT RAISE(ABORT, 'Test profil güncelleme hatası'); END''',
      );
      await expectLater(
        BireyselOkulBilgiService.kaydet(
          oturum,
          oturum.okul.copyWith(okulAdi: 'Kaydedilmemeli'),
        ),
        throwsStateError,
      );
      expect((await db.query('OkulProfil')).single['OkulAdi'], 'Test Okulu');
      expect(
        (await db.query('OgretmenProfil')).single['OkulAdi'],
        'Test Okulu',
      );
      expect(await db.query('UygulamaAyarlari'), isEmpty);
    },
  );

  test('Bozuk JSON sessizce boşaltılıp üzerine yazılmaz', () async {
    final oturum = await BireyselOkulBilgiService.getir();
    await db.insert('UygulamaAyarlari', {
      'Anahtar': 'okul_bilgileri:okul-1:1',
      'Deger': '{bozuk',
      'GuncellemeTarihi': 'test',
    });
    await expectLater(BireyselOkulBilgiService.getir(), throwsFormatException);
    await expectLater(
      BireyselOkulBilgiService.kaydet(oturum, oturum.okul),
      throwsFormatException,
    );
    expect((await db.query('UygulamaAyarlari')).single['Deger'], '{bozuk');
  });

  test('Eski okul profili olmayan rapor müdürü davranışı korunur', () async {
    await db.delete('OkulProfil');
    final liste = await BireyselListeService.hazirla();
    expect(liste.okulId, isNull);
    await BireyselListeService.mudurKaydet(liste, 'Eski Kurulum Müdürü');
    expect((await BireyselListeService.hazirla()).mudur, 'Eski Kurulum Müdürü');
    await expectLater(BireyselOkulBilgiService.getir(), throwsStateError);
  });

  test(
    'Ad düzeltmesi aynı belge arşivini ve tarihsel sahiplik adını korur',
    () async {
      final belge = BireyselBelgeService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final oncekiArsiv = (await belge.arsivleriGetir()).aktif;
      final oturum = await BireyselOkulBilgiService.getir();
      await BireyselOkulBilgiService.kaydet(
        oturum,
        oturum.okul.copyWith(okulAdi: 'Düzeltilmiş Ad'),
      );
      final sonrakiArsiv = (await belge.arsivleriGetir()).aktif;
      expect(sonrakiArsiv.id, oncekiArsiv.id);
      expect(sonrakiArsiv.okulId, oncekiArsiv.okulId);
      expect((await db.query('BelgeArsivi')).single['OkulAdi'], 'Test Okulu');
    },
  );

  test(
    'Ad düzeltmesinde eski mesaj kuyruğu görünür; içerik ve alıcı durumları korunur',
    () async {
      var launches = 0;
      final mesaj = MesajlasmaService(
        databaseGetir: () async => db,
        whatsappAc: (_, _) async {
          launches++;
        },
      );
      final eskiBaglam = await mesaj.hazirla();
      await db.insert('MesajKuyrugu', {
        'KuyrukId': 'kuyruk',
        'OkulId': 'okul-1',
        'OgretmenProfilId': 1,
        'OgretmenAdi': 'Test Öğretmen',
        'OkulAdi': 'Test Okulu',
        'EgitimOgretimYili': '2026/2027',
        'KaynakModul': 'Test',
        'Metin': 'Eski adla hazırlanmış mesaj',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('MesajAlici', {
        'KuyrukId': 'kuyruk',
        'Sira': 1,
        'Telefon': '905321234567',
        'AliciAdi': 'Veli',
        'Ogrenciler': '[]',
        'Durum': 'Onaylandi',
        'AcilmaTarihi': 'ilk açılma',
        'OnayTarihi': 'ilk onay',
      });
      final oncekiKuyruk = await db.query('MesajKuyrugu');
      final oncekiAlici = await db.query('MesajAlici');
      final oturum = await BireyselOkulBilgiService.getir();
      await BireyselOkulBilgiService.kaydet(
        oturum,
        oturum.okul.copyWith(okulAdi: 'Yeni Okul Adı'),
      );
      await expectLater(
        mesaj.kuyrukGetir(eskiBaglam, 'kuyruk'),
        throwsStateError,
      );
      final yeniBaglam = await mesaj.hazirla();
      expect((await mesaj.kuyruklar(yeniBaglam)).single.id, 'kuyruk');
      expect((await mesaj.kuyrukGetir(yeniBaglam, 'kuyruk')).onaylanan, 1);
      expect(await db.query('MesajKuyrugu'), oncekiKuyruk);
      expect(await db.query('MesajAlici'), oncekiAlici);
      expect(launches, 0);
      await db.update('OkulProfil', {'OkulId': 'baska-okul'});
      final baskaOkul = await mesaj.hazirla();
      expect(await mesaj.kuyruklar(baskaOkul), isEmpty);
      await expectLater(
        mesaj.kuyrukGetir(baskaOkul, 'kuyruk'),
        throwsStateError,
      );
    },
  );

  test('Okul bilgileri mevcut yedekle taşınır ve geri yüklenir', () async {
    alan = await Directory.systemTemp.createTemp('okul_bilgi_test_');
    final bakim = BireyselBakimService(
      databaseGetir: () async => db,
      alanGetir: () async => alan!,
    );
    final oturum = await BireyselOkulBilgiService.getir();
    await BireyselOkulBilgiService.kaydet(
      oturum,
      oturum.okul.copyWith(
        okulAdi: 'Yedekteki Okul',
        mudurAdi: 'Yedekteki Müdür',
        email: 'yedek@example.com',
        konum: 'https://maps.google.com/?q=Ankara',
      ),
    );
    final yedek = await bakim.yedekle();
    final zip = ZipDecoder().decodeBytes(await yedek.dosya.readAsBytes());
    final metadata =
        jsonDecode(
              utf8.decode(zip.findFile('yedek.json')!.content as List<int>),
            )
            as Map;
    expect(metadata['sema'], 17);
    final ayarlar = (metadata['tablolar'] as Map)['UygulamaAyarlari'] as List;
    expect(ayarlar.single['Anahtar'], 'okul_bilgileri:okul-1:1');
    final current = await BireyselOkulBilgiService.getir();
    await BireyselOkulBilgiService.kaydet(
      current,
      current.okul.copyWith(
        okulAdi: 'Sonraki Okul',
        mudurAdi: '',
        email: '',
        konum: '',
      ),
    );
    final incelenen = await bakim.incele(yedek.dosya);
    await bakim.geriYukle(incelenen, onayMetni: 'GERİ YÜKLE');
    final restored = await BireyselOkulBilgiService.getir();
    expect(restored.okulId, 'okul-1');
    expect(restored.okul.okulAdi, 'Yedekteki Okul');
    expect(restored.okul.mudurAdi, 'Yedekteki Müdür');
    expect(restored.okul.email, 'yedek@example.com');
    expect(restored.okul.konum, 'https://maps.google.com/?q=Ankara');
    expect((await BireyselListeService.hazirla()).mudur, 'Yedekteki Müdür');
  });
}
