import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/dbf_belgesi.dart';
import '../models/bireysel_belge.dart';
import '../models/ortak_import.dart';
import 'bireysel_yillik_plan_service.dart';
import 'calisma_modu_service.dart';
import 'bireysel_belge_service.dart';
import 'dbf_kaynak_service.dart';

/// Mevcut import profilleri gibi sürümlü JSON tutulur. Böylece DBF kaynak
/// metinleri mevcut SQLite yedekleme/geri yükleme ve sıfırlamaya dahildir.
class BireyselDbfService {
  BireyselDbfService({
    Future<Database> Function()? databaseGetir,
    Future<CalismaModu?> Function()? modGetir,
    BireyselBelgeService? belgeService,
  }) : _db = databaseGetir ?? (() => LocalDatabase.instance.database),
       _mod = modGetir ?? CalismaModuService.getir,
       _belgeler = belgeService ?? BireyselBelgeService.instance;
  static final instance = BireyselDbfService();
  final Future<Database> Function() _db;
  final Future<CalismaModu?> Function() _mod;
  final BireyselBelgeService _belgeler;

  static String yil(String s) =>
      BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(s);

  Future<String> _baglam(
    DatabaseExecutor db,
    int profil,
    String egitimYili,
    int ders,
    int seviye,
  ) async {
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'DBF importu yalnız bireysel öğretmen modunda kullanılabilir.',
      );
    }
    final okullar = await db.query(
      'OkulProfil',
      where: 'Id = 1 AND AktifMi = 1',
    );
    final ogretmenler = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (okullar.length != 1 ||
        ogretmenler.length != 1 ||
        ogretmenler.single['OgretmenProfilId'] != profil ||
        yil(egitimYili).isEmpty ||
        yil('${ogretmenler.single['EgitimOgretimYili']}') != yil(egitimYili) ||
        yil('${okullar.single['EgitimYili']}') != yil(egitimYili) ||
        okullar.single['OkulAdi'] != ogretmenler.single['OkulAdi']) {
      throw StateError(
        'Okul, öğretmen veya eğitim yılı değişti. Ekranı yeniden açın.',
      );
    }
    final kapsam = await db.rawQuery(
      '''
      SELECT d.DersAdi FROM DersProgrami dp
      LEFT JOIN DersProgramiSurum ps ON ps.ProgramSurumId = dp.ProgramSurumId
      INNER JOIN Ders d ON d.DersId = dp.DersId
      INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
      WHERE dp.OgretmenProfilId = ? AND dp.DersId = ?
        AND s.SinifSeviyesi = ? AND dp.Aktif = 1 AND d.Aktif = 1 AND s.Aktif = 1
        AND dp.EgitimOgretimYili = ? AND s.EgitimOgretimYili = ?
        AND (dp.ProgramSurumId IS NULL OR ps.Aktif = 1)
    ''',
      [
        profil,
        ders,
        seviye,
        '${ogretmenler.single['EgitimOgretimYili']}',
        '${ogretmenler.single['EgitimOgretimYili']}',
      ],
    );
    if (kapsam.isEmpty) {
      throw StateError(
        'Seçili ders ve sınıf öğretmenin ders kapsamında değil.',
      );
    }
    final okul = (okullar.single['OkulId'] ?? '').toString();
    if (okul.isEmpty) throw StateError('Okul kimliği eksik.');
    return kapsam.first['DersAdi'] as String;
  }

  Future<String> _anahtar(
    DatabaseExecutor db,
    int profil,
    String egitimYili,
    int ders,
    int seviye,
  ) async {
    await _baglam(db, profil, egitimYili, ders, seviye);
    final okul = (await db.query(
      'OkulProfil',
      where: 'Id = 1',
    )).single['OkulId'];
    return 'dbf.v1.${jsonEncode([okul, profil, yil(egitimYili), ders, seviye])}';
  }

  Future<DbfBelgesi?> getir({
    required int profilId,
    required String egitimYili,
    required int dersId,
    required int sinifSeviyesi,
  }) async {
    final db = await _db();
    final key = await _anahtar(db, profilId, egitimYili, dersId, sinifSeviyesi);
    final rows = await db.query(
      'UygulamaAyarlari',
      where: 'Anahtar = ?',
      whereArgs: [key],
    );
    await _baglam(db, profilId, egitimYili, dersId, sinifSeviyesi);
    return rows.isEmpty
        ? null
        : DbfBelgesi.fromJson(
            jsonDecode(rows.single['Deger'] as String) as Map<String, dynamic>,
          );
  }

  Future<DbfBelgesi> kaydet({
    required int profilId,
    required String egitimYili,
    required int dersId,
    required int sinifSeviyesi,
    required DbfBelgesi belge,
    required int beklenenSurum,
    required String kaynakAdresi,
    required String programSurumu,
  }) async {
    if (programSurumu.trim().isEmpty || programSurumu.length > 100) {
      throw const FormatException(
        'Program sürümünü belirtin (en fazla 100 karakter).',
      );
    }
    // Ön izlemede değiştirilmiş veya eksik içerik kaydedilmez.
    final dogrulanan = DbfBelgesi.metinden(
      dosyaAdi: belge.dosyaAdi,
      sayfalar: belge.sayfalar,
      icerikOzeti: belge.icerikOzeti,
    );
    if (dogrulanan.dersAdi != belge.dersAdi ||
        dogrulanan.sinifSeviyesi != belge.sinifSeviyesi) {
      throw const FormatException('DBF kimlik bilgileri kaynakla uyuşmuyor.');
    }
    final db = await _db();
    DbfKaynakService.dogrula(kaynakAdresi);
    final ilkAnahtar = await _anahtar(
      db,
      profilId,
      egitimYili,
      dersId,
      sinifSeviyesi,
    );
    final ilkAd = await _baglam(
      db,
      profilId,
      egitimYili,
      dersId,
      sinifSeviyesi,
    );
    if (sinifSeviyesi != belge.sinifSeviyesi ||
        importNormalize(ilkAd) != importNormalize(belge.dersAdi)) {
      throw StateError('DBF’nin ders adı veya sınıfı seçili dersle uyuşmuyor.');
    }
    final ilkKayit = await getir(
      profilId: profilId,
      egitimYili: egitimYili,
      dersId: dersId,
      sinifSeviyesi: sinifSeviyesi,
    );
    if ((ilkKayit?.surum ?? 0) != beklenenSurum) {
      throw StateError('DBF başka bir işlemde değişti. Ekranı yeniden açın.');
    }
    BireyselBelge? arsivBelgesi;
    if (belge.pdfBytes != null) {
      final bytes = belge.pdfBytes!;
      final crc = 'crc32:${getCrc32(bytes).toRadixString(16).padLeft(8, '0')}';
      if (crc != belge.icerikOzeti ||
          bytes.length < 5 ||
          bytes.length > 20 * 1024 * 1024 ||
          String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const FormatException(
          'DBF kaynak PDF’sinin bütünlüğü doğrulanamadı.',
        );
      }
      final arsiv = (await _belgeler.arsivleriGetir()).aktif;
      arsivBelgesi = (await _belgeler.ekle(
        arsivId: arsiv.id,
        dosya: PlatformFile(
          name: belge.dosyaAdi,
          size: bytes.length,
          bytes: bytes,
        ),
      )).belge;
      await _belgeler.belgeyiDuzenle(arsivBelgesi, tur: 'Ders bilgi formu');
    }
    return db.transaction((tx) async {
      final ad = await _baglam(tx, profilId, egitimYili, dersId, sinifSeviyesi);
      if (sinifSeviyesi != belge.sinifSeviyesi ||
          importNormalize(ad) != importNormalize(belge.dersAdi)) {
        throw StateError(
          'DBF’nin ders adı veya sınıfı seçili dersle uyuşmuyor.',
        );
      }
      final key = await _anahtar(
        tx,
        profilId,
        egitimYili,
        dersId,
        sinifSeviyesi,
      );
      if (key != ilkAnahtar) {
        throw StateError('Okul kapsamı değişti. DBF’yi yeniden açın.');
      }
      final rows = await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar = ?',
        whereArgs: [key],
      );
      final onceki = rows.isEmpty
          ? null
          : DbfBelgesi.fromJson(
              jsonDecode(rows.single['Deger'] as String)
                  as Map<String, dynamic>,
            );
      if ((onceki?.surum ?? 0) != beklenenSurum) {
        throw StateError('DBF başka bir işlemde değişti. Ekranı yeniden açın.');
      }
      final kayit = DbfBelgesi(
        dosyaAdi: belge.dosyaAdi,
        dersAdi: belge.dersAdi,
        sinifSeviyesi: belge.sinifSeviyesi,
        sayfalar: belge.sayfalar,
        icerikOzeti: belge.icerikOzeti,
        surum: beklenenSurum + 1,
        kaynakAdresi: kaynakAdresi,
        programSurumu: programSurumu.trim(),
        kayitTarihi: DateTime.now().toIso8601String(),
        belgeId: arsivBelgesi?.id ?? belge.belgeId,
        arsivId: arsivBelgesi?.arsivId ?? belge.arsivId,
      );
      await tx.insert('UygulamaAyarlari', {
        'Anahtar': key,
        'Deger': jsonEncode(kayit.toJson()),
        'GuncellemeTarihi': kayit.kayitTarihi,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _baglam(tx, profilId, egitimYili, dersId, sinifSeviyesi);
      return kayit;
    });
  }
}
