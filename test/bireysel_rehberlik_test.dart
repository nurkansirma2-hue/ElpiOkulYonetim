import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BireyselRehberlikService service;
  CalismaModu? mod;

  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    mod = CalismaModu.bireyselOgretmen;
    service = BireyselRehberlikService(
      databaseGetir: () async => db,
      modGetir: () async => mod,
    );
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
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
    for (var i = 1; i <= 4; i++) {
      final yil = i == 3 ? '2025/2026' : '2026/2027';
      await db.insert('SinifSube', {
        'SinifKodu': '9-${String.fromCharCode(64 + i)}',
        'SinifSeviyesi': 9,
        'RehberOgretmen': 'Öğretmen',
        'EgitimOgretimYili': yil,
        'Aktif': i == 4 ? 0 : 1,
        'OlusturmaTarihi': 'test',
      });
      if (i == 2) continue;
      await db.insert('DersProgrami', {
        'SinifSubeId': i,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': yil,
        'OlusturmaTarihi': 'test',
      });
    }
  });
  tearDown(() => LocalDatabase.instance.close());

  Future<int> kaydet(BireyselRehberlikBaglami b, String bas, [String? bit]) =>
      service.atamaKaydet(
        b,
        sinifSubeId: 1,
        baslangicTarihi: bas,
        bitisTarihi: bit,
      );

  test(
    'Kayıt ve sonlandırma geçmişi korur; sonraki gün yeni atama açılır',
    () async {
      final b = await service.hazirla();
      final id = await kaydet(b, '2026-09-07');
      await db.update('DersProgrami', {'Aktif': 0});
      await service.atamayiSonlandir(b, atamaId: id, bitisTarihi: '2026-10-11');
      final rows = await service.atamalariGetir(b);
      expect(rows.single['RehberlikAtamaId'], id);
      expect(rows.single['BitisTarihi'], '2026-10-11');
      expect(rows.single['GuncellemeTarihi'], isNotNull);
      await expectLater(
        service.atamayiSonlandir(b, atamaId: id, bitisTarihi: '2026-10-12'),
        throwsStateError,
      );
      await db.update('DersProgrami', {'Aktif': 1});
      await expectLater(kaydet(b, '2026-10-11'), throwsStateError);
      await kaydet(b, '2026-10-12');
      expect(await service.atamalariGetir(b), hasLength(2));
      expect(() => rows.single['BitisTarihi'] = null, throwsUnsupportedError);
    },
  );

  test(
    'Tarih çakışmaları ve hatalı tarihler kayıt oluşturmadan reddedilir',
    () async {
      final b = await service.hazirla();
      await kaydet(b, '2026-10-01', '2026-10-31');
      for (final aralik in [
        ['2026-10-01', '2026-10-31'],
        ['2026-10-10', '2026-10-20'],
        ['2026-09-01', '2026-11-01'],
        ['2026-09-01', '2026-10-01'],
        ['2026-10-31', null],
        ['2026-09-01', null],
      ]) {
        await expectLater(kaydet(b, aralik[0]!, aralik[1]), throwsStateError);
      }
      for (final tarih in [
        '2026-02-30',
        '2026-13-01',
        '2026-9-01',
        '',
        'abc',
      ]) {
        await expectLater(kaydet(b, tarih), throwsFormatException);
      }
      await expectLater(
        kaydet(b, '2026-10-01', '2026-09-30'),
        throwsFormatException,
      );
      await kaydet(b, '2026-09-01', '2026-09-30');
      await kaydet(b, '2026-11-01');
      expect(await service.atamalariGetir(b), hasLength(3));
    },
  );

  test('Kapsam dışı sınıflar, eski oturum ve kurumsal mod yazamaz', () async {
    final b = await service.hazirla();
    for (final id in [2, 3, 4, 999]) {
      await expectLater(
        service.atamaKaydet(b, sinifSubeId: id, baslangicTarihi: '2026-09-07'),
        throwsStateError,
      );
    }
    final id = await kaydet(b, '2026-09-07');
    await expectLater(
      service.atamayiSonlandir(b, atamaId: id, bitisTarihi: '2026-09-06'),
      throwsStateError,
    );
    await db.update('OgretmenProfil', {'AdSoyad': 'Değişti'});
    await expectLater(kaydet(b, '2026-11-01'), throwsStateError);
    await expectLater(
      service.atamayiSonlandir(b, atamaId: id, bitisTarihi: '2026-10-11'),
      throwsStateError,
    );
    mod = null;
    await expectLater(service.atamalariGetir(b), throwsStateError);
    await expectLater(kaydet(b, '2026-11-01'), throwsStateError);
    await expectLater(
      service.atamayiSonlandir(b, atamaId: id, bitisTarihi: '2026-10-11'),
      throwsStateError,
    );
    expect((await db.query('RehberlikAtama')).single['BitisTarihi'], isNull);
  });

  test('Geçmiş yıl programdan bağımsız okunur; geçmişe yazılmaz', () async {
    final b = await service.hazirla();
    final id = await kaydet(b, '2026-09-07');
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
    await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
    await db.update('DersProgrami', {'Aktif': 0});
    await db.update('SinifSube', {'Aktif': 0});
    final yeni = await service.hazirla();
    expect(await service.atamalariGetir(yeni), isEmpty);
    expect(
      await service.atamalariGetir(yeni, egitimOgretimYili: '2026/2027'),
      hasLength(1),
    );
    await expectLater(
      service.atamayiSonlandir(yeni, atamaId: id, bitisTarihi: '2027-06-25'),
      throwsStateError,
    );
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Başka',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2027/2028',
      'OlusturmaTarihi': 'test',
    });
    final baska = await service.hazirla();
    expect(
      await service.atamalariGetir(baska, egitimOgretimYili: '2026/2027'),
      isEmpty,
    );
    await expectLater(
      service.atamayiSonlandir(baska, atamaId: id, bitisTarihi: '2027-06-25'),
      throwsStateError,
    );
  });

  test('Eşzamanlı mükerrer kayıt yalnız bir atama oluşturur', () async {
    final b = await service.hazirla();
    final sonuc = await Future.wait([
      kaydet(
        b,
        '2026-09-07',
      ).then<Object>((id) => id, onError: (Object e) => e),
      kaydet(
        b,
        '2026-09-07',
      ).then<Object>((id) => id, onError: (Object e) => e),
    ]);
    expect(sonuc.whereType<int>(), hasLength(1));
    expect(sonuc.whereType<StateError>(), hasLength(1));
    expect(await db.query('RehberlikAtama'), hasLength(1));
  });

  test(
    'Yalnız aktif yıl ve ders kapsamı okunur; isim atama sayılmaz',
    () async {
      final before = await db.rawQuery('SELECT total_changes() AS n');
      final baglam = await service.hazirla();
      final rows = await service.siniflariGetir(baglam);
      expect(rows.map((r) => r['SinifKodu']), ['9-A']);
      expect(rows.single['RehberOgretmen'], 'Öğretmen');
      expect(await db.rawQuery('SELECT total_changes() AS n'), before);
      expect(() => rows.clear(), throwsUnsupportedError);
      expect(() => rows.single['SinifKodu'] = 'X', throwsUnsupportedError);
      await db.update('DersProgrami', {'Aktif': 0});
      expect(await service.siniflariGetir(baglam), isEmpty);
    },
  );

  test('Seçilmemiş mod veritabanı açılmadan reddedilir', () async {
    var acildi = false;
    final servis = BireyselRehberlikService(
      databaseGetir: () async {
        acildi = true;
        return db;
      },
      modGetir: () async => null,
    );
    await expectLater(servis.hazirla(), throwsStateError);
    expect(acildi, isFalse);
  });

  test('Tutarsız veya eksik kurulum reddedilir', () async {
    await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
    await expectLater(service.hazirla(), throwsStateError);
    await db.update('OkulProfil', {'EgitimYili': '2026/2027', 'AktifMi': 0});
    await expectLater(service.hazirla(), throwsStateError);
  });

  test(
    'Eski bağlam okul, öğretmen, yıl veya mod değişince reddedilir',
    () async {
      final baglam = await service.hazirla();
      await db.update('OkulProfil', {'OkulId': 'okul-2'});
      await expectLater(service.siniflariGetir(baglam), throwsStateError);
      await db.update('OkulProfil', {'OkulId': 'okul-1'});
      await db.update('OgretmenProfil', {'AdSoyad': 'Başka öğretmen'});
      await expectLater(service.siniflariGetir(baglam), throwsStateError);
      await db.update('OgretmenProfil', {
        'AdSoyad': 'Öğretmen',
        'EgitimOgretimYili': '2027/2028',
      });
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await expectLater(service.siniflariGetir(baglam), throwsStateError);
      mod = null;
      await expectLater(service.siniflariGetir(baglam), throwsStateError);
    },
  );
}
