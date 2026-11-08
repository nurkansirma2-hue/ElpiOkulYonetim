import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/dbf_belgesi.dart';
import '../models/bireysel_gunluk_plan.dart';
import '../models/bireysel_belge.dart';
import '../models/ortak_import.dart';
import 'bireysel_belge_service.dart';
import 'bireysel_yillik_plan_service.dart';
import 'calisma_modu_service.dart';

class DersBelgeGrubu {
  DersBelgeGrubu(
    this.profilId,
    this.egitimYili,
    this.dersId,
    this.dersAdi,
    this.sinifSeviyesi,
  );
  final int profilId, dersId, sinifSeviyesi;
  final String egitimYili, dersAdi;
  bool yillikPlanVar = false;
  final gunlukPlanlar = <BireyselGunlukPlan>[];
  DbfBelgesi? dbf;
  String? yillikBelgeId, yillikArsivId;
}

class DersBelgeleriService {
  DersBelgeleriService({
    Future<Database> Function()? databaseGetir,
    Future<CalismaModu?> Function()? modGetir,
    BireyselBelgeService? belgeService,
  }) : _db = databaseGetir ?? (() => LocalDatabase.instance.database),
       _mod = modGetir ?? CalismaModuService.getir,
       _belgeler = belgeService ?? BireyselBelgeService.instance;
  static final instance = DersBelgeleriService();
  final Future<Database> Function() _db;
  final Future<CalismaModu?> Function() _mod;
  final BireyselBelgeService _belgeler;

