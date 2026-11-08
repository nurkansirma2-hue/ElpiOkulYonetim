import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/bireysel_gunluk_plan.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_gunluk_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';
import 'support/eski_yedek_fixture.dart';
import 'package:elpi_okul_yonetim/database/bilgi_toplama_semasi.dart';
import 'support/gunluk_plan_fixture.dart';
import 'package:elpi_okul_yonetim/database/rehberlik_semasi.dart';

// Native sqflite aynı bağlantının transaction işlemlerini sıraya koyar.
// Ortak bellek yardımcısının _depth kontrolü ise iki eşzamanlı transaction'ı
// iç içe çağrı kabul eder. Bu test dosyasında gerçek bağlantı sırası korunur.
class _SiraliBellekDatabase extends WindowsMemoryDatabase {
  Future<void> _sira = Future.value();

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    final sonuc = _sira.then(
      (_) => super.transaction(action, exclusive: exclusive),
    );
    _sira = sonuc.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return sonuc;
  }
}

class _SiraliBellekFactory extends WindowsMemoryFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final database = db = _SiraliBellekDatabase();
    await options?.onConfigure?.call(database);
    await options?.onCreate?.call(database, options.version!);
    await options?.onOpen?.call(database);
    return database;
  }
}

// v15 sonrasında eklenen tablolar çıkarılıp gerçek onUpgrade çalıştırılır.
// DROP yalnız bu teste ait :memory: veritabanında uygulanır.
class _V15YukseltmeFactory extends WindowsMemoryFactory {
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
    for (final t in RehberlikSemasi.googleTablolari.reversed) {
      await db.execute('DROP TABLE $t');
    }
    await db.execute('DROP TABLE MesajSms');
    await db.execute('DROP TABLE BireyselGunlukPlan');
    await db.insert('Ogrenci', {
      'OkulNo': 'v15',
      'Ad': 'Eski',
      'Soyad': 'Öğrenci',
      'OlusturmaTarihi': 'test',
    });
    await options.onUpgrade!.call(db, 15, 27);
    yukseltildi = true;
    return db;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  Directory? alan;
  const yil = '2026 / 2027';
  final tarih = DateTime(2026, 10, 14);

  Future<BireyselGunlukPlan> hazirla({
    int sinif = 1,
    DateTime? gun,
    int profil = 1,
    String egitimYili = yil,
    int ders = 1,
    int seviye = 9,
  }) => BireyselGunlukPlanService.hazirla(
    ogretmenProfilId: profil,
    egitimOgretimYili: egitimYili,
    dersId: ders,
    sinifSeviyesi: seviye,
    sinifSubeId: sinif,
    tarih: gun ?? tarih,
  );

  Future<int> planEkle({
    String konu = 'Denklemler',
    String? kazanim = 'Denklem çözer.',
    String? ogrenme = 'Çözümünü açıklar.',
    String? yontem = 'Soru cevap',
    String? arac = 'Ders kitabı',
    String? degerlendirme = 'Çıkış bileti',
    String? bas = '2026-10-12',
    String? bit = '2026-10-16',
  }) async {
    final id = await db.insert('YillikPlan', {
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'DersId': 1,
      'SinifSeviyesi': 9,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': id,
      'HaftaNo': 6,
      'BaslangicTarihi': bas,
      'BitisTarihi': bit,
      'Konu': konu,
      'Kazanim': kazanim,
      'OgrenmeCiktisi': ogrenme,
      'YontemTeknik': yontem,
      'AracGerec': arac,
      'Degerlendirme': degerlendirme,
      'OlusturmaTarihi': 'test',
    });
    return id;
  }

