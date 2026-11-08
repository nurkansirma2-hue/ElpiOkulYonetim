import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/bireysel_gunluk_plan.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_gunluk_plan_belge_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_gunluk_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';
import 'support/gunluk_plan_fixture.dart';

// PDF'in gömülü Unicode haritası okunur; yalnız %PDF başlığıyla yetinilmez.
class _Pdf {
  _Pdf(Uint8List bytes) : ham = latin1.decode(bytes) {
    final nesneler = <int, String>{
      for (final e in RegExp(
        r'(\d+)\s+0\s+obj\b([\s\S]*?)endobj',
      ).allMatches(ham))
        int.parse(e.group(1)!): e.group(2)!,
    };
    String? akis(String nesne) {
      final baslangic = RegExp(r'\bstream\r?\n').firstMatch(nesne);
      final uzunluk = RegExp(r'/Length\s+(\d+)').firstMatch(nesne);
      if (baslangic == null || uzunluk == null) return null;
      final veri = latin1.encode(
        nesne.substring(
          baslangic.end,
          baslangic.end + int.parse(uzunluk.group(1)!),
        ),
      );
      return latin1.decode(
        nesne.contains('/FlateDecode') ? zlib.decode(veri) : veri,
      );
    }

    final fontlar = <String, Map<int, String>>{};
    for (final nesne in nesneler.values) {
      final ad = RegExp(r'/Name\s*/(\w+)').firstMatch(nesne);
      final unicode = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R').firstMatch(nesne);
      if (ad == null || unicode == null) continue;
      final cmap = akis(nesneler[int.parse(unicode.group(1)!)]!)!;
      final karakterler = cmap
          .split('beginbfchar')
          .last
          .split('endbfchar')
          .first;
      fontlar[ad.group(1)!] = {
        for (final e in RegExp(
          r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
        ).allMatches(karakterler))
          int.parse(e.group(1)!, radix: 16): String.fromCharCode(
            int.parse(e.group(2)!, radix: 16),
          ),
      };
    }
    final sonuc = StringBuffer();
    for (final nesne in nesneler.values) {
      final yazi = akis(nesne);
      if (yazi == null || !yazi.contains('TJ')) continue;
      fontBoyutlari.addAll(
        RegExp(
          r'/\w+\s+([-+\d.]+)\s+Tf',
        ).allMatches(yazi).map((e) => double.parse(e.group(1)!)),
      );
      Map<int, String>? font;
      for (final e in RegExp(
        r'/(\w+)\s+[-+\d.]+\s+Tf|<([0-9A-Fa-f]+)>',
      ).allMatches(yazi)) {
        if (e.group(1) != null) {
          font = fontlar[e.group(1)!];
        } else if (font != null) {
          final kodlar = e.group(2)!;
          for (var i = 0; i + 4 <= kodlar.length; i += 4) {
            sonuc.write(
              font[int.parse(kodlar.substring(i, i + 4), radix: 16)] ?? '',
            );
          }
          sonuc.write(' ');
        }
      }
    }
    metin = sonuc.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final String ham;
  late final String metin;
  final fontBoyutlari = <double>[];
  int get sayfalar => RegExp(r'/Type\s*/Page\b').allMatches(ham).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory alan;
  late BireyselBelgeService belgeService;
  late ByteData normalFont;
  late ByteData kalinFont;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;

  Future<BireyselGunlukPlan> taslak() => BireyselGunlukPlanService.hazirla(
    ogretmenProfilId: 1,
    egitimOgretimYili: '2026/2027',
    dersId: 1,
    sinifSeviyesi: 9,
    sinifSubeId: 1,
    tarih: DateTime(2026, 10, 14),
  );

  Future<Uint8List> pdf(BireyselGunlukPlan plan, String ad) async {
    final bytes = await BireyselGunlukPlanBelgeService.pdfOlustur(
      plan,
      normalFont: normalFont,
      kalinFont: kalinFont,
    );
    final qa =
        Platform.environment['GUNLUK_PLAN_QA_DIR'] ??
        const String.fromEnvironment('GUNLUK_PLAN_QA_DIR');
    if (qa.isNotEmpty) {
      await Directory(qa).create(recursive: true);
      await File(p.join(qa, '$ad.pdf')).writeAsBytes(bytes);
    }
    return bytes;
  }

  Future<String> belgeYolu(String id) async {
    final arsiv = (await belgeService.arsivleriGetir()).aktif;
    return belgeService.dosyaYolunuGetir(arsivId: arsiv.id, belgeId: id);
  }

  setUpAll(() async {
    normalFont = ByteData.sublistView(
      await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes(),
    );
    kalinFont = ByteData.sublistView(
      await File('assets/fonts/NotoSans-Bold.ttf').readAsBytes(),
    );
  });

  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    alan = await Directory.systemTemp.createTemp('gunluk_plan_belge_test_');
    mod = CalismaModu.bireyselOgretmen;
    belgeService = BireyselBelgeService(
      databaseGetir: () async => db,
      alanGetir: () async => alan,
      geciciAlanGetir: () async => alan,
      modGetir: () async => mod,
    );
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Çınar Öğretim Okulu',
      'OkulKisaAdi': 'ÇO',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'OgretmenProfilId': 1,
      'AdSoyad': 'Ayşe Şığ Öğretmen',
      'OkulAdi': 'Çınar Öğretim Okulu',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {
      'DersId': 1,
      'DersAdi': 'Matematik',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-A',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Çarşamba',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await gunlukPlanTestDbfEkle(db, ayrintili: false);
    final yp = await db.insert('YillikPlan', {
      'DersId': 1,
      'SinifSeviyesi': 9,
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': yp,
      'HaftaNo': 6,
      'BaslangicTarihi': '2026-10-12',
      'BitisTarihi': '2026-10-16',
      'Saat': '2',
      'Konu': 'Denklemler',
      'Kazanim': 'Denklem çözer.',
      'OlusturmaTarihi': 'test',
    });
  });

