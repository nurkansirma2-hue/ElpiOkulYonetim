import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/odev_not_semasi.dart';
import 'package:elpi_okul_yonetim/database/bilgi_toplama_semasi.dart';
import 'package:elpi_okul_yonetim/database/mesaj_alici_semasi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yonetim_paneli_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_yedekleme_screen.dart';
import 'support/windows_memory_database.dart';
import 'support/eski_yedek_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory alan;
  late BireyselBakimService bakim;
  late BireyselBelgeService belge;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = _AndroidMetadataMemoryFactory();
    db = await LocalDatabase.instance.database;
    alan = await Directory.systemTemp.createTemp('bakim_test_');
    mod = CalismaModu.bireyselOgretmen;
    bakim = BireyselBakimService(
      databaseGetir: () async => db,
      alanGetir: () async => alan,
      modGetir: () async => mod,
    );
    belge = BireyselBelgeService(
      databaseGetir: () async => db,
      alanGetir: () async => alan,
      modGetir: () async => mod,
    );
    SharedPreferences.setMockInitialValues({
      'calisma_modu': CalismaModu.bireyselOgretmen.kayitDegeri,
    });
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
      'Brans': 'Matematik',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OkulNo': '001',
      'Ad': 'Ayşe',
      'Soyad': 'Test',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifKodu': '9/A',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlan', {
      'DersId': 1,
      'SinifSubeId': 1,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': 1,
      'HaftaNo': 1,
      'Konu': 'Sayılar',
      'OlusturmaTarihi': 'test',
    });
    final a = (await belge.arsivleriGetir()).aktif;
    await belge.ekle(
      arsivId: a.id,
      dosya: PlatformFile(
        name: 'plan.txt',
        size: 5,
        readStream: Stream.value(utf8.encode('plan!')),
      ),
    );
  });
  tearDown(() async {
    await LocalDatabase.instance.close();
    await alan.delete(recursive: true);
  });
  void v28AlanlariniKaldir(Map<String, dynamic> m) {
    eskiYedekAlanlariniAyir(m, 27);
    for (final t in OdevNotSemasi.tablolar) {
      (m['tablolar'] as Map).remove(t);
      (m['kolonlar'] as Map).remove(t);
    }
    for (final (tablo, kolon) in [('OdevTanim', 'Tamamlandi'), ('OdevKontrolSonuc', 'NotDegeri')]) {
      (m['kolonlar'][tablo] as List).remove(kolon);
      for (final row in m['tablolar'][tablo] as List) {
        (row as Map).remove(kolon);
      }
    }
  }

  Future<File> degistir(
    File f,
    void Function(Map<String, dynamic>) change, {
    String? fazladan,
  }) async {
    final a = ZipDecoder().decodeBytes(await f.readAsBytes());
    final m =
        jsonDecode(utf8.decode(a.findFile('yedek.json')!.content as List<int>))
            as Map<String, dynamic>;
    change(m);
    if ((m['sema'] as int) < 30) eskiYedekAlanlariniAyir(m, 29);
    final next = Archive();
    final json = utf8.encode(jsonEncode(m));
    next.addFile(ArchiveFile('yedek.json', json.length, json));
    for (final entry in a.files.where((e) => e.name != 'yedek.json')) {
      next.addFile(ArchiveFile(entry.name, entry.size, entry.content));
    }
    if (fazladan != null) next.addFile(ArchiveFile(fazladan, 1, [1]));
    return File(
      p.join(alan.path, 'yanlis.zip'),
    ).writeAsBytes(ZipEncoder().encode(next)!);
  }

  test('ortak form durumları ve görüş yanıt önbelleği yedekten korunur', () async {
    final ayarlar = <String, String>{
      'bilgi_form_yonetim:1': jsonEncode({'sablon':'Anket','arsiv':true,'yayinAcik':false}),
      'bilgi_form_alicilari:1': jsonEncode(['Ogrenci:1:1']),
      'bilgi_form_taslak_istegi:test': jsonEncode({'formId':1,'ozet':'test'}),
      'ogretmen_gorus_v1:test': jsonEncode({'yanitlar':[{'responseId':'r1'}],'silinenYanitlar':['r0']}),
    };
    for (final e in ayarlar.entries) {
      await db.insert('UygulamaAyarlari',{'Anahtar':e.key,'Deger':e.value,'GuncellemeTarihi':'test'});
    }
    final y = await bakim.yedekle();
    for (final key in ayarlar.keys) { await db.delete('UygulamaAyarlari',where:'Anahtar=?',whereArgs:[key]); }
    await bakim.geriYukle(await bakim.incele(y.dosya),onayMetni:'GERİ YÜKLE');
    for (final e in ayarlar.entries) {
      expect((await db.query('UygulamaAyarlari',where:'Anahtar=?',whereArgs:[e.key])).single['Deger'],e.value);
    }
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
  });

  test('SQLite 31 yedeği Google tablolarını koruyarak geri yüklenir', () async {
    final y = await bakim.yedekle();
    final a = ZipDecoder().decodeBytes(await y.dosya.readAsBytes());
    final m = jsonDecode(
      utf8.decode(a.findFile('yedek.json')!.content as List<int>),
    ) as Map<String, dynamic>;
    expect(m['sema'], 31);
    for (final t in [
      'RehberlikGoogleForm',
      'RehberlikFormDavet',
      'RehberlikGoogleYanit',
    ]) {
      expect((m['tablolar'] as Map).containsKey(t), isTrue);
    }
    await db.update('Ogrenci', {'Ad': 'Değişti'});
    await bakim.geriYukle(await bakim.incele(y.dosya), onayMetni: 'GERİ YÜKLE');
    expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('v21 veli kopyası anne ilişkisine dönüşür; v22 seçimi yedekte korunur', () async {
    await db.update('Ogrenci', {'AnneAdi': 'Anne', 'AnneTelefon': '05321112233',
      'BabaAdi': 'Baba', 'BabaTelefon': '05324445566',
      'VeliAdi': 'Anne', 'VeliTelefonu': '+905321112233', 'VeliTuru': 'Anne'});
    final y = await bakim.yedekle();
    final eski = await degistir(y.dosya, (m) {
      m['sema'] = 21;
      v28AlanlariniKaldir(m);
      for (final t in [...MesajAliciSemasi.tablolar, 'OgrenciIletisim', 'MesajOgretmenSinifDers', 'MesajTekliGecmis']) {
        (m['tablolar'] as Map).remove(t); (m['kolonlar'] as Map).remove(t);
      }
      (m['kolonlar']['Ogrenci'] as List).remove('VeliTuru');
      for (final o in m['tablolar']['Ogrenci'] as List) { (o as Map).remove('VeliTuru'); }
    });
    await bakim.geriYukle(await bakim.incele(eski), onayMetni: 'GERİ YÜKLE');
    var o = (await db.query('Ogrenci')).single;
    expect(o['VeliTuru'], 'Anne');
    expect(o['VeliTelefonu'], '+905321112233');
    await db.update('Ogrenci', {'VeliTuru': 'Baba'});
    final yeni = await bakim.yedekle();
    await db.update('Ogrenci', {'VeliTuru': 'Anne'});
    await bakim.geriYukle(await bakim.incele(yeni.dosya), onayMetni: 'GERİ YÜKLE');
    o = (await db.query('Ogrenci')).single;
    expect(o['VeliTuru'], 'Baba');
    expect(o['AnneTelefon'], '05321112233');
    expect(o['BabaTelefon'], '05324445566');
  });
  test('v25 öğretmen sınıf ders ilişkileri yedek ve geri yüklemede korunur', () async {
    final id=List.filled(32,'a').join();
    await db.insert('MesajOgretmenKisi',{'KisiId':id,'OkulId':'okul','SahipProfilId':1,'AdSoyad':'Ders Öğretmeni','Telefon':'05320000000','OlusturmaTarihi':'test','GuncellemeTarihi':'test'});
    await db.insert('MesajOgretmenSinif',{'KisiId':id,'SinifSubeId':1,'EgitimOgretimYili':'2026-2027','Kaynak':'DersProgrami','OlusturmaTarihi':'test'});
    await db.insert('MesajOgretmenSinifDers',{'KisiId':id,'SinifSubeId':1,'EgitimOgretimYili':'2026-2027','DersId':1});
    final y=await bakim.yedekle();
    await db.delete('MesajOgretmenSinifDers');
    await bakim.geriYukle(await bakim.incele(y.dosya),onayMetni:'GERİ YÜKLE');
    expect(await db.query('MesajOgretmenSinifDers'),hasLength(1));
    expect((await db.query('MesajOgretmenKisi')).single['Telefon'],'05320000000');
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
  });
  for (final version in [17, 18]) {
    test('SQLite $version yedeği 24 şemasına dönüştürülür', () async {
      final y = await bakim.yedekle();
      final eski = await degistir(y.dosya, (m) {
        m['sema'] = version;
        v28AlanlariniKaldir(m);
        for (final t in [...MesajAliciSemasi.tablolar, 'OgrenciIletisim', 'MesajOgretmenSinifDers', 'MesajTekliGecmis']) {
          (m['tablolar'] as Map).remove(t); (m['kolonlar'] as Map).remove(t);
        }
        (m['kolonlar']['Ogrenci'] as List).remove('VeliTuru');
        for (final o in m['tablolar']['Ogrenci'] as List) {
          (o as Map).remove('VeliTuru');
        }
        for (final t in ['OdevDegerlendirmeOlcutu', 'OdevDegerlendirmePuani']) {
          (m['tablolar'] as Map).remove(t);
          (m['kolonlar'] as Map).remove(t);
        }
        for (final t in BilgiToplamaSemasi.tablolar) {
          (m['tablolar'] as Map).remove(t);
          (m['kolonlar'] as Map).remove(t);
        }
        (m['kolonlar']['Ogrenci'] as List).removeWhere(
          BilgiToplamaSemasi.ogrenciAlanlari.contains,
        );
        for (final row in m['tablolar']['Ogrenci'] as List) {
          for (final f in BilgiToplamaSemasi.ogrenciAlanlari) {
            (row as Map).remove(f);
          }
        }
        for (final t in [
          'RehberlikGoogleForm',
          'RehberlikFormDavet',
          'RehberlikGoogleYanit',
          if (version == 17) 'MesajSms',
        ]) {
          (m['tablolar'] as Map).remove(t);
          (m['kolonlar'] as Map).remove(t);
        }
      });
      await db.update('Ogrenci', {'Ad': 'Değişti'});
      await bakim.geriYukle(
        await bakim.incele(eski),
        onayMetni: 'GERİ YÜKLE',
      );
      expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
      expect(await db.query('RehberlikGoogleForm'), isEmpty);
      expect(await db.query('RehberlikFormDavet'), isEmpty);
      expect(await db.query('RehberlikGoogleYanit'), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }

  test('Yanlış sürüm etiketli yedek reddedilir; canlı veri korunur', () async {
    final y = await bakim.yedekle();
    final hatali = await degistir(y.dosya, (m) {
      m['sema'] = 17;
    });
    await db.update('Ogrenci', {'Ad': 'Korunacak'});
    await expectLater(bakim.incele(hatali), throwsA(isA<FormatException>()));
    expect((await db.query('Ogrenci')).single['Ad'], 'Korunacak');
  });

  test('Yeni yedek sistem tablosunu içermez; Android locale korunur', () async {
    final y = await bakim.yedekle();
    final a = ZipDecoder().decodeBytes(await y.dosya.readAsBytes());
    final m = jsonDecode(
      utf8.decode(a.findFile('yedek.json')!.content as List<int>),
    ) as Map<String, dynamic>;
    expect((m['tablolar'] as Map).containsKey('android_metadata'), isFalse);
    expect((m['kolonlar'] as Map).containsKey('android_metadata'), isFalse);
    expect(y.sayilar.containsKey('android_metadata'), isFalse);
    await db.update('Ogrenci', {'Ad': 'Değişti'});
    await bakim.geriYukle(await bakim.incele(y.dosya), onayMetni: 'GERİ YÜKLE');
    expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
    expect((await db.query('android_metadata')).single['locale'], 'tr_TR');
  });
  test('Eski Android yedeği locale değerini değiştirmeden geri yüklenir', () async {
    final y = await bakim.yedekle();
    final old = await degistir(y.dosya, (m) {
      m['tablolar']['android_metadata'] = [{'locale': 'en_US'}];
      m['kolonlar']['android_metadata'] = ['locale'];
    });
    final bytes = await old.readAsBytes();
    await db.update('Ogrenci', {'Ad': 'Değişti'});
    final info = await bakim.incele(old);
    expect(info.sayilar.containsKey('android_metadata'), isFalse);
    final protection = await bakim.geriYukle(info, onayMetni: 'GERİ YÜKLE');
    expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
    expect((await db.query('android_metadata')).single['locale'], 'tr_TR');
    expect(await old.readAsBytes(), bytes);
    final protectionArchive = ZipDecoder().decodeBytes(
      await File(protection).readAsBytes(),
    );
    final protectionManifest = jsonDecode(
      utf8.decode(protectionArchive.findFile('yedek.json')!.content as List<int>),
    ) as Map<String, dynamic>;
    expect((protectionManifest['tablolar'] as Map).containsKey('android_metadata'), isFalse);
    expect((protectionManifest['kolonlar'] as Map).containsKey('android_metadata'), isFalse);
    final protect = await bakim.incele(File(protection));
    expect(protect.sayilar.containsKey('android_metadata'), isFalse);
  });
  test('Eski Android yedeği sistem tablosu olmayan hedefte de açılır', () async {
    final y = await bakim.yedekle();
    final old = await degistir(y.dosya, (m) {
      m['tablolar']['ANDROID_METADATA'] = [{'locale': 'en_US'}];
      m['kolonlar']['ANDROID_METADATA'] = ['locale'];
    });
    await db.execute('DROP TABLE android_metadata');
    databaseFactory = WindowsMemoryFactory();
    await db.update('Ogrenci', {'Ad': 'Değişti'});
    await bakim.geriYukle(await bakim.incele(old), onayMetni: 'GERİ YÜKLE');
    expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE lower(name) = 'android_metadata'",
      ),
      isEmpty,
    );
  });
  test('Sistem tablosu atlanırken bilinmeyen uygulama tablosu reddedilir', () async {
    final y = await bakim.yedekle();
    final wrong = await degistir(y.dosya, (m) {
      m['tablolar']['android_metadata'] = [{'locale': 'en_US'}];
      m['kolonlar']['android_metadata'] = ['locale'];
      m['tablolar']['BilinmeyenTablo'] = [];
      m['kolonlar']['BilinmeyenTablo'] = ['Id'];
    });
    await expectLater(bakim.incele(wrong), throwsA(isA<FormatException>()));
    expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
    expect((await db.query('android_metadata')).single['locale'], 'tr_TR');
  });

  test(
    'Tüm veriler, fotoğraf BLOB ve belgeler yeni yollarla geri gelir',
    () async {
      final foto = Uint8List.fromList([0, 255, 128, 1]);
      await db.insert('OgrenciFotograf', {
        'OgrenciId': 1,
        'DosyaYolu': '',
        'FotoVerisi': foto,
        'OlusturmaTarihi': 'test',
      });
      final old = (await db.query('BireyselBelge')).single['GoreliYol'];
      final y = await bakim.yedekle();
      expect(y.sayilar['YillikPlanDetay'], 1);
      expect(y.sayilar['BireyselBelge'], 1);
      await db.update('Ogrenci', {'Ad': 'Değişti'});
      final info = await bakim.incele(y.dosya);
      final protection = await bakim.geriYukle(info, onayMetni: 'GERİ YÜKLE');
      expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
      expect((await db.query('OgrenciFotograf')).single['FotoVerisi'], foto);
      expect((await db.query('YillikPlanDetay')).single['Konu'], 'Sayılar');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final r = (await db.query('BireyselBelge')).single;
      expect(r['GoreliYol'], isNot(old));
      expect(
        await File(
          p.join(alan.path, 'bireysel_belgeler', r['GoreliYol'] as String),
        ).readAsString(),
        'plan!',
      );
      expect(
        await File(
          p.join(alan.path, 'bireysel_belgeler', old as String),
        ).exists(),
        isFalse,
      );
      expect(await File(protection).exists(), isTrue);
      final protect = await bakim.incele(File(protection));
      expect(protect.sayilar['Ogrenci'], 1);
    },
  );
  test(
    'Sıfırlamadan sonra korunan belgelerle yedekten profil yeniden kurulur',
    () async {
      final y = await bakim.yedekle();
      await LocalDatabase.instance.bireyselVerileriSifirla(
        onayMetni: 'SIFIRLA',
      );
      expect(await db.query('OgretmenProfil'), isEmpty);
      expect(await db.query('BireyselBelge'), hasLength(1));
      await bakim.geriYukle(
        await bakim.incele(y.dosya),
        onayMetni: 'GERİ YÜKLE',
      );
      expect(await db.query('OgretmenProfil'), hasLength(1));
      expect(await db.query('YillikPlanDetay'), hasLength(1));
    },
  );
  test('v25 yedeğindeki kaldırılan modüller geri gelmez; diğer veriler yüklenir', () async {
    final y = await bakim.yedekle();
    final eski = await degistir(y.dosya, (m) {
      m['sema'] = 25;
      v28AlanlariniKaldir(m);
      (m['tablolar'] as Map).remove('MesajTekliGecmis');
      (m['kolonlar'] as Map).remove('MesajTekliGecmis');
      for (final t in ['Yoklama', 'YoklamaDetay', 'BireyselIslenenDers']) {
        m['tablolar'][t] = [{'Id': 1}];
        m['kolonlar'][t] = ['Id'];
      }
    });
    final kaynak = await eski.readAsBytes();
    final bilgi = await bakim.incele(eski);
    expect(bilgi.sayilar.containsKey('Yoklama'), false);
    await db.update('Ogrenci', {'Ad':'Değişti'});
    await bakim.geriYukle(bilgi, onayMetni:'GERİ YÜKLE');
    expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
    expect(await db.query('YillikPlan'), hasLength(1));
    expect(await eski.readAsBytes(), kaynak);
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name IN ('Yoklama','YoklamaDetay','BireyselIslenenDers')"), isEmpty);
  });

  test('Yanlış onay hiçbir veriyi değiştirmez', () async {
    final y = await bakim.yedekle();
    await expectLater(bakim.geriYukle(y, onayMetni: 'evet'), throwsStateError);
    expect((await db.query('Ogrenci')).single['Ad'], 'Ayşe');
  });
  test('Kurumsal modda yedek ve geri yükleme engellenir', () async {
    mod = null;
    await expectLater(bakim.yedekle(), throwsStateError);
  });
  test('Eksik belge kısmi yedek üretmez', () async {
    final r = (await db.query('BireyselBelge')).single;
    await File(
      p.join(alan.path, 'bireysel_belgeler', r['GoreliYol'] as String),
    ).delete();
    await expectLater(bakim.yedekle(), throwsStateError);
    expect(
      await Directory(p.join(alan.path, 'bakim_yedekleri')).list().length,
      0,
    );
  });
  test('Çöp kutusu, klasör ve import geçmişi yedekte korunur', () async {
    final r = (await db.query('BireyselBelge')).single;
    await db.insert('BelgeKlasoru', {
      'KlasorId': 'klasor',
      'ArsivId': r['ArsivId'],
      'Ad': 'Planlar',
      'AramaAdi': 'planlar',
    });
    await db.update('BireyselBelge', {
      'KlasorId': 'klasor',
      'SilinmeTarihi': 'test',
      'TurElleSecildi': 1,
      'BelgeTuru': 'Yıllık plan',
    });
    await db.insert('BelgeImportGecmisi', {
      'IslemId': 'test',
      'BelgeId': r['BelgeId'],
      'Modul': 'yillik',
      'EgitimOgretimYili': '2026-2027',
      'Tarih': 'test',
      'Eklenen': 1,
      'Guncellenen': 0,
      'Mesaj': 'tamam',
    });
    final y = await bakim.yedekle();
    await bakim.geriYukle(await bakim.incele(y.dosya), onayMetni: 'GERİ YÜKLE');
    final restored = (await db.query('BireyselBelge')).single;
    expect(restored['SilinmeTarihi'], 'test');
    expect(restored['TurElleSecildi'], 1);
    expect(
      restored['ArsivId'],
      (await db.query('BelgeKlasoru')).single['ArsivId'],
    );
    expect(
      (await db.query('BelgeImportGecmisi')).single['BelgeId'],
      restored['BelgeId'],
    );
  });
  test('Yol aşımı ve fazladan ZIP girdisi reddedilir', () async {
    final y = await bakim.yedekle();
    final wrong = await degistir(y.dosya, (_) {}, fazladan: '../disari.txt');
    await expectLater(bakim.incele(wrong), throwsA(isA<FormatException>()));
    expect(await db.query('Ogrenci'), hasLength(1));
  });
  test(
    'Kopuk yıllık plan ilişkisi canlı verileri değiştirmeden reddedilir',
    () async {
      final y = await bakim.yedekle();
      final wrong = await degistir(
        y.dosya,
        (m) => m['tablolar']['YillikPlanDetay'][0]['YillikPlanId'] = 999,
      );
      await expectLater(bakim.incele(wrong), throwsA(anything));
      expect((await db.query('YillikPlanDetay')).single['YillikPlanId'], 1);
    },
  );
  test(
    'Veri yazımı hata verirse transaction ve yeni dosya alanı geri alınır',
    () async {
      final y = await bakim.yedekle();
      final info = await bakim.incele(y.dosya);
      await db.update('Ogrenci', {'Ad': 'Önceki'});
      await db.execute(
        "CREATE TRIGGER test_error BEFORE INSERT ON Ogrenci WHEN NEW.Ad='Ayşe' BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      final old = (await Directory(
        p.join(alan.path, 'bireysel_belgeler'),
      ).list().toList()).length;
      await expectLater(
        bakim.geriYukle(info, onayMetni: 'GERİ YÜKLE'),
        throwsA(anything),
      );
      expect((await db.query('Ogrenci')).single['Ad'], 'Önceki');
      expect(
        await Directory(p.join(alan.path, 'bireysel_belgeler')).list().length,
        old,
      );
    },
  );
  test(
    'Eski fotoğraf yolu içerik olarak alınır ve taşınabilir hale gelir',
    () async {
      final f = await File(
        p.join(alan.path, 'eski.jpg'),
      ).writeAsBytes([1, 2, 255]);
      await db.insert('OgrenciFotograf', {
        'OgrenciId': 1,
        'DosyaYolu': f.path,
        'OlusturmaTarihi': 'test',
      });
      final y = await bakim.yedekle();
      final info = await bakim.incele(y.dosya);
      await bakim.geriYukle(info, onayMetni: 'GERİ YÜKLE');
      final r = (await db.query('OgrenciFotograf')).single;
      expect(r['DosyaYolu'], '');
      expect(r['FotoVerisi'], [1, 2, 255]);
    },
  );
  test(
    'Özel alan dışındaki kaynak ve yanlış onayla yerel yedek silinmez',
    () async {
      final y = await bakim.yedekle();
      await expectLater(
        bakim.yerelYedegiSil(y.dosya, onay: 'evet'),
        throwsStateError,
      );
      final disari = await File(
        p.join(alan.path, 'kaynak.zip'),
      ).writeAsBytes([1]);
      await expectLater(
        bakim.yerelYedegiSil(disari, onay: 'SİL'),
        throwsStateError,
      );
      expect(await disari.exists(), isTrue);
      await bakim.yerelYedegiSil(y.dosya, onay: 'SİL');
      expect(await y.dosya.exists(), isFalse);
      expect(await db.query('Ogrenci'), hasLength(1));
    },
  );
  test(
    'Yerel yedekler yeniden açılabilir; ilgisiz dosyalar listelenmez',
    () async {
      final y = await bakim.yedekle();
      await File(
        p.join(y.dosya.parent.path, 'kaynak.txt'),
      ).writeAsString('koru');
      expect((await bakim.yerelYedekler()).map((f) => f.path), [y.dosya.path]);
      expect((await bakim.incele(y.dosya)).sayilar['Ogrenci'], 1);
    },
  );
  test(
    'Bilinen yedekte sahte açılmış boyut içerik açılırken durdurulur',
    () async {
      final y = await bakim.yedekle();
      final bytes = await y.dosya.readAsBytes();
      final data = ByteData.sublistView(bytes);
      var found = false;
      for (var i = 0; i < bytes.length - 30; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50) {
          data.setUint32(i + 24, 1, Endian.little);
          found = true;
          break;
        }
      }
      expect(found, isTrue);
      final bad = await File(
        p.join(alan.path, 'bozuk.zip'),
      ).writeAsBytes(bytes);
      await expectLater(bakim.incele(bad), throwsA(anything));
      expect(await db.query('YillikPlanDetay'), hasLength(1));
    },
  );
  test('Yedekte dışarıya işaret eden fotoğraf yolu reddedilir', () async {
    await db.insert('OgrenciFotograf', {
      'OgrenciId': 1,
      'DosyaYolu': '',
      'FotoVerisi': Uint8List.fromList([1]),
      'OlusturmaTarihi': 'test',
    });
    final y = await bakim.yedekle();
    final bad = await degistir(
      y.dosya,
      (m) => m['tablolar']['OgrenciFotograf'][0]['DosyaYolu'] = 'C:/gizli.txt',
    );
    await expectLater(bakim.incele(bad), throwsA(isA<FormatException>()));
  });
  test('Kaynak belge sonradan değişirse eksik yedek üretilmez', () async {
    final r = (await db.query('BireyselBelge')).single;
    await File(
      p.join(alan.path, 'bireysel_belgeler', r['GoreliYol'] as String),
    ).writeAsString('değişmiş');
    await expectLater(bakim.yedekle(), throwsStateError);
    expect(await db.query('BireyselBelge'), hasLength(1));
  });
  testWidgets(
    'Yönetim paneli önce modül seçtirir, sıfırlamadan önce yedek önerir',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: BireyselYonetimPaneliScreen(onSifirlandi: () {})),
      );
      expect(find.text('Yönetim ve Bakım'), findsOneWidget);
      expect(find.text('Yedekleme ve Geri Yükleme'), findsOneWidget);
      final reset = find.widgetWithText(
        FilledButton,
        'Bireysel Verileri Sıfırla',
      );
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(find.text('Sıfırlanacak modüller'), findsOneWidget);
      expect(find.text('Sıfırlamadan önce yedekle'), findsNothing);
      final modul = find.byKey(const ValueKey('sifirla-modul-planlar'));
      await tester.scrollUntilVisible(modul, 180, scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(modul);
      await tester.pumpAndSettle();
      await tester.tap(modul);
      await tester.pumpAndSettle();
      final uygula = find.byKey(const ValueKey('secili-modulleri-sifirla'));
      await tester.scrollUntilVisible(uygula, 200, scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(uygula);
      await tester.pumpAndSettle();
      await tester.tap(uygula);
      await tester.pumpAndSettle();
      expect(find.text('Sıfırlamadan önce yedekle'), findsOneWidget);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      expect(await db.query('Ogrenci'), hasLength(1));
    },
  );
  testWidgets('Dar ekranda bakım düğmeleri kaydırılır ve taşma yapmaz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: BireyselYedeklemeScreen(service: bakim)),
    );
    await tester.scrollUntilVisible(
      find.text('Yedeği Geri Yükle'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

// Android'in SQLite açılışında oluşturduğu tabloyu testte de hazırla.
class _AndroidMetadataMemoryFactory extends WindowsMemoryFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final database = db = WindowsMemoryDatabase();
    try {
      await database.execute('CREATE TABLE android_metadata (locale TEXT)');
      await database.insert('android_metadata', {'locale': 'tr_TR'});
      await options?.onConfigure?.call(database);
      await options?.onCreate?.call(database, options.version!);
      await options?.onOpen?.call(database);
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }
}

