import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/bilgi_toplama_semasi.dart';
import 'support/windows_memory_database.dart';

class _V19Factory extends WindowsMemoryFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final d = db = WindowsMemoryDatabase();
    await options!.onConfigure!(d);
    await d.execute(
      'CREATE TABLE Ogrenci(OgrenciId INTEGER PRIMARY KEY, OkulNo TEXT, Ad TEXT, Soyad TEXT, VeliAdi TEXT, VeliTelefonu TEXT)',
    );
    await d.execute('CREATE TABLE OkulProfil(OkulId TEXT PRIMARY KEY)');
    await d.execute(
      'CREATE TABLE OgretmenProfil(OgretmenProfilId INTEGER PRIMARY KEY)',
    );
    await d.execute(
      "INSERT INTO Ogrenci VALUES(1,'001','Eski','Öğrenci','Veli','05001234567')",
    );
    expect(options.version, 20);
    await options.onUpgrade!(d, 19, 20);
    return d;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => LocalDatabase.instance.close());
  tearDown(() async => LocalDatabase.instance.close());

  test(
    'v20 yedek geri yüklenir; v19 uyarlanır; sahte eski paket reddedilir',
    () async {
      databaseFactory = WindowsMemoryFactory();
      final db = await LocalDatabase.instance.database;
      final alan = await Directory.systemTemp.createTemp('bilgi_toplama_test_');
      try {
        final bakim = BireyselBakimService(
          databaseGetir: () async => db,
          alanGetir: () async => alan,
          modGetir: () async => CalismaModu.bireyselOgretmen,
        );
        await db.insert('Ogrenci', {
          'OkulNo': '001',
          'Ad': 'Ad',
          'Soyad': 'Soyad',
          'VeliTelefonu': '05001234567',
          'AnneAdi': 'Anne',
          'OlusturmaTarihi': 'test',
        });
        final yedek = await bakim.yedekle();
        await bakim.incele(yedek.dosya);
        await db.update('Ogrenci', {'AnneAdi': 'Değişti'});
        await bakim.geriYukle(
          await bakim.incele(yedek.dosya),
          onayMetni: 'GERİ YÜKLE',
        );
        expect((await db.query('Ogrenci')).single['AnneAdi'], 'Anne');
        final zip = ZipDecoder().decodeBytes(await yedek.dosya.readAsBytes());
        final meta =
            jsonDecode(
                  utf8.decode(zip.findFile('yedek.json')!.content as List<int>),
                )
                as Map;
        meta['sema'] = 19;
        Future<File> paket(String ad) async {
          final bytes = utf8.encode(jsonEncode(meta));
          final archive = Archive()
            ..addFile(ArchiveFile('yedek.json', bytes.length, bytes));
          return File(
            '${alan.path}/$ad.zip',
          ).writeAsBytes(ZipEncoder().encode(archive)!);
        }

        await expectLater(
          bakim.incele(await paket('sahte')),
          throwsA(anything),
        );
        for (final t in BilgiToplamaSemasi.tablolar) {
          (meta['tablolar'] as Map).remove(t);
          (meta['kolonlar'] as Map).remove(t);
        }
        (meta['kolonlar']['Ogrenci'] as List).removeWhere(
          BilgiToplamaSemasi.ogrenciAlanlari.contains,
        );
        for (final row in meta['tablolar']['Ogrenci'] as List) {
          for (final f in BilgiToplamaSemasi.ogrenciAlanlari) {
            (row as Map).remove(f);
          }
        }
        final eski = await bakim.incele(await paket('v19'));
        await bakim.geriYukle(eski, onayMetni: 'GERİ YÜKLE');
        final row = (await db.query('Ogrenci')).single;
        expect(row['OkulNo'], '001');
        expect(row['VeliTelefonu'], '05001234567');
        expect(row['AnneAdi'], isNull);
      } finally {
        // Yalnız bu testin oluşturduğu geçici klasör.
        await alan.delete(recursive: true);
      }
    },
  );

  test('v19 -> v20 mevcut kimlik ve veli bilgilerini korur', () async {
    databaseFactory = _V19Factory();
    final db = await LocalDatabase.instance.database;
    final row = (await db.query('Ogrenci')).single;
    expect(row['OkulNo'], '001');
    expect(row['Ad'], 'Eski');
    expect(row['VeliTelefonu'], '05001234567');
    for (final f in BilgiToplamaSemasi.ogrenciAlanlari) {
      expect(row.containsKey(f), isTrue);
      expect(row[f], isNull);
    }
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('yeni kurulum, cevap ilişkileri, tekrar ve sıfırlama', () async {
    databaseFactory = WindowsMemoryFactory();
    final db = await LocalDatabase.instance.database;
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
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    for (final id in [1, 2]) {
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'OkulNo': '00$id',
        'Ad': 'Ad',
        'Soyad': 'Soyad',
        'OlusturmaTarihi': 'test',
      });
    }
    for (final id in [1, 2]) {
      await db.insert('BilgiToplamaForm', {
        'Id': id,
        'OkulId': 'okul',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'Baslik': 'Form',
        'HedefTuru': 'OgrenciSec',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('BilgiToplamaHedef', {'FormId': id, 'OgrenciId': 1});
      await db.insert('BilgiToplamaSoru', {
        'Id': id,
        'FormId': id,
        'AlanAnahtari': 'beklenti',
        'Baslik': 'Beklenti',
        'VeriTuru': 'Metin',
        'Sira': 1,
      });
    }
    final cevap = <String, Object?>{
      'Id': 1,
      'FormId': 1,
      'GoogleYanitId': 'yanit',
      'KaynakSurum': 'v1',
      'FormSurum': 1,
      'GirilenOkulNo': 'yanlis',
      'GirilenAdSoyad': 'Farklı İsim',
      'GirilenSinif': '9/A',
      'HamYanit': '{}',
      'SoruAnlikGoruntusu': '{}',
      'OlusturmaTarihi': 'test',
    };
    await db.insert('BilgiToplamaYanit', cevap);
    expect(
      (await db.query('Ogrenci', where: 'OgrenciId=1')).single['Ad'],
      'Ad',
    );
    await expectLater(
      db.insert('BilgiToplamaYanit', {...cevap, 'Id': 2}),
      throwsA(anything),
    );
    await expectLater(
      db.update('BilgiToplamaYanit', {'Durum': 'Onaylandi'}, where: 'Id=1'),
      throwsA(anything),
    );
    await expectLater(
      db.update('BilgiToplamaYanit', {'OgrenciId': 2}, where: 'Id=1'),
      throwsA(anything),
    );
    await db.update('BilgiToplamaYanit', {
      'OgrenciId': 1,
      'Durum': 'Onaylandi',
      'OnaylayanProfilId': 1,
      'OnayTarihi': 'test',
    }, where: 'Id=1');
    await db.insert('BilgiToplamaEsleme', {
      'YanitId': 1,
      'FormId': 1,
      'YeniOgrenciId': 1,
      'KontrolEdenProfilId': 1,
      'Aciklama': 'Numara düzeltildi',
      'Tarih': 'test',
    });
    final deger = {
      'YanitId': 1,
      'FormId': 1,
      'SoruId': 1,
      'OgrenciId': 1,
      'Deger': 'Cevap',
    };
    await expectLater(
      db.insert('OgrenciEkBilgiDeger', {...deger, 'SoruId': 2}),
      throwsA(anything),
    );
    await expectLater(
      db.insert('OgrenciEkBilgiDeger', {...deger, 'OgrenciId': 2}),
      throwsA(anything),
    );
    await db.insert('OgrenciEkBilgiDeger', deger);
    expect(
      (await db.query('BilgiToplamaYanit')).single['GirilenOkulNo'],
      'yanlis',
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.update('OgretmenProfil', {'OkulAdi': 'Okul'});
    final yedekAlani = await Directory.systemTemp.createTemp(
      'bilgi_iliski_test_',
    );
    try {
      final bakim = BireyselBakimService(
        databaseGetir: () async => db,
        alanGetir: () async => yedekAlani,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final yedek = await bakim.yedekle();
      await bakim.geriYukle(
        await bakim.incele(yedek.dosya),
        onayMetni: 'GERİ YÜKLE',
      );
      expect((await db.query('OgrenciEkBilgiDeger')).single['Deger'], 'Cevap');
      expect(
        (await db.query('BilgiToplamaEsleme')).single['Aciklama'],
        'Numara düzeltildi',
      );
    } finally {
      await yedekAlani.delete(recursive: true);
    }
    await LocalDatabase.instance.bireyselVerileriSifirla(onayMetni: 'SIFIRLA');
    for (final t in BilgiToplamaSemasi.tablolar) {
      expect(await db.query(t), isEmpty);
    }
  });
}