  Future<({String okul, int profil, String yil})> _baglam(
    DatabaseExecutor db,
  ) async {
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError('Ders belgeleri yalnız bireysel öğretmen modundadır.');
    }
    final s = await db.query('OkulProfil', where: 'Id = 1 AND AktifMi = 1');
    final p = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (s.length != 1 ||
        p.length != 1 ||
        s.single['OkulAdi'] != p.single['OkulAdi'] ||
        s.single['EgitimYili'] != p.single['EgitimOgretimYili']) {
      throw StateError('Okul ve öğretmen kurulumu geçersiz.');
    }
    return (
      okul: s.single['OkulId'] as String,
      profil: p.single['OgretmenProfilId'] as int,
      yil: p.single['EgitimOgretimYili'] as String,
    );
  }

  Future<List<DersBelgeGrubu>> getir() async {
    final db = await _db();
    final b = await _baglam(db);
    final yil = BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(b.yil);
    final groups = <(int, int), DersBelgeGrubu>{};
    DersBelgeGrubu grup(int ders, String ad, int seviye) => groups.putIfAbsent((
      ders,
      seviye,
    ), () => DersBelgeGrubu(b.profil, b.yil, ders, ad, seviye));
    final program = await db.rawQuery(
      '''SELECT DISTINCT d.DersId, d.DersAdi, s.SinifSeviyesi
      FROM GecerliDersProgrami dp JOIN Ders d ON d.DersId = dp.DersId
      JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
      WHERE dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ?
        AND dp.Aktif = 1 AND d.Aktif = 1 AND s.Aktif = 1 AND s.SinifSeviyesi > 0''',
      [b.profil, b.yil],
    );
    for (final r in program) {
      grup(
        r['DersId'] as int,
        r['DersAdi'] as String,
        r['SinifSeviyesi'] as int,
      );
    }
    final plans = await db.rawQuery(
      '''SELECT DISTINCT y.DersId, d.DersAdi, y.SinifSeviyesi
      FROM YillikPlan y JOIN Ders d ON d.DersId = y.DersId
      WHERE y.OgretmenProfilId = ? AND y.EgitimOgretimYili IN (?, ?) AND y.Aktif = 1
        AND y.SinifSeviyesi > 0 AND EXISTS
          (SELECT 1 FROM YillikPlanDetay t WHERE t.YillikPlanId = y.YillikPlanId AND t.Aktif = 1)''',
      [b.profil, b.yil, yil],
    );
    for (final r in plans) {
      grup(
        r['DersId'] as int,
        r['DersAdi'] as String,
        r['SinifSeviyesi'] as int,
      ).yillikPlanVar = true;
    }
    final daily = await db.query(
      'BireyselGunlukPlan',
      where: 'OkulId = ? AND OgretmenProfilId = ? AND EgitimOgretimYili = ?',
      whereArgs: [b.okul, b.profil, yil],
      orderBy: 'Tarih DESC, SinifKodu, GunlukPlanId DESC',
    );
    for (final r in daily) {
      final p = BireyselGunlukPlan.fromMap(r);
      grup(p.dersId, p.dersAdi, p.sinifSeviyesi).gunlukPlanlar.add(p);
    }
    final ayarlar = await db.query(
      'UygulamaAyarlari',
      where: "Anahtar LIKE 'dbf.v1.%' OR Anahtar LIKE 'ders.yillik.v1.%'",
    );
    final dersler = {
      for (final r in await db.query('Ders'))
        r['DersId'] as int: r['DersAdi'] as String,
    };
    // Belgenin kayıt yılı kullanım yılından farklı olabilir. Sahiplik ise
    // mutlaka aktif okul ve öğretmen arşiviyle aynı olmalıdır.
    final kaynaklar = {
      for (final r in await db.rawQuery(
        '''
        SELECT b.BelgeId, b.ArsivId FROM BireyselBelge b
        JOIN BelgeArsivi a ON a.ArsivId = b.ArsivId
        WHERE a.OkulId = ? AND a.OgretmenProfilId = ?
          AND b.Durum = 'Hazir' AND b.SilinmeTarihi IS NULL
      ''',
        [b.okul, b.profil],
      ))
        (r['ArsivId'], r['BelgeId']),
    };
    for (final r in ayarlar) {
      final key = r['Anahtar'] as String;
      final prefix = key.startsWith('dbf.v1.') ? 'dbf.v1.' : 'ders.yillik.v1.';
      final scope = jsonDecode(key.substring(prefix.length)) as List;
      if (scope.length != 5 ||
          scope[0] != b.okul ||
          scope[1] != b.profil ||
          scope[2] != yil) {
        continue;
      }
      final ad = dersler[scope[3]];
      if (ad == null) continue;
      final g = grup(scope[3] as int, ad, scope[4] as int);
      final data = jsonDecode(r['Deger'] as String) as Map<String, dynamic>;
      if (prefix == 'dbf.v1.') {
        g.dbf = DbfBelgesi.fromJson(data);
      } else if (kaynaklar.contains((data['arsivId'], data['belgeId']))) {
        g.yillikBelgeId = data['belgeId'] as String;
        g.yillikArsivId = data['arsivId'] as String;
      }
    }
    if (await _baglam(db) != b) {
      throw StateError('Okul, öğretmen veya yıl değişti. Ekranı yenileyin.');
    }
    return groups.values.toList()..sort((a, b) {
      final c = a.dersAdi.compareTo(b.dersAdi);
      return c == 0 ? a.sinifSeviyesi.compareTo(b.sinifSeviyesi) : c;
    });
  }

  Future<void> _planiDogrula(
    DatabaseExecutor db,
    int profilId,
    String hamYil,
    int dersId,
    int seviye,
  ) async {
    final yil = BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
      hamYil,
    );
    final rows = await db.rawQuery(
      '''
      SELECT y.YillikPlanId FROM YillikPlan y
      JOIN Ders d ON d.DersId = y.DersId
      WHERE y.OgretmenProfilId = ? AND y.EgitimOgretimYili IN (?, ?)
        AND y.DersId = ? AND y.SinifSeviyesi = ? AND y.Aktif = 1
        AND EXISTS (SELECT 1 FROM YillikPlanDetay t
          WHERE t.YillikPlanId = y.YillikPlanId AND t.Aktif = 1)
      LIMIT 1
    ''',
      [profilId, hamYil, yil, dersId, seviye],
    );
    if (rows.isEmpty) throw StateError('Yıllık plan kaydı bulunamadı.');
  }

  /// Import edilen yıllık planın orijinali de arşivde korunur. Dosya ekleme
  /// başarısız olursa yıllık plan verisi korunur ve çağıran açık uyarı gösterir.
  Future<void> yillikKaynakKaydet({
    required int profilId,
    required String egitimYili,
    required int dersId,
    required int seviye,
    required ImportDosya dosya,
  }) async {
    final db = await _db();
    final b = await _baglam(db);
    final yil = BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
      egitimYili,
    );
    if (b.profil != profilId ||
        BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(b.yil) !=
            yil) {
      throw StateError('Import kapsamı değişti.');
    }
    await _planiDogrula(db, profilId, b.yil, dersId, seviye);
    final arsiv = (await _belgeler.arsivleriGetir()).aktif;
    if (arsiv.okulId != b.okul ||
        arsiv.ogretmenProfilId != b.profil ||
        await _baglam(db) != b) {
      throw StateError('Import kapsamı değişti.');
    }
    final BireyselBelge belge;
    final kaynak = dosya.belgeKaynagi;
    if (kaynak != null) {
      if (kaynak.arsivId != arsiv.id ||
          BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
                kaynak.yil,
              ) !=
              yil) {
        throw StateError(
          'Kaynak belge aktif okul, öğretmen veya yıla ait değil.',
        );
      }
      await _belgeler.importKapsaminiDogrula(kaynak);
      final yol = await _belgeler.dosyaYolunuGetir(
        arsivId: kaynak.arsivId,
        belgeId: kaynak.belgeId,
      );
      if (!listEquals(await File(yol).readAsBytes(), dosya.bytes)) {
        throw StateError(
          'Kaynak belge içeriği değişti. Belgeyi yeniden seçin.',
        );
      }
      belge = await _belgeler.belgeGetir(kaynak.arsivId, kaynak.belgeId);
    } else {
      final sonuc = await _belgeler.ekle(
        arsivId: arsiv.id,
        dosya: PlatformFile(
          name: dosya.ad,
          size: dosya.bytes.length,
          bytes: dosya.bytes,
        ),
      );
      belge = sonuc.belge;
      // Tekrar kullanılan şablonun kullanıcı tarafından seçilmiş türü korunur.
      if (!sonuc.zatenVar) {
        await _belgeler.belgeyiDuzenle(belge, tur: 'Yıllık plan');
      }
    }
    await db.transaction((tx) async {
      if (await _baglam(tx) != b) throw StateError('Import kapsamı değişti.');
      await _planiDogrula(tx, profilId, b.yil, dersId, seviye);
      final mevcut = await tx.rawQuery(
        '''
        SELECT b.BelgeId FROM BireyselBelge b
        JOIN BelgeArsivi a ON a.ArsivId = b.ArsivId
        WHERE b.BelgeId = ? AND b.ArsivId = ? AND a.OkulId = ?
          AND a.OgretmenProfilId = ? AND b.Durum = 'Hazir'
          AND b.SilinmeTarihi IS NULL
      ''',
        [belge.id, belge.arsivId, b.okul, b.profil],
      );
      if (mevcut.isEmpty) {
        throw StateError('Kaynak belge artık kullanılamıyor. Yeniden seçin.');
      }
      await tx.insert('UygulamaAyarlari', {
        'Anahtar':
            'ders.yillik.v1.${jsonEncode([b.okul, b.profil, yil, dersId, seviye])}',
        'Deger': jsonEncode({'belgeId': belge.id, 'arsivId': belge.arsivId}),
        'GuncellemeTarihi': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
