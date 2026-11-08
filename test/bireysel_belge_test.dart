import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/belge_arsivi_semasi.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/bireysel_belge.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_belgelerim_screen.dart';
import 'package:elpi_okul_yonetim/screens/ortak_import_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';

import 'support/windows_memory_database.dart';

// Dosya/SQLite davranışları yukarıdaki gerçek servis testlerinde doğrulanır.
// Görünüm testi native I/O'nun fake-clock ortamına bağlı kalmaz.
class _EkranBelgeService extends BireyselBelgeService {
  _EkranBelgeService(this.arsiv, this.belge);
  final BelgeArsivListesi arsiv;
  final BireyselBelge belge;
  String? sonArama;
  @override
  Future<List<BelgeKlasoru>> klasorleriGetir(String arsivId) async => [];
  @override
  Future<List<String>> yillariGetir(String arsivId) async => [];

  @override
  Future<BelgeArsivListesi> arsivleriGetir() async => arsiv;

  @override
  Future<List<BireyselBelge>> listele({
    required String arsivId,
    String arama = '',
    int offset = 0,
    int limit = 50,
    String? klasorId,
    bool tumKlasorler = true,
    String? tur,
    String? yil,
    bool copKutusu = false,
  }) async {
    sonArama = arama;
    return arama.isEmpty ? [belge] : [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory alan;
  late BireyselBelgeService service;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;

  Future<void> kurulum(String okulId, String okulAdi) async {
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': okulId,
      'OkulAdi': okulAdi,
      'OkulKisaAdi': okulAdi,
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Ayşe Öğretmen',
      'OkulAdi': okulAdi,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
  }

  PlatformFile kaynak(String ad, String icerik) => PlatformFile(
    name: ad,
    size: utf8.encode(icerik).length,
    readStream: Stream.value(utf8.encode(icerik)),
  );

  Future<BelgeEklemeSonucu> ekle(String ad, String icerik) async {
    final arsiv = (await service.arsivleriGetir()).aktif;
    return service.ekle(arsivId: arsiv.id, dosya: kaynak(ad, icerik));
  }

  setUp(() async {
    mod = CalismaModu.bireyselOgretmen;
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    // Her test kendi geçici alanını kullanır; kullanıcının dosyalarına erişmez.
    alan = await Directory.systemTemp.createTemp('belgelerim_test_');
    service = BireyselBelgeService(
      databaseGetir: () async => db,
      alanGetir: () async => alan,
      geciciAlanGetir: () async => alan,
      modGetir: () async => mod,
    );
    await kurulum('okul-1', 'Birinci Okul');
  });

  tearDown(() async {
    await LocalDatabase.instance.close();
    await alan.delete(recursive: true);
  });

  test(
    'Orijinal korunur; dosya SQLite dışında kalır ve yeniden açılışta okunur',
    () async {
      final orijinal = File(p.join(alan.path, 'kaynak.txt'));
      await orijinal.writeAsString('Özgün içerik');
      final arsiv = (await service.arsivleriGetir()).aktif;
      final sonuc = await service.ekle(
        arsivId: arsiv.id,
        dosya: PlatformFile(
          name: 'kaynak.txt',
          path: orijinal.path,
          size: await orijinal.length(),
        ),
      );
      expect(await orijinal.readAsString(), 'Özgün içerik');
      final yeni = BireyselBelgeService(
        databaseGetir: () async => db,
        alanGetir: () async => alan,
        geciciAlanGetir: () async => alan,
        modGetir: () async => mod,
      );
      final yol = await yeni.dosyaYolunuGetir(
        arsivId: arsiv.id,
        belgeId: sonuc.belge.id,
      );
      expect(yol, isNot(orijinal.path));
      expect(await File(yol).readAsString(), 'Özgün içerik');
      expect((await yeni.listele(arsivId: arsiv.id)).single.id, sonuc.belge.id);
      final kolonlar = await db.rawQuery('PRAGMA table_info(BireyselBelge)');
      expect(kolonlar.any((c) => c['type'] == 'BLOB'), isFalse);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'Aynı içerik farklı adla çoğalmaz; aynı adlı farklı içerik korunur',
    () async {
      final ilk = await ekle('liste.txt', 'birinci');
      final ayni = await ekle('farkli_ad.txt', 'birinci');
      final farkli = await ekle('liste.txt', 'ikinci');
      expect(ayni.zatenVar, isTrue);
      expect(ayni.belge.id, ilk.belge.id);
      expect(farkli.zatenVar, isFalse);
      expect(await db.query('BireyselBelge'), hasLength(2));
      final dosyalar = await Directory(
        p.join(alan.path, 'bireysel_belgeler'),
      ).list(recursive: true).where((e) => e is File).toList();
      expect(dosyalar, hasLength(2));
    },
  );

  test('Özet çakışması farklı içeriği tekrar saymaz', () async {
    final ilk = await ekle('bir.txt', 'AAAA');
    // Aday özeti eşitlenir; servis buna rağmen gerçek dosyaları karşılaştırmalı.
    final ikinciOzet =
        'crc32:${getCrc32(utf8.encode('BBBB')).toRadixString(16).padLeft(8, '0')}';
    await db.update(
      'BireyselBelge',
      {'IcerikOzeti': ikinciOzet},
      where: 'BelgeId = ?',
      whereArgs: [ilk.belge.id],
    );
    final ikinci = await ekle('iki.txt', 'BBBB');
    expect(ikinci.zatenVar, isFalse);
    expect(await db.query('BireyselBelge'), hasLength(2));
  });

  test(
    'Dış görüntüleyici yalnız geçici kopyayı değiştirir; kopyalar birikmez',
    () async {
      final belge = (await ekle('belge.txt', 'özgün')).belge;
      final orijinal = await service.dosyaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      final goruntu = await service.acmaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      expect(goruntu, isNot(orijinal));
      await File(goruntu).writeAsString('dış uygulamada değiştirildi');
      expect(await File(orijinal).readAsString(), 'özgün');
      final tekrar = await service.acmaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      expect(await File(tekrar).readAsString(), 'özgün');
      final diger = (await ekle('diger.txt', 'başka')).belge;
      await service.acmaYolunuGetir(arsivId: diger.arsivId, belgeId: diger.id);
      expect(
        await Directory(p.join(alan.path, 'belge_goruntuleme')).list().toList(),
        hasLength(1),
      );
      mod = null;
      await expectLater(
        service.acmaYolunuGetir(arsivId: belge.arsivId, belgeId: belge.id),
        throwsStateError,
      );
    },
  );

  test('Türkçe arama, sayfalama ve arşiv kapsamı korunur', () async {
    await ekle('ÖĞRENCİ ŞUBESİ.txt', '1');
    await ekle('başka.txt', '2');
    final arsiv = (await service.arsivleriGetir()).aktif;
    expect(
      (await service.listele(
        arsivId: arsiv.id,
        arama: 'ogrenci subesi',
      )).single.dosyaAdi,
      'ÖĞRENCİ ŞUBESİ.txt',
    );
    expect(await service.listele(arsivId: arsiv.id, arama: '%'), hasLength(2));
    final ilkSayfa = await service.listele(arsivId: arsiv.id, limit: 1);
    final ikinciSayfa = await service.listele(
      arsivId: arsiv.id,
      offset: 1,
      limit: 1,
    );
    expect(ilkSayfa.single.id, isNot(ikinciSayfa.single.id));
    await expectLater(service.listele(arsivId: 'yok'), throwsStateError);
  });

  test(
    'Boş, aşırı büyük, desteklenmeyen ve yarım dosya kayıt bırakmaz',
    () async {
      final arsiv = (await service.arsivleriGetir()).aktif;
      for (final dosya in [
        kaynak('bos.txt', ''),
        kaynak('program.exe', 'dosya'),
        PlatformFile(
          name: 'buyuk.txt',
          size: BireyselBelgeService.azamiBoyut + 1,
        ),
        PlatformFile(
          name: 'yarim.txt',
          size: 10,
          readStream: Stream.value([1, 2]),
        ),
        PlatformFile(
          name: 'artan.txt',
          size: 1,
          readStream: Stream.value([1, 2]),
        ),
        PlatformFile(
          name: 'hata.txt',
          size: 10,
          readStream: Stream.error(StateError('okuma hatası')),
        ),
      ]) {
        await expectLater(
          service.ekle(arsivId: arsiv.id, dosya: dosya),
          throwsA(anyOf(isA<Exception>(), isA<Error>())),
        );
      }
      expect(await db.query('BireyselBelge'), isEmpty);
      final dosyalar = await Directory(
        p.join(alan.path, 'bireysel_belgeler'),
      ).list(recursive: true).where((e) => e is File).toList();
      expect(dosyalar, isEmpty);
    },
  );

  test('Kurumsal modda okuma, ekleme ve açma durur', () async {
    final belge = (await ekle('belge.txt', 'içerik')).belge;
    mod = null;
    await expectLater(service.arsivleriGetir(), throwsStateError);
    await expectLater(
      service.listele(arsivId: belge.arsivId),
      throwsStateError,
    );
    await expectLater(
      service.ekle(arsivId: belge.arsivId, dosya: kaynak('yeni.txt', 'yeni')),
      throwsStateError,
    );
    await expectLater(
      service.dosyaYolunuGetir(arsivId: belge.arsivId, belgeId: belge.id),
      throwsStateError,
    );
  });

  test('Sıfırlama belgeleri korur; yeni okul eski arşive yazamaz', () async {
    final belge = (await ekle('eski.txt', 'eski içerik')).belge;
    await LocalDatabase.instance.bireyselVerileriSifirla(onayMetni: 'SIFIRLA');
    expect(await db.query('BireyselBelge'), hasLength(1));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await expectLater(service.arsivleriGetir(), throwsStateError);
    await kurulum('okul-2', 'İkinci Okul');
    final liste = await service.arsivleriGetir();
    expect(liste.arsivler, hasLength(2));
    expect(await service.listele(arsivId: liste.aktif.id), isEmpty);
    expect((await service.listele(arsivId: belge.arsivId)).single.id, belge.id);
    await expectLater(
      service.ekle(
        arsivId: belge.arsivId,
        dosya: kaynak('karisma.txt', 'yeni'),
      ),
      throwsStateError,
    );
    expect(
      await File(
        await service.dosyaYolunuGetir(
          arsivId: belge.arsivId,
          belgeId: belge.id,
        ),
      ).readAsString(),
      'eski içerik',
    );
  });

  test(
    'Kopyalama sırasında yıl değişince yanlış kapsama kayıt yapılmaz',
    () async {
      final arsiv = (await service.arsivleriGetir()).aktif;
      Stream<List<int>> degisenKaynak() async* {
        await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
        await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
        yield utf8.encode('içerik');
      }

      await expectLater(
        service.ekle(
          arsivId: arsiv.id,
          dosya: PlatformFile(
            name: 'yil.txt',
            size: utf8.encode('içerik').length,
            readStream: degisenKaynak(),
          ),
        ),
        throwsStateError,
      );
      expect(await db.query('BireyselBelge'), isEmpty);
    },
  );

  test(
    'Yarım kalmış kalıcılaştırma toparlanır; eksik dosya kayıt olarak korunur',
    () async {
      final belge = (await ekle('plan.txt', 'içerik')).belge;
      final yol = await service.dosyaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      await File(yol).rename('$yol.tmp');
      await db.update(
        'BireyselBelge',
        {'Durum': 'Hazirlaniyor'},
        where: 'BelgeId = ?',
        whereArgs: [belge.id],
      );
      expect(
        (await service.listele(arsivId: belge.arsivId)).single.acilabilir,
        isTrue,
      );
      expect(await File(yol).exists(), isTrue);
      await File(yol).delete();
      expect(
        (await service.listele(arsivId: belge.arsivId)).single.durum,
        'Eksik',
      );
      await expectLater(
        service.dosyaYolunuGetir(arsivId: belge.arsivId, belgeId: belge.id),
        throwsStateError,
      );
      expect(await db.query('BireyselBelge'), hasLength(1));
    },
  );

  test('Eksik klasör listeyi bozmaz; değiştirilmiş dosya açılmaz', () async {
    final belge = (await ekle('belge.txt', 'AAAA')).belge;
    final yol = await service.dosyaYolunuGetir(
      arsivId: belge.arsivId,
      belgeId: belge.id,
    );
    await File(yol).writeAsString('BBBB');
    await expectLater(
      service.dosyaYolunuGetir(arsivId: belge.arsivId, belgeId: belge.id),
      throwsStateError,
    );
    await File(yol).parent.delete(recursive: true);
    expect(
      (await service.listele(arsivId: belge.arsivId)).single.durum,
      'Eksik',
    );
  });

  test('Arşiv veya kayıtlı yol değiştirilerek başka dosya açılamaz', () async {
    final belge = (await ekle('belge.txt', 'içerik')).belge;
    await expectLater(
      service.dosyaYolunuGetir(arsivId: 'baska', belgeId: belge.id),
      throwsStateError,
    );
    await db.update(
      'BireyselBelge',
      {'GoreliYol': '../kaynak.txt'},
      where: 'BelgeId = ?',
      whereArgs: [belge.id],
    );
    await expectLater(
      service.dosyaYolunuGetir(arsivId: belge.arsivId, belgeId: belge.id),
      throwsStateError,
    );
  });

  test(
    'v10 üzerine belge şeması eklemek mevcut öğrenci kaydını korur',
    () async {
      final eski = WindowsMemoryDatabase();
      try {
        await eski.execute('PRAGMA foreign_keys = ON');
        await eski.execute(
          'CREATE TABLE Ogrenci (OgrenciId INTEGER PRIMARY KEY, Ad TEXT)',
        );
        await eski.insert('Ogrenci', {'OgrenciId': 1, 'Ad': 'Ali'});
        await eski.transaction((txn) => BelgeArsiviSemasi.hazirla(txn));
        expect((await eski.query('Ogrenci')).single['Ad'], 'Ali');
        expect(await eski.query('BireyselBelge'), isEmpty);
        expect(await eski.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await eski.close();
      }
    },
  );

  test(
    'Klasör taşıma, yeniden adlandırma ve tür/yıl filtreleri asıl dosyayı korur',
    () async {
      final belge = (await ekle('ilk.txt', 'orijinal')).belge;
      final yol = await service.dosyaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      await service.klasorKaydet(belge.arsivId, 'Yıllık Planlar');
      final klasor = (await service.klasorleriGetir(belge.arsivId)).single;
      await service.belgeyiDuzenle(
        belge,
        ad: 'yeni.txt',
        tur: 'Yıllık plan',
        tasi: true,
        klasorId: klasor.id,
      );
      final rows = await service.listele(
        arsivId: belge.arsivId,
        klasorId: klasor.id,
        tumKlasorler: false,
        tur: 'Yıllık plan',
        yil: '2026/2027',
      );
      expect(rows.single.dosyaAdi, 'yeni.txt');
      expect(rows.single.turElleSecildi, isTrue);
      expect(await File(yol).readAsString(), 'orijinal');
      expect(
        await service.listele(arsivId: belge.arsivId, tumKlasorler: false),
        isEmpty,
      );
      expect(
        await service.listele(arsivId: belge.arsivId, tur: 'Öğrenci listesi'),
        isEmpty,
      );
      await service.klasorSil(belge.arsivId, klasor.id);
      expect(
        (await service.listele(
          arsivId: belge.arsivId,
          tumKlasorler: false,
        )).single.klasorId,
        isNull,
      );
      expect(await service.klasorleriGetir(belge.arsivId), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'Hatalı ad, uzantı değişimi, tekrar klasör ve başka arşive taşıma reddedilir',
    () async {
      final belge = (await ekle('bir.txt', 'bir')).belge;
      for (final ad in ['', '../disari.txt', 'sahte.pdf']) {
        await expectLater(
          service.belgeyiDuzenle(belge, ad: ad),
          throwsFormatException,
        );
      }
      await service.klasorKaydet(belge.arsivId, 'Öğrenciler');
      await expectLater(
        service.klasorKaydet(belge.arsivId, 'ogrenciler'),
        throwsStateError,
      );
      await expectLater(
        service.belgeyiDuzenle(belge, tasi: true, klasorId: 'yok'),
        throwsStateError,
      );
      await expectLater(
        service.belgeyiDuzenle(belge, tur: 'uydurma'),
        throwsArgumentError,
      );
      expect(
        (await service.listele(arsivId: belge.arsivId)).single.dosyaAdi,
        'bir.txt',
      );
    },
  );

  test(
    'Çöp kutusu, geri alma ve tekrar dosya ekleme tek kopyayı korur',
    () async {
      final belge = (await ekle('bir.txt', 'içerik')).belge;
      await service.belgeyiDuzenle(belge, sil: true);
      expect(await service.listele(arsivId: belge.arsivId), isEmpty);
      expect(
        (await service.listele(
          arsivId: belge.arsivId,
          copKutusu: true,
        )).single.id,
        belge.id,
      );
      await expectLater(service.importKaynaginiGetir(belge), throwsStateError);
      await service.belgeyiDuzenle(belge, sil: false);
      expect(await service.listele(arsivId: belge.arsivId), hasLength(1));
      await service.belgeyiDuzenle(belge, sil: true);
      final tekrar = await ekle('baska.txt', 'içerik');
      expect(tekrar.zatenVar, isTrue);
      expect(tekrar.belge.silinmeTarihi, isNull);
      expect(await service.listele(arsivId: belge.arsivId), hasLength(1));
      expect(await db.query('BireyselBelge'), hasLength(1));
    },
  );

  test(
    'Kalıcı silme yalnız açık onayla çöp kutusunda çalışır, geçmiş ve özel kopya kaldırılır',
    () async {
      final belge = (await ekle('bir.txt', 'orijinal')).belge;
      final yol = await service.dosyaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      await expectLater(
        service.kaliciSil(belge, onay: 'SİL'),
        throwsStateError,
      );
      await service.belgeyiDuzenle(belge, sil: true);
      await expectLater(
        service.kaliciSil(belge, onay: 'evet'),
        throwsStateError,
      );
      await service.kaliciSil(belge, onay: 'SİL');
      expect(await File(yol).exists(), isFalse);
      expect(await db.query('BireyselBelge'), isEmpty);
      expect(await db.query('BelgeSilmeBekleyen'), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'Import geçmişi yalnız doğru arşiv/yıl kapsamına yazılır ve listeye işaret koyar',
    () async {
      final belge = (await ekle(
        'liste.csv',
        'Okul No;Ad;Soyad\n1;Ali;Yılmaz',
      )).belge;
      final kaynak = await service.importKaynaginiGetir(belge);
      await service.importKapsaminiDogrula(kaynak);
      await service.importSonucunuKaydet(
        kaynak,
        'Öğrenci Import',
        const ImportOzet(
          eklenen: 1,
          guncellenen: 2,
          atlanan: 3,
          hatali: 0,
          mesaj: 'Tamam',
        ),
      );
      final gecmis = await service.gecmis(belge);
      expect(gecmis.single.eklenen, 1);
      expect(gecmis.single.guncellenen, 2);
      expect(
        (await service.listele(arsivId: belge.arsivId)).single.sonImport,
        isNotNull,
      );
      await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await expectLater(
        service.importKapsaminiDogrula(kaynak),
        throwsStateError,
      );
      await expectLater(
        service.importSonucunuKaydet(
          kaynak,
          'Öğrenci Import',
          const ImportOzet(
            eklenen: 1,
            guncellenen: 0,
            atlanan: 0,
            hatali: 0,
            mesaj: 'Yanlış yıl',
          ),
        ),
        throwsStateError,
      );
      expect(await service.gecmis(belge), hasLength(1));
    },
  );

  test('Elle düzeltilmiş genel tür yeniden analizde değişmez', () async {
    final belge = (await ekle('bir.txt', 'içerik')).belge;
    await service.analizKaydet(belge, '{}', 'Öğrenci listesi');
    final otomatik = await service.belgeGetir(belge.arsivId, belge.id);
    expect(otomatik.belgeTuru, 'Öğrenci listesi');
    await service.belgeyiDuzenle(otomatik, tur: 'Genel belge');
    final elle = await service.belgeGetir(belge.arsivId, belge.id);
    await service.analizKaydet(elle, '{"yeniden":true}', 'Yıllık plan');
    expect(
      (await service.belgeGetir(belge.arsivId, belge.id)).belgeTuru,
      'Genel belge',
    );
  });

  test(
    'Eski arşiv ve kurumsal mod dosya yönetimine/importa kapalıdır',
    () async {
      final belge = (await ekle('bir.txt', 'bir')).belge;
      await LocalDatabase.instance.bireyselVerileriSifirla(
        onayMetni: 'SIFIRLA',
      );
      await kurulum('okul-2', 'İkinci Okul');
      await expectLater(service.importKaynaginiGetir(belge), throwsStateError);
      await expectLater(
        service.belgeyiDuzenle(belge, sil: true),
        throwsStateError,
      );
      await expectLater(
        service.klasorKaydet(belge.arsivId, 'yeni'),
        throwsStateError,
      );
      mod = null;
      await expectLater(
        service.klasorleriGetir(belge.arsivId),
        throwsStateError,
      );
      await expectLater(
        service.belgeyiDuzenle(belge, ad: 'yeni.txt'),
        throwsStateError,
      );
      await expectLater(
        service.yedekDosyaListesi(belge.arsivId),
        throwsStateError,
      );
    },
  );

  test(
    'Yedek dosya manifesti bütünlüğü doğrular, eksik dosyayı sessiz atlamaz',
    () async {
      final belge = (await ekle('bir.txt', 'bir')).belge;
      expect(await service.yedekDosyaListesi(belge.arsivId), hasLength(1));
      final yol = await service.dosyaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      await File(yol).delete();
      await expectLater(
        service.yedekDosyaListesi(belge.arsivId),
        throwsStateError,
      );
    },
  );

  test(
    'v11 belge yönetimi yükseltmesi eski belge metaverisini korur',
    () async {
      final eski = WindowsMemoryDatabase();
      try {
        await BelgeArsiviSemasi.hazirla(eski);
        await eski.insert('BelgeArsivi', {
          'ArsivId': 'arsiv',
          'OkulId': 'okul',
          'OgretmenProfilId': 1,
          'OkulAdi': 'Okul',
          'OgretmenAdi': 'Öğretmen',
          'OlusturmaTarihi': 'test',
        });
        await eski.insert('BireyselBelge', {
          'BelgeId': 'belge',
          'ArsivId': 'arsiv',
          'DosyaAdi': 'eski.txt',
          'AramaAdi': 'eski',
          'GoreliYol': 'arsiv/belge.txt',
          'Uzanti': 'txt',
          'Boyut': 1,
          'EgitimOgretimYili': '2026/2027',
          'EklenmeTarihi': 'test',
          'Durum': 'Hazir',
        });
        await BelgeArsiviSemasi.yonetimiHazirla(eski);
        final row = (await eski.query('BireyselBelge')).single;
        expect(row['DosyaAdi'], 'eski.txt');
        expect(row['BelgeTuru'], 'Genel belge');
        expect(row['SilinmeTarihi'], isNull);
        expect(await eski.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await eski.close();
      }
    },
  );

  testWidgets(
    'Arşivden dosya mevcut ön izleme/onaya gider; geçmiş yalnız gerçek kayıt sonrası yazılır',
    (tester) async {
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      final belge = await tester.runAsync(
        () async => (await ekle('liste.csv', 'Ad\nAli')).belge,
      );
      final kaynak = await tester.runAsync(
        () => service.importKaynaginiGetir(belge!),
      );
      final file = ImportDosya(
        'liste.csv',
        Uint8List.fromList(utf8.encode('Ad\nAli')),
        belgeKaynagi: kaynak,
      );
      final definition = ImportTanimi(
        id: 'test',
        ad: 'Deneme Import',
        alanlar: const [ImportAlan('ad', 'Ad', zorunlu: true)],
        aciklama: 'Onayla kaydet.',
        hazirla: (rows) async => ImportOnIzleme(
          rows.map((r) => ImportKaydi(r.id, r.konum, r.degerler)).toList(),
        ),
        aktar: (preview, selected) async {
          await db.insert('Ogrenci', {
            'OkulNo': '101',
            'Ad': 'Ali',
            'Soyad': 'Test',
            'OlusturmaTarihi': 'test',
          });
          return const ImportOzet(
            eklenen: 1,
            guncellenen: 0,
            atlanan: 0,
            hatali: 0,
            mesaj: 'Kaydedildi',
          );
        },
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: OrtakImportScreen(
              tanim: definition,
              baslangicDosyasi: file,
              belgeService: service,
            ),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();
      Future<void> tap(String text) async {
        final finder = find.text(text);
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            300,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(finder);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 350));
        });
        await tester.pumpAndSettle();
      }

      await tap('Ön İzleme Hazırla');
      await tap('Tüm Aktarılabilirleri Seç');
      expect(await tester.runAsync(() => db.query('Ogrenci')), isEmpty);
      expect(await tester.runAsync(() => service.gecmis(belge!)), isEmpty);
      await tap('1 Seçili Kaydı Aktar');
      expect(await tester.runAsync(() => db.query('Ogrenci')), isEmpty);
      await tap('Onayla ve Aktar');
      expect(await tester.runAsync(() => db.query('Ogrenci')), hasLength(1));
      expect(
        (await tester.runAsync(() => service.gecmis(belge!)))!.single.eklenen,
        1,
      );
      final yol = await tester.runAsync(
        () => service.dosyaYolunuGetir(
          arsivId: belge!.arsivId,
          belgeId: belge.id,
        ),
      );
      expect(await tester.runAsync(() => File(yol!).readAsString()), 'Ad\nAli');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dar ekranda uzun belge adı listelenir ve Türkçe arama çalışır', (
    tester,
  ) async {
    final sonuc = await tester.runAsync(
      () => ekle('${List.filled(80, 'Ö').join()}.txt', 'içerik'),
    );
    final arsivler = await tester.runAsync(service.arsivleriGetir);
    final ekranService = _EkranBelgeService(arsivler!, sonuc!.belge);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: BireyselBelgelerimScreen(service: ekranService)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belge Ekle'), findsOneWidget);
    expect(find.byKey(ValueKey(sonuc.belge.id)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Filtreler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bulunmayan');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Aramanıza uygun belge bulunamadı.'), findsOneWidget);
    expect(ekranService.sonArama, 'bulunmayan');
    expect(tester.takeException(), isNull);
  });
}