  Future<Map<String, List<Map<String, Object?>>>> digerVeriler() async {
    final tablolar = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'BireyselGunlukPlan' "
      'ORDER BY name',
    );
    return {
      for (final t in tablolar)
        t['name'] as String: await db.query(
          t['name'] as String,
          where: t['name'] == 'UygulamaAyarlari'
              ? "Anahtar NOT LIKE 'gunlukPlan.%'"
              : null,
        ),
    };
  }

  Future<void> programEkle({
    required int sinif,
    int ders = 1,
    int profil = 1,
    String egitimYili = yil,
    int seviye = 9,
    int aktif = 1,
    bool program = true,
  }) async {
    await db.insert('SinifSube', {
      'SinifSubeId': sinif,
      'SinifKodu': '$seviye-${String.fromCharCode(64 + sinif)}',
      'SinifSeviyesi': seviye,
      'EgitimOgretimYili': egitimYili,
      'Aktif': aktif,
      'OlusturmaTarihi': 'test',
    });
    if (!program) return;
    await db.insert('DersProgrami', {
      'SinifSubeId': sinif,
      'DersId': ders,
      'DersSaatiId': 1,
      'Gun': 'Çarşamba',
      'Baslangic': '08:00',
      'Bitis': '08:40',
      'OgretmenProfilId': profil,
      'EgitimOgretimYili': egitimYili,
      'OlusturmaTarihi': 'test',
    });
  }

  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = _SiraliBellekFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    alan = null;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Test Okulu',
      'OkulKisaAdi': 'TO',
      'EgitimYili': yil,
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    for (var id = 1; id <= 2; id++) {
      await db.insert('OgretmenProfil', {
        'OgretmenProfilId': id,
        'AdSoyad': id == 1 ? 'Ayşe Öğretmen' : 'Başka Öğretmen',
        'OkulAdi': 'Test Okulu',
        'EgitimOgretimYili': yil,
        'Aktif': id == 1 ? 1 : 0,
        'OlusturmaTarihi': 'test',
      });
    }
    for (var id = 1; id <= 2; id++) {
      await db.insert('Ders', {
        'DersId': id,
        'DersAdi': id == 1 ? 'Matematik' : 'Fizik',
        'OlusturmaTarihi': 'test',
      });
    }
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    await programEkle(sinif: 1);
    await planEkle();
    await gunlukPlanTestDbfEkle(db, ayrintili: false);
  });

  tearDown(() async {
    await LocalDatabase.instance.close();
    final directory = alan;
    if (directory != null) {
      expect(
        p.isWithin(Directory.systemTemp.absolute.path, directory.absolute.path),
        isTrue,
      );
      expect(p.basename(directory.path), startsWith('gunluk_plan_test_'));
      await directory.delete(recursive: true);
    }
  });

  test(
    'Mevcut bilgiler ve aynı tarihin tüm plan satırları ön doldurulur',
    () async {
      final plan = await planEkle();
      await db.insert('YillikPlanDetay', {
        'YillikPlanId': plan,
        'HaftaNo': 6,
        'BaslangicTarihi': '2026-10-12',
        'BitisTarihi': '2026-10-16',
        'Konu': 'Problemler',
        'Kazanim': 'Problem kurar.',
        'YontemTeknik': 'Grup çalışması',
        'AracGerec': 'Çalışma kâğıdı',
        'Degerlendirme': 'Öz değerlendirme',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('YillikPlanDetay', {
        'YillikPlanId': plan,
        'BaslangicTarihi': '2026-10-19',
        'BitisTarihi': '2026-10-23',
        'Konu': 'Sonraki haftanın konusu',
        'OlusturmaTarihi': 'test',
      });
      final once = await digerVeriler();
      final taslak = await hazirla(gun: DateTime(2026, 10, 14, 23, 59));
      expect(taslak.id, isNull);
      expect(taslak.surum, 0);
      expect(taslak.okulId, 'okul-1');
      expect(taslak.ogretmenAdi, 'Ayşe Öğretmen');
      expect(taslak.okulAdi, 'Test Okulu');
      expect(taslak.egitimOgretimYili, '2026-2027');
      expect(taslak.dersAdi, 'Matematik');
      expect(taslak.sinifKodu, '9-A');
      expect(taslak.tarih, DateTime(2026, 10, 12));
      expect(
        taslak.konu,
        allOf(contains('Denklemler'), contains('Problemler')),
      );
      expect(taslak.konu, isNot(contains('Sonraki haftanın konusu')));
      expect(
        taslak.kazanim,
        allOf(contains('Denklem çözer.'), contains('Problem kurar.')),
      );
      expect(taslak.ogrenmeCiktisi, contains('Çözümünü açıklar.'));
      expect(
        taslak.yontemTeknik,
        allOf(contains('Soru cevap'), contains('Grup çalışması')),
      );
      expect(
        taslak.aracGerec,
        allOf(contains('Ders kitabı'), contains('Çalışma kâğıdı')),
      );
      expect(
        taslak.degerlendirme,
        allOf(contains('Çıkış bileti'), contains('Öz değerlendirme')),
      );
      expect(taslak.dersinIslenisi, isEmpty);
      expect(taslak.etkinlikler, isEmpty);
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
      expect(await digerVeriler(), once);
    },
  );

  test(
    'Eksik kaynak alanları boş kalır; öğretmen elle tamamlayabilir',
    () async {
      await planEkle(
        kazanim: null,
        ogrenme: null,
        yontem: null,
        arac: null,
        degerlendirme: null,
      );
      final taslak = await hazirla();
      expect(taslak.kazanim, isEmpty);
      expect(taslak.yontemTeknik, isEmpty);
      expect(taslak.aracGerec, isEmpty);
      expect(taslak.degerlendirme, isEmpty);
      final kayit = await BireyselGunlukPlanService.kaydet(
        taslak.copyWith(
          kazanim: 'Elle girilen kazanım',
          yontemTeknik: 'Gösterip yaptırma',
          aracGerec: 'Öğretmen materyali',
          degerlendirme: 'Kontrol listesi',
          dersinIslenisi: 'Önce önceki ders hatırlatılır.',
          etkinlikler: 'İkili çalışma yapılır.',
        ),
      );
      final acilan = await hazirla();
      expect(acilan.id, kayit.id);
      expect(acilan.kazanim, 'Elle girilen kazanım');
      expect(acilan.yontemTeknik, 'Gösterip yaptırma');
      expect(acilan.aracGerec, 'Öğretmen materyali');
      expect(acilan.degerlendirme, 'Kontrol listesi');
      expect(acilan.dersinIslenisi, 'Önce önceki ders hatırlatılır.');
      expect(acilan.etkinlikler, 'İkili çalışma yapılır.');
    },
  );

  test(
    'Kaynak veya tarih eşleşmesi yoksa tarih/hafta tahmin edilmez',
    () async {
      await db.delete('YillikPlanDetay');
      await db.delete('YillikPlan');
      await expectLater(hazirla(), throwsStateError);
      await planEkle(bas: null, bit: null);
      await expectLater(hazirla(), throwsStateError);
      await planEkle(bas: '2026-12-28', bit: '2027-01-01');
      await expectLater(hazirla(gun: DateTime(2026, 12, 27)), throwsStateError);
      expect((await hazirla(gun: DateTime(2026, 12, 28))).konu, 'Denklemler');
      expect(
        (await hazirla(gun: DateTime(2027, 1, 1, 23, 59))).konu,
        'Denklemler',
      );
      await expectLater(hazirla(gun: DateTime(2027, 1, 2)), throwsStateError);
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
    },
  );

  test(
    'Şube seçimi yalnız öğretmenin aynı ders, seviye ve yıl kapsamındadır',
    () async {
      await programEkle(sinif: 2);
      await programEkle(sinif: 3, ders: 2);
      await programEkle(sinif: 4, profil: 2);
      await programEkle(sinif: 5, egitimYili: '2025/2026');
      await programEkle(sinif: 6, aktif: 0);
      await programEkle(sinif: 7, seviye: 10);
      await programEkle(sinif: 8, program: false);
      final secenekler = await BireyselGunlukPlanService.siniflariGetir(
        ogretmenProfilId: 1,
        egitimOgretimYili: yil,
        dersId: 1,
        sinifSeviyesi: 9,
      );
      expect(secenekler.map((s) => s.sinifSubeId), unorderedEquals([1, 2]));
      for (final id in [3, 4, 5, 6, 7, 8, 999]) {
        await expectLater(hazirla(sinif: id), throwsStateError);
      }
      final a = await BireyselGunlukPlanService.kaydet(await hazirla());
      final b = await BireyselGunlukPlanService.kaydet(await hazirla(sinif: 2));
      expect(a.id, isNot(b.id));
      expect(await db.query('BireyselGunlukPlan'), hasLength(2));
    },
  );

  test(
    'Kaydet ve düzenle aynı planı korur; tekrar açılış kaynakla üzerine yazmaz',
    () async {
      await planEkle();
      final taslak = await hazirla();
      final ilk = await BireyselGunlukPlanService.kaydet(
        taslak.copyWith(
          konu: 'Öğretmenin düzelttiği konu',
          kazanim: '',
          dersinIslenisi: 'Ön bilgi yoklanır. Örnek çözülür.',
          etkinlikler: 'Öğrenciler model oluşturur.',
        ),
      );
      expect(ilk.id, isNotNull);
      expect(ilk.surum, 1);
      await db.update('YillikPlan', {'Aktif': 0});
      await planEkle(konu: 'Yeniden import edilmiş konu');
      final tekrar = await hazirla(egitimYili: '2026-2027');
      expect(tekrar.id, ilk.id);
      expect(tekrar.konu, 'Öğretmenin düzelttiği konu');
      expect(tekrar.kazanim, isEmpty);
      expect(tekrar.etkinlikler, 'Öğrenciler model oluşturur.');
      final duzenlenen = await BireyselGunlukPlanService.kaydet(
        tekrar.copyWith(dersinIslenisi: 'Öğretmenin ikinci düzenlemesi'),
      );
      expect(duzenlenen.id, ilk.id);
      expect(duzenlenen.surum, 2);
      expect(
        (await BireyselGunlukPlanService.getir(ilk.id!)).dersinIslenisi,
        'Öğretmenin ikinci düzenlemesi',
      );
      expect(await db.query('BireyselGunlukPlan'), hasLength(1));
      await expectLater(
        BireyselGunlukPlanService.kaydet(taslak),
        throwsStateError,
      );
      await expectLater(
        BireyselGunlukPlanService.kaydet(ilk),
        throwsStateError,
      );
      expect((await hazirla()).surum, 2);
    },
  );

  test('Aynı anda aynı taslağı kaydetmek ikinci plan oluşturmaz', () async {
    final taslak = await hazirla();
    final sonuc = await Future.wait([
      BireyselGunlukPlanService.kaydet(
        taslak,
      ).then<Object>((p) => p, onError: (Object e) => e),
      BireyselGunlukPlanService.kaydet(
        taslak,
      ).then<Object>((p) => p, onError: (Object e) => e),
    ]);
    expect(
      sonuc.whereType<BireyselGunlukPlan>(),
      hasLength(1),
      reason: sonuc.map((r) => '${r.runtimeType}: $r').join('\n'),
    );
    expect(sonuc.whereType<StateError>(), hasLength(1));
    expect(await db.query('BireyselGunlukPlan'), hasLength(1));
  });

  test(
    'Hazırlama ve kaydetme yıllık plan, takvim veya başka kayıt üretmez',
    () async {
      await planEkle();
      final once = await digerVeriler();
      final kayit = await BireyselGunlukPlanService.kaydet(
        (await hazirla()).copyWith(
          dersinIslenisi: 'Ders için hazırlanmış plan',
        ),
      );
      await BireyselGunlukPlanService.getir(kayit.id!);
      expect(await digerVeriler(), once);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'Eski okul, profil, yıl ve kurumsal mod bağlamı okuyamaz veya yazamaz',
    () async {
      final taslak = await hazirla();
      final kayit = await BireyselGunlukPlanService.kaydet(taslak);
      Future<void> reddedilir() async {
        await expectLater(hazirla(), throwsStateError);
        await expectLater(
          BireyselGunlukPlanService.getir(kayit.id!),
          throwsStateError,
        );
        await expectLater(
          BireyselGunlukPlanService.kaydet(kayit.copyWith(konu: 'Yazılmamalı')),
          throwsStateError,
        );
      }

      await db.update('OkulProfil', {'AktifMi': 0});
      await reddedilir();
      await db.update('OkulProfil', {'AktifMi': 1});
      await db.update('OgretmenProfil', {
        'Aktif': 0,
      }, where: 'OgretmenProfilId = 1');
      await db.update('OgretmenProfil', {
        'Aktif': 1,
      }, where: 'OgretmenProfilId = 2');
      await reddedilir();
      await db.update('OgretmenProfil', {
        'Aktif': 0,
      }, where: 'OgretmenProfilId = 2');
      await db.update('OgretmenProfil', {
        'Aktif': 1,
      }, where: 'OgretmenProfilId = 1');
      await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
      await db.update('OgretmenProfil', {
        'EgitimOgretimYili': '2027/2028',
      }, where: 'OgretmenProfilId = 1');
      await reddedilir();
      await db.update('OkulProfil', {'EgitimYili': yil});
      await db.update('OgretmenProfil', {
        'EgitimOgretimYili': yil,
      }, where: 'OgretmenProfilId = 1');
      SharedPreferences.setMockInitialValues({'calisma_modu': 'okul'});
      await reddedilir();
      expect((await db.query('BireyselGunlukPlan')).single['Konu'], kayit.konu);
    },
  );

  test('15 → 19 gerçek yükseltmesi mevcut veriyi korur', () async {
    await LocalDatabase.instance.close();
    final factory = _V15YukseltmeFactory();
    databaseFactory = factory;
    db = await LocalDatabase.instance.database;
    expect(factory.yukseltildi, isTrue);
    expect((await db.query('Ogrenci')).single['OkulNo'], 'v15');
    expect(await db.query('BireyselGunlukPlan'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    '19 yedeği günlük düzenlemeleri geri getirir; 15 yedeği boş günlük tabloyla yüklenir',
    () async {
      alan = await Directory.systemTemp.createTemp('gunluk_plan_test_');
      final belge = BireyselBelgeService(
        databaseGetir: () async => db,
        alanGetir: () async => alan!,
        geciciAlanGetir: () async => alan!,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      // Sıfırlama arşivleri korur; günlük verisini yeni kuruluma taşımaz.
      final arsiv = (await belge.arsivleriGetir()).aktif;
      final bakim = BireyselBakimService(
        databaseGetir: () async => db,
        alanGetir: () async => alan!,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      final kayit = await BireyselGunlukPlanService.kaydet(
        (await hazirla()).copyWith(
          dersinIslenisi: 'Yedeklenen işleniş',
          etkinlikler: 'Yedeklenen etkinlik',
        ),
      );
      final yedek = await bakim.yedekle();
      expect(yedek.sayilar['BireyselGunlukPlan'], 1);
      final zip = ZipDecoder().decodeBytes(await yedek.dosya.readAsBytes());
      final meta =
          jsonDecode(
                utf8.decode(zip.findFile('yedek.json')!.content as List<int>),
              )
              as Map;
      expect(meta['sema'], 27);
      final ekBilgi = (await BireyselGunlukPlanService.getir(
        kayit.id!,
      )).planBilgisi;
      expect(ekBilgi['kaynaklar'], isNotEmpty);
      await LocalDatabase.instance.bireyselVerileriSifirla(
        onayMetni: 'SIFIRLA',
      );
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
      expect((await db.query('BelgeArsivi')).single['ArsivId'], arsiv.id);
      await bakim.geriYukle(
        await bakim.incele(yedek.dosya),
        onayMetni: 'GERİ YÜKLE',
      );
      final geri = await BireyselGunlukPlanService.getir(kayit.id!);
      expect(geri.dersinIslenisi, 'Yedeklenen işleniş');
      expect(geri.etkinlikler, 'Yedeklenen etkinlik');
      expect(geri.planBilgisi['kaynaklar'], ekBilgi['kaynaklar']);
      meta['sema'] = 15;
      eskiYedekAlanlariniAyir(meta, 15);
      for (final t in [...RehberlikSemasi.googleTablolari, 'MesajSms']) {
        (meta['tablolar'] as Map).remove(t);
        (meta['kolonlar'] as Map).remove(t);
      }
      (meta['tablolar'] as Map).remove('BireyselIslenenDers');
      (meta['kolonlar'] as Map).remove('BireyselIslenenDers');
      (meta['tablolar'] as Map).remove('BireyselGunlukPlan');
      (meta['kolonlar'] as Map).remove('BireyselGunlukPlan');
      final bytes = utf8.encode(jsonEncode(meta));
      final eski = File(p.join(alan!.path, 'v15.zip'));
      await eski.writeAsBytes(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile('yedek.json', bytes.length, bytes)),
        )!,
      );
      final incelenen = await bakim.incele(eski);
      expect(incelenen.sayilar['BireyselGunlukPlan'], 0);
      await bakim.geriYukle(incelenen, onayMetni: 'GERİ YÜKLE');
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
      expect(await db.query('OgretmenProfil'), hasLength(2));
      expect(await db.query('DersProgrami'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}