  tearDown(() async {
    await LocalDatabase.instance.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, alan.absolute.path),
      isTrue,
    );
    expect(p.basename(alan.path), startsWith('gunluk_plan_belge_test_'));
    await alan.delete(recursive: true);
  });

  test(
    'PDF öğretmenin kaydedilmiş düzenlemelerini ve Türkçe alanları eksiksiz içerir',
    () async {
      final plan = await BireyselGunlukPlanService.kaydet(
        (await taslak()).copyWith(
          konu: 'Doğrusal denklemler',
          kazanim: 'Çözüm kümesini bulur.',
          ogrenmeCiktisi: 'İşlemini açıklar.',
          yontemTeknik: 'Soru cevap',
          aracGerec: 'Çalışma kâğıdı',
          degerlendirme: 'Öğrenci öz değerlendirmesi',
          dersinIslenisi: 'Önce giriş yapılır. Örnek birlikte çözülür.',
          etkinlikler: 'Öğrenci çözümünü arkadaşına açıklar.',
        ),
      );
      final once = await db.query('BireyselGunlukPlan');
      final belge = _Pdf(await pdf(plan, 'gunluk_plan_kisa'));
      for (final metin in [
        'GÜNLÜK DERS PLANI',
        'Çınar Öğretim Okulu',
        'Ayşe Şığ Öğretmen',
        '2026-2027 Eğitim Öğretim Yılı',
        'Matematik',
        '9-A',
        '12.10.2026',
        'Doğrusal denklemler',
        'Çözüm kümesini bulur.',
        'İşlemini açıklar.',
        'Soru cevap',
        'Çalışma kâğıdı',
        'Öğrenci öz değerlendirmesi',
        'Önce giriş yapılır. Örnek birlikte çözülür.',
        'Öğrenci çözümünü arkadaşına açıklar.',
      ]) {
        expect(belge.metin, contains(metin));
      }
      expect(belge.sayfalar, greaterThanOrEqualTo(1));
      expect(belge.fontBoyutlari, everyElement(greaterThanOrEqualTo(8)));
      expect(await db.query('BireyselGunlukPlan'), once);
      expect(await db.query('BireyselBelge'), isEmpty);
    },
  );

  test(
    'Uzun işleniş ve etkinlikler kesilmeden okunabilir sayfalara akar',
    () async {
      final islenis = List.generate(
        140,
        (i) =>
            'ISLENIS_${i.toString().padLeft(4, '0')} Öğrenci örnek çözümünü açıklayıp düşüncesini paylaşır.',
      ).join('\n');
      final etkinlik = List.generate(
        80,
        (i) =>
            'ETKINLIK_${i.toString().padLeft(4, '0')} Küçük gruplar öğretmenin verdiği soruyu çözer.',
      ).join('\n');
      final plan = (await taslak()).copyWith(
        dersinIslenisi: islenis,
        etkinlikler: etkinlik,
      );
      final belge = _Pdf(await pdf(plan, 'gunluk_plan_uzun'));
      expect(belge.sayfalar, greaterThan(1));
      expect(belge.fontBoyutlari, everyElement(greaterThanOrEqualTo(8)));
      for (var i = 0; i < 140; i++) {
        expect(
          belge.metin,
          contains('ISLENIS_${i.toString().padLeft(4, '0')}'),
        );
      }
      for (var i = 0; i < 80; i++) {
        expect(
          belge.metin,
          contains('ETKINLIK_${i.toString().padLeft(4, '0')}'),
        );
      }
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
      expect(await db.query('BireyselBelge'), isEmpty);
    },
  );

  test(
    'Belgelerim tekrar kaydında aynı belgeyi günceller; plan ve dosya çoğalmaz',
    () async {
      var plan = await BireyselGunlukPlanService.kaydet(
        (await taslak()).copyWith(
          konu: 'Birinci PDF konusu',
          dersinIslenisi: 'Birinci işleniş',
        ),
      );
      final id = await BireyselGunlukPlanBelgeService.arsiveKaydet(
        plan,
        belgeService: belgeService,
      );
      expect((await BireyselGunlukPlanService.getir(plan.id!)).belgeId, id);
      final ilkYol = await belgeYolu(id);
      final ilkBytes = await File(ilkYol).readAsBytes();
      expect(_Pdf(ilkBytes).metin, contains('Birinci PDF konusu'));
      expect(
        await BireyselGunlukPlanBelgeService.arsiveKaydet(
          plan,
          belgeService: belgeService,
        ),
        id,
      );
      expect(await db.query('BireyselBelge'), hasLength(1));
      expect(await db.query('BireyselGunlukPlan'), hasLength(1));
      plan = await BireyselGunlukPlanService.getir(plan.id!);
      plan = await BireyselGunlukPlanService.kaydet(
        plan.copyWith(
          konu: 'İkinci PDF konusu',
          dersinIslenisi: 'Öğretmenin yeni işlenişi',
        ),
      );
      final yeniId = await BireyselGunlukPlanBelgeService.arsiveKaydet(
        plan,
        belgeService: belgeService,
      );
      expect(yeniId, id);
      final yeniYol = await belgeYolu(id);
      expect(yeniYol, ilkYol);
      final yeniBytes = await File(yeniYol).readAsBytes();
      expect(yeniBytes, isNot(orderedEquals(ilkBytes)));
      expect(_Pdf(yeniBytes).metin, contains('İkinci PDF konusu'));
      expect(_Pdf(yeniBytes).metin, contains('Öğretmenin yeni işlenişi'));
      expect(_Pdf(yeniBytes).metin, isNot(contains('Birinci PDF konusu')));
      final arsiv = (await belgeService.arsivleriGetir()).aktif;
      final listelenen = await belgeService.listele(arsivId: arsiv.id);
      expect(listelenen.single.id, id);
      expect(listelenen.single.uzanti, 'pdf');
      expect(listelenen.single.acilabilir, isTrue);
      expect(await db.query('BireyselBelge'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'Kaydedilmemiş ve eski sürüm arşive yazamaz; son kayıt korunur',
    () async {
      final ilkTaslak = await taslak();
      await expectLater(
        BireyselGunlukPlanBelgeService.arsiveKaydet(
          ilkTaslak,
          belgeService: belgeService,
        ),
        throwsStateError,
      );
      var plan = await BireyselGunlukPlanService.kaydet(
        ilkTaslak.copyWith(konu: 'Geçerli konu'),
      );
      final id = await BireyselGunlukPlanBelgeService.arsiveKaydet(
        plan,
        belgeService: belgeService,
      );
      final yol = await belgeYolu(id);
      final once = await File(yol).readAsBytes();
      final eski = plan;
      plan = await BireyselGunlukPlanService.getir(plan.id!);
      plan = await BireyselGunlukPlanService.kaydet(
        plan.copyWith(konu: 'Güncel konu'),
      );
      await expectLater(
        BireyselGunlukPlanBelgeService.arsiveKaydet(
          eski,
          belgeService: belgeService,
        ),
        throwsStateError,
      );
      await expectLater(
        belgeService.gunlukPlanPdfKaydet(
          gunlukPlanId: plan.id!,
          surum: eski.surum,
          bytes: await pdf(eski, 'gunluk_plan_eski'),
        ),
        throwsStateError,
      );
      expect(await File(yol).readAsBytes(), orderedEquals(once));
      expect(await db.query('BireyselBelge'), hasLength(1));
      expect(
        (await BireyselGunlukPlanService.getir(plan.id!)).konu,
        'Güncel konu',
      );
    },
  );

  test('Yıl veya mod değişiminde belge arşivi ve plan değişmez', () async {
    final plan = await BireyselGunlukPlanService.kaydet(
      (await taslak()).copyWith(konu: 'Korunan konu'),
    );
    final id = await BireyselGunlukPlanBelgeService.arsiveKaydet(
      plan,
      belgeService: belgeService,
    );
    final yol = await belgeYolu(id);
    final once = await File(yol).readAsBytes();
    final belgeler = await db.query('BireyselBelge');
    final arsivler = await db.query('BelgeArsivi');
    final bytes = await pdf(plan, 'gunluk_plan_kapsam');
    await db.update('OkulProfil', {'EgitimYili': '2027/2028'});
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2027/2028'});
    await expectLater(
      BireyselGunlukPlanBelgeService.arsiveKaydet(
        plan,
        belgeService: belgeService,
      ),
      throwsStateError,
    );
    await expectLater(
      belgeService.gunlukPlanPdfKaydet(
        gunlukPlanId: plan.id!,
        surum: plan.surum,
        bytes: bytes,
      ),
      throwsStateError,
    );
    await db.update('OkulProfil', {'EgitimYili': '2026/2027'});
    await db.update('OgretmenProfil', {'EgitimOgretimYili': '2026/2027'});
    mod = null;
    await expectLater(
      belgeService.gunlukPlanPdfKaydet(
        gunlukPlanId: plan.id!,
        surum: plan.surum,
        bytes: bytes,
      ),
      throwsStateError,
    );
    expect(await File(yol).readAsBytes(), orderedEquals(once));
    expect(await db.query('BireyselBelge'), belgeler);
    expect(await db.query('BelgeArsivi'), arsivler);
    expect(await db.query('BireyselGunlukPlan'), hasLength(1));
  });

  test(
    'Yarım kalmış PDF güncellemesi sağlam geçici dosyadan aynı belgeye tamamlanır',
    () async {
      var plan = await BireyselGunlukPlanService.kaydet(
        (await taslak()).copyWith(konu: 'Eski PDF'),
      );
      final id = await BireyselGunlukPlanBelgeService.arsiveKaydet(
        plan,
        belgeService: belgeService,
      );
      final yol = await belgeYolu(id);
      plan = await BireyselGunlukPlanService.getir(plan.id!);
      plan = await BireyselGunlukPlanService.kaydet(
        plan.copyWith(konu: 'Toparlanan PDF'),
      );
      final bytes = await pdf(plan, 'gunluk_plan_toparlanan');
      final gecici = File('$yol.tmp');
      await gecici.writeAsBytes(bytes, flush: true);
      await db.update(
        'BireyselBelge',
        {
          'Durum': 'Hazirlaniyor',
          'Boyut': bytes.length,
          'IcerikOzeti':
              'crc32:${getCrc32(bytes).toRadixString(16).padLeft(8, '0')}',
        },
        where: 'BelgeId = ?',
        whereArgs: [id],
      );
      final arsiv = (await belgeService.arsivleriGetir()).aktif;
      final rows = await belgeService.listele(arsivId: arsiv.id);
      expect(rows.single.id, id);
      expect(rows.single.acilabilir, isTrue);
      expect(await gecici.exists(), isFalse);
      expect(
        _Pdf(await File(yol).readAsBytes()).metin,
        contains('Toparlanan PDF'),
      );
      expect(await db.query('BireyselBelge'), hasLength(1));
      expect((await BireyselGunlukPlanService.getir(plan.id!)).belgeId, id);
    },
  );
}
