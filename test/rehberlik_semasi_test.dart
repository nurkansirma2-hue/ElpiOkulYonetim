import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/mesajlasma_semasi.dart';
import 'package:elpi_okul_yonetim/database/rehberlik_semasi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'support/windows_memory_database.dart';
import 'support/eski_yedek_fixture.dart';
import 'package:elpi_okul_yonetim/database/bilgi_toplama_semasi.dart';

// Yeni kurulumdan sonraki sürümlerin nesnelerini çıkarıp gerçek onUpgrade çağrısını
// çalıştırır. Bütün DROP işlemleri yalnız :memory: test veritabanındadır.
class _YukseltmeFactory extends WindowsMemoryFactory {
  _YukseltmeFactory([this.eskiSurum = 13]);
  final int eskiSurum;
  bool yukseltildi = false;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final db = await super.openDatabase(path, options: options);
    expect(options!.version, 27);
    for (final t in ['MesajOgretmenSinifDers', ...BilgiToplamaSemasi.tablolar.reversed]) {
      await db.execute('DROP TABLE $t');
    }
    for (final t in [
      ...RehberlikSemasi.googleTablolari.reversed,
      'MesajSms',
      'BireyselGunlukPlan',
      'RehberlikBag',
      'RehberlikForm',
      'RehberlikKayit',
      'MesajFormCevap',
      'MesajForm',
    ]) {
      await db.execute('DROP TABLE $t');
    }
    if (eskiSurum == 13) {
      await db.execute('DROP TABLE RehberlikAtama');
      await db.execute('DROP INDEX UX_SinifSube_IdYil');
    } else {
      await db.insert('OkulProfil', {
        'Id': 1,
        'OkulId': 'eski',
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
      await db.insert('RehberlikAtama', {
        'OkulId': 'eski',
        'OgretmenProfilId': 1,
        'SinifSubeId': 1,
        'EgitimOgretimYili': '2026-2027',
        'BaslangicTarihi': '2026-09-07',
        'OlusturmaTarihi': 'test',
      });
    }
    await db.insert('Ogrenci', {
      'OkulNo': 'eski',
      'Ad': 'Eski',
      'Soyad': 'Öğrenci',
      'OlusturmaTarihi': 'test',
    });
    await options.onUpgrade!.call(db, eskiSurum, 27);
    yukseltildi = true;
    return db;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory alan;
  late BireyselBakimService bakim;
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    alan = await Directory.systemTemp.createTemp('rehberlik_sema_');
    bakim = BireyselBakimService(
      databaseGetir: () async => db,
      alanGetir: () async => alan,
      modGetir: () async => CalismaModu.bireyselOgretmen,
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
    await db.insert('SinifSube', {
      'SinifKodu': '9/A',
      'RehberOgretmen': 'Öğretmen',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
  });
  tearDown(() async {
    await LocalDatabase.instance.close();
    await alan.delete(recursive: true);
  });
  Map<String, Object?> atama([Map<String, Object?> fark = const {}]) => {
    'OkulId': 'okul',
    'OgretmenProfilId': 1,
    'SinifSubeId': 1,
    'EgitimOgretimYili': '2026-2027',
    'BaslangicTarihi': '2026-09-07',
    'OlusturmaTarihi': 'test',
    ...fark,
  };
  Future<File> paket(File kaynak, void Function(Map) degistir) async {
    final archive = ZipDecoder().decodeBytes(await kaynak.readAsBytes());
    final meta =
        jsonDecode(
              utf8.decode(archive.findFile('yedek.json')!.content as List<int>),
            )
            as Map;
    degistir(meta);
    final bytes = utf8.encode(jsonEncode(meta));
    final sonuc = Archive()
      ..addFile(ArchiveFile('yedek.json', bytes.length, bytes));
    return File(
      '${alan.path}/deneme.zip',
    ).writeAsBytes(ZipEncoder().encode(sonuc)!);
  }

  test(
    'Yeni kurulum otomatik atama üretmez; ilişkiler ve tarihler korunur',
    () async {
      expect(await db.query('RehberlikAtama'), isEmpty);
      await db.insert('RehberlikAtama', atama());
      await expectLater(
        db.insert('RehberlikAtama', atama()),
        throwsA(anything),
      );
      for (final fark in <Map<String, Object?>>[
        {'OkulId': 'yok'},
        {'OgretmenProfilId': 999},
        {'SinifSubeId': 999},
        {'EgitimOgretimYili': '2027-2028'},
        {'BaslangicTarihi': '2026-02-30'},
        {'BaslangicTarihi': '2026-9-7'},
        {'BitisTarihi': '2026-09-06'},
        {'BitisTarihi': 'yanlış'},
      ]) {
        await expectLater(
          db.insert('RehberlikAtama', atama(fark)),
          throwsA(anything),
        );
      }
      for (final tablo in ['SinifSube', 'OgretmenProfil', 'OkulProfil']) {
        await expectLater(db.delete(tablo), throwsA(anything));
      }
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('Profil yılı ve sınıf aktifliği değişince eski atama korunur', () async {
    await db.insert('RehberlikAtama', atama({'BitisTarihi': '2027-06-25'}));
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027-2028'});
    await db.update('OkulProfil', {'EgitimYili': '2027-2028'});
    await db.update('SinifSube', {'Aktif': 0});
    expect(
      (await db.query('RehberlikAtama')).single['EgitimOgretimYili'],
      '2026-2027',
    );
    await expectLater(
      db.update('SinifSube', {'EgitimOgretimYili': '2027-2028'}),
      throwsA(anything),
    );
  });

  test('13 -> 17 gerçek yükseltme callback eski veriyi korur', () async {
    await LocalDatabase.instance.close();
    final factory = _YukseltmeFactory();
    databaseFactory = factory;
    db = await LocalDatabase.instance.database;
    expect(factory.yukseltildi, isTrue);
    expect((await db.query('Ogrenci')).single['OkulNo'], 'eski');
    expect(await db.query('RehberlikAtama'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test('14 -> 17 yükseltme mevcut atamayı korur', () async {
    await LocalDatabase.instance.close();
    databaseFactory = _YukseltmeFactory(14);
    db = await LocalDatabase.instance.database;
    expect(
      (await db.query('RehberlikAtama')).single['BaslangicTarihi'],
      '2026-09-07',
    );
    expect(await db.query('RehberlikKayit'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    '14 yedeği atama geçmişini geri getirir; sıfırlama bağımlılıkları siler',
    () async {
      await db.insert('RehberlikAtama', atama({'BitisTarihi': '2027-06-25'}));
      final yedek = await bakim.yedekle();
      expect(yedek.sayilar['RehberlikAtama'], 1);
      await LocalDatabase.instance.bireyselVerileriSifirla(
        onayMetni: 'SIFIRLA',
      );
      expect(await db.query('RehberlikAtama'), isEmpty);
      await bakim.geriYukle(
        await bakim.incele(yedek.dosya),
        onayMetni: 'GERİ YÜKLE',
      );
      expect(
        (await db.query('RehberlikAtama')).single['BitisTarihi'],
        '2027-06-25',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  for (final surum in [12, 13, 14]) {
    test('$surum yedeği boş atama tablosuyla geri yüklenir', () async {
      final yedek = await bakim.yedekle();
      final eski = await paket(yedek.dosya, (m) {
        m['sema'] = surum;
        eskiYedekAlanlariniAyir(m, surum);
        (m['tablolar'] as Map).remove('BireyselIslenenDers');
        (m['kolonlar'] as Map).remove('BireyselIslenenDers');
        (m['tablolar'] as Map).remove('BireyselGunlukPlan');
        (m['kolonlar'] as Map).remove('BireyselGunlukPlan');
        for (final t in RehberlikSemasi.modulTablolari) {
          (m['tablolar'] as Map).remove(t);
          (m['kolonlar'] as Map).remove(t);
        }
        if (surum < 14) {
          (m['tablolar'] as Map).remove('RehberlikAtama');
          (m['kolonlar'] as Map).remove('RehberlikAtama');
        }
        if (surum == 12) {
          for (final t in MesajlasmaSemasi.tablolar) {
            (m['tablolar'] as Map).remove(t);
            (m['kolonlar'] as Map).remove(t);
          }
          for (final f in MesajlasmaSemasi.iletisimAlanlari) {
            (m['kolonlar']['Ogrenci'] as List).remove(f);
          }
        }
      });
      await db.insert('RehberlikAtama', atama());
      final bilgi = await bakim.incele(eski);
      expect(bilgi.sayilar['RehberlikAtama'], 0);
      await bakim.geriYukle(bilgi, onayMetni: 'GERİ YÜKLE');
      expect(await db.query('RehberlikAtama'), isEmpty);
      expect(await db.query('SinifSube'), hasLength(1));
    });
  }

  test(
    'Sahte eski sürüm ve kopuk atama yedeği canlı veriyi değiştirmez',
    () async {
      await db.insert('RehberlikAtama', atama());
      final yedek = await bakim.yedekle();
      final sahte = await paket(yedek.dosya, (m) => m['sema'] = 13);
      await expectLater(bakim.incele(sahte), throwsA(isA<FormatException>()));
      final kopuk = await paket(
        yedek.dosya,
        (m) => m['tablolar']['RehberlikAtama'][0]['SinifSubeId'] = 999,
      );
      await expectLater(bakim.incele(kopuk), throwsA(anything));
      expect((await db.query('RehberlikAtama')).single['SinifSubeId'], 1);
    },
  );
}
