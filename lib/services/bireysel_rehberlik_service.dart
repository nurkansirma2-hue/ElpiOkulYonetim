import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/ortak_import.dart';
import '../models/ogrenci_bilgi_formu.dart';
import 'ortak_import_service.dart';
import 'bireysel_yillik_plan_service.dart';
import 'belge_analiz_service.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../database/veli_iliskisi.dart';
import 'calisma_modu_service.dart';

part 'rehberlik_modul_service.dart';
part 'rehberlik_form_toplu_kayit.dart';
part 'rehberlik_google_form_kaydi.dart';
part 'ogretmen_gorus_kaydi.dart';

class BireyselRehberlikBaglami {
  const BireyselRehberlikBaglami({
    required this.okulId,
    required this.ogretmenProfilId,
    required this.okulAdi,
    required this.ogretmenAdi,
    required this.egitimOgretimYili,
  });

  final String okulId, okulAdi, ogretmenAdi, egitimOgretimYili;
  final int ogretmenProfilId;

  bool _ayni(BireyselRehberlikBaglami diger) =>
      okulId == diger.okulId &&
      ogretmenProfilId == diger.ogretmenProfilId &&
      okulAdi == diger.okulAdi &&
      ogretmenAdi == diger.ogretmenAdi &&
      egitimOgretimYili == diger.egitimOgretimYili;
}

/// Bireysel öğretmenin ders kapsamını ve kendi rehberlik atamalarını yönetir.
class BireyselRehberlikService {
  BireyselRehberlikService({
    Future<Database> Function()? databaseGetir,
    Future<CalismaModu?> Function()? modGetir,
  }) : _db = databaseGetir ?? (() => LocalDatabase.instance.database),
       _mod = modGetir ?? CalismaModuService.getir;

  static final instance = BireyselRehberlikService();
  final Future<Database> Function() _db;
  final Future<CalismaModu?> Function() _mod;
  static Future<void> _yazmaSirasi = Future.value();

  Future<T> _sirali<T>(Future<T> Function() islem) {
    final sonuc = _yazmaSirasi.then((_) => islem());
    _yazmaSirasi = sonuc.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return sonuc;
  }

  Future<void> _modKontrol() async {
    if (await _mod() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Sınıf Rehberliğim yalnız bireysel öğretmen modunda kullanılabilir.',
      );
    }
  }

  Future<BireyselRehberlikBaglami> _baglam(DatabaseExecutor db) async {
    await _modKontrol();
    final okullar = await db.query(
      'OkulProfil',
      where: 'Id = 1 AND AktifMi = 1',
    );
    final profiller = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    if (okullar.length != 1 || profiller.isEmpty) {
      throw StateError('Önce bireysel öğretmen ve okul kurulumunu tamamlayın.');
    }
    final okul = okullar.single, profil = profiller.single;
    final okulId = (okul['OkulId'] ?? '').toString();
    final okulAdi = (okul['OkulAdi'] ?? '').toString();
    final ogretmenAdi = (profil['AdSoyad'] ?? '').toString();
    final yil = (okul['EgitimYili'] ?? '').toString();
    final profilId = profil['OgretmenProfilId'];
    if (okulId.trim().isEmpty ||
        okulAdi.trim().isEmpty ||
        ogretmenAdi.trim().isEmpty ||
        yil.trim().isEmpty ||
        profilId is! int ||
        profilId <= 0 ||
        okulAdi != profil['OkulAdi'] ||
        yil != profil['EgitimOgretimYili']) {
      throw StateError(
        'Aktif okul, öğretmen ve eğitim yılı bilgileri tutarsız.',
      );
    }
    return BireyselRehberlikBaglami(
      okulId: okulId,
      ogretmenProfilId: profilId,
      okulAdi: okulAdi,
      ogretmenAdi: ogretmenAdi,
      egitimOgretimYili: yil,
    );
  }

  Future<void> _kontrol(
    DatabaseExecutor db,
    BireyselRehberlikBaglami baglam,
  ) async {
    if (!baglam._ayni(await _baglam(db))) {
      throw StateError(
        'Öğretmen, okul veya eğitim yılı değişti. Sınıf Rehberliğim bölümünü yeniden açın.',
      );
    }
  }

  Future<BireyselRehberlikBaglami> hazirla() async {
    await _modKontrol();
    final db = await _db();
    return db.transaction((txn) async {
      final baglam = await _baglam(txn);
      await _kontrol(txn, baglam);
      return baglam;
    });
  }

  /// RehberOgretmen yalnız importtan gelen metindir; atama doğrulaması değildir.
  Future<List<Map<String, Object?>>> siniflariGetir(
    BireyselRehberlikBaglami baglam,
  ) async {
    await _modKontrol();
    final db = await _db();
    return db.transaction((txn) async {
      await _kontrol(txn, baglam);
      final siniflar = await txn.rawQuery(
        '''
        SELECT s.SinifSubeId, s.SinifKodu, s.SinifSeviyesi,
          s.Sube, s.Alan, s.RehberOgretmen, s.EgitimOgretimYili
        FROM SinifSube s
        WHERE s.Aktif = 1 AND s.EgitimOgretimYili = ?
          AND EXISTS (
            SELECT 1 FROM GecerliDersProgrami dp
            WHERE dp.SinifSubeId = s.SinifSubeId
              AND dp.OgretmenProfilId = ?
              AND dp.EgitimOgretimYili = ? AND dp.Aktif = 1
          )
        ORDER BY s.SinifSeviyesi, s.SinifKodu
      ''',
        [
          baglam.egitimOgretimYili,
          baglam.ogretmenProfilId,
          baglam.egitimOgretimYili,
        ],
      );
      await _kontrol(txn, baglam);
      return List<Map<String, Object?>>.unmodifiable(
        siniflar.map((satir) => Map<String, Object?>.unmodifiable(satir)),
      );
    });
  }

  static String _tarih(String deger) {
    final tarih = DateTime.tryParse(deger);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(deger) ||
        tarih == null ||
        tarih.year.toString().padLeft(4, '0') != deger.substring(0, 4) ||
        tarih.month.toString().padLeft(2, '0') != deger.substring(5, 7) ||
        tarih.day.toString().padLeft(2, '0') != deger.substring(8, 10)) {
      throw const FormatException('Geçerli bir tarih girin (YYYY-AA-GG).');
    }
    return deger;
  }

  Future<int> atamaKaydet(
    BireyselRehberlikBaglami baglam, {
    required int sinifSubeId,
    required String baslangicTarihi,
    String? bitisTarihi,
  }) async {
    await _modKontrol();
    final baslangic = _tarih(baslangicTarihi);
    final bitis = bitisTarihi == null ? null : _tarih(bitisTarihi);
    if (sinifSubeId <= 0 || (bitis != null && bitis.compareTo(baslangic) < 0)) {
      throw const FormatException(
        'Sınıfı ve atama tarih aralığını kontrol edin.',
      );
    }
    final db = await _db();
    return _sirali(
      () => db.transaction((txn) async {
        await _kontrol(txn, baglam);
        final kapsam = await txn.rawQuery(
          '''
        SELECT s.SinifSubeId FROM SinifSube s
        WHERE s.SinifSubeId = ? AND s.EgitimOgretimYili = ? AND s.Aktif = 1
          AND EXISTS (SELECT 1 FROM GecerliDersProgrami dp
            WHERE dp.SinifSubeId = s.SinifSubeId AND dp.OgretmenProfilId = ?
              AND dp.EgitimOgretimYili = ? AND dp.Aktif = 1)
      ''',
          [
            sinifSubeId,
            baglam.egitimOgretimYili,
            baglam.ogretmenProfilId,
            baglam.egitimOgretimYili,
          ],
        );
        if (kapsam.isEmpty) {
          throw StateError(
            'Sınıf güncel eğitim yılı ve ders kapsamınızda bulunmuyor.',
          );
        }
        // Bitiş günü dahildir; açık uçlu atama sonraki bütün tarihlerle çakışır.
        final cakisan = await txn.rawQuery(
          '''
        SELECT RehberlikAtamaId FROM RehberlikAtama
        WHERE OkulId = ? AND OgretmenProfilId = ? AND SinifSubeId = ?
          AND EgitimOgretimYili = ?
          AND (BitisTarihi IS NULL OR BitisTarihi >= ?)
          AND (? IS NULL OR BaslangicTarihi <= ?)
        LIMIT 1
      ''',
          [
            baglam.okulId,
            baglam.ogretmenProfilId,
            sinifSubeId,
            baglam.egitimOgretimYili,
            baslangic,
            bitis,
            bitis,
          ],
        );
        if (cakisan.isNotEmpty) {
          throw StateError(
            'Bu sınıf için belirtilen tarihlerle çakışan atamanız var.',
          );
        }
        final id = await txn.insert('RehberlikAtama', {
          'OkulId': baglam.okulId,
          'OgretmenProfilId': baglam.ogretmenProfilId,
          'SinifSubeId': sinifSubeId,
          'EgitimOgretimYili': baglam.egitimOgretimYili,
          'BaslangicTarihi': baslangic,
          'BitisTarihi': bitis,
          'OlusturmaTarihi': DateTime.now().toIso8601String(),
        });
        await _kontrol(txn, baglam);
        return id;
      }),
    );
  }

  Future<List<Map<String, Object?>>> ogrencileriGetir(
    BireyselRehberlikBaglami baglam, {
    required int atamaId,
  }) async {
    await _modKontrol();
    final db = await _db();
    return db.transaction((txn) async {
      await _kontrol(txn, baglam);
      final bugun = DateTime.now().toIso8601String().substring(0, 10);
      final atama = await txn.rawQuery(
        '''
        SELECT a.SinifSubeId FROM RehberlikAtama a
        JOIN SinifSube s ON s.SinifSubeId = a.SinifSubeId
          AND s.EgitimOgretimYili = a.EgitimOgretimYili AND s.Aktif = 1
        WHERE a.RehberlikAtamaId = ? AND a.OkulId = ?
          AND a.OgretmenProfilId = ? AND a.EgitimOgretimYili = ?
          AND a.BaslangicTarihi <= ?
          AND (a.BitisTarihi IS NULL OR a.BitisTarihi >= ?)
      ''',
        [
          atamaId,
          baglam.okulId,
          baglam.ogretmenProfilId,
          baglam.egitimOgretimYili,
          bugun,
          bugun,
        ],
      );
      if (atama.length != 1) {
        throw StateError(
          'Bugün geçerli, size ait bir rehberlik ataması bulunamadı.',
        );
      }
      final rows = await txn.rawQuery(
        '''
        SELECT o.OgrenciId, o.OkulNo, o.Ad, o.Soyad, ${VeliIliskisi.adSql('o')} AS VeliAdi,
          ${VeliIliskisi.telefonSql('o')} AS VeliTelefonu, s.SinifKodu, f.FotoVerisi, f.DosyaYolu
        FROM Ogrenci o
        JOIN OgrenciSinifKayit k ON k.OgrenciId = o.OgrenciId
        JOIN SinifSube s ON s.SinifSubeId = k.SinifSubeId
        LEFT JOIN OgrenciFotograf f ON f.OgrenciId = o.OgrenciId AND f.Aktif = 1
        WHERE o.Aktif = 1 AND k.Aktif = 1 AND s.Aktif = 1
          AND k.SinifSubeId = ? AND k.EgitimOgretimYili = ?
          AND s.EgitimOgretimYili = ?
        ORDER BY CAST(o.OkulNo AS INTEGER), o.OkulNo, o.Ad, o.Soyad
      ''',
        [
          atama.single['SinifSubeId'],
          baglam.egitimOgretimYili,
          baglam.egitimOgretimYili,
        ],
      );
      await _kontrol(txn, baglam);
      return List<Map<String, Object?>>.unmodifiable(
        rows.map((r) => Map<String, Object?>.unmodifiable(r)),
      );
    });
  }

  /// Önceki yıllar da okunabilir; yalnız aktif okul ve öğretmene ait kayıtlar döner.
  Future<List<Map<String, Object?>>> atamalariGetir(
    BireyselRehberlikBaglami baglam, {
    String? egitimOgretimYili,
  }) async {
    await _modKontrol();
    final yil = egitimOgretimYili ?? baglam.egitimOgretimYili;
    if (yil.trim().isEmpty) {
      throw const FormatException('Eğitim öğretim yılı boş bırakılamaz.');
    }
    final db = await _db();
    return db.transaction((txn) async {
      await _kontrol(txn, baglam);
      final rows = await txn.rawQuery(
        '''
        SELECT a.*, s.SinifKodu FROM RehberlikAtama a
        INNER JOIN SinifSube s ON s.SinifSubeId = a.SinifSubeId
          AND s.EgitimOgretimYili = a.EgitimOgretimYili
        WHERE a.OkulId = ? AND a.OgretmenProfilId = ? AND a.EgitimOgretimYili = ?
        ORDER BY s.SinifKodu, a.BaslangicTarihi DESC, a.RehberlikAtamaId DESC
      ''',
        [baglam.okulId, baglam.ogretmenProfilId, yil],
      );
      await _kontrol(txn, baglam);
      return List<Map<String, Object?>>.unmodifiable(
        rows.map((r) => Map<String, Object?>.unmodifiable(r)),
      );
    });
  }

  /// Güncel yıldaki açık atamayı kapatır; bitmiş/geçmiş kayıtlar değiştirilmez.
  Future<void> atamayiSonlandir(
    BireyselRehberlikBaglami baglam, {
    required int atamaId,
    required String bitisTarihi,
  }) async {
    await _modKontrol();
    final bitis = _tarih(bitisTarihi);
    final db = await _db();
    await _sirali(
      () => db.transaction((txn) async {
        await _kontrol(txn, baglam);
        final etkilenen = await txn.update(
          'RehberlikAtama',
          {
            'BitisTarihi': bitis,
            'GuncellemeTarihi': DateTime.now().toIso8601String(),
          },
          where: '''RehberlikAtamaId = ? AND OkulId = ? AND OgretmenProfilId = ?
        AND EgitimOgretimYili = ? AND BitisTarihi IS NULL AND BaslangicTarihi <= ?''',
          whereArgs: [
            atamaId,
            baglam.okulId,
            baglam.ogretmenProfilId,
            baglam.egitimOgretimYili,
            bitis,
          ],
        );
        if (etkilenen != 1) {
          throw StateError(
            'Atama sonlandırılamadı. Kayıt kapsamını ve tarihleri kontrol edin; atama zaten bitmiş olabilir.',
          );
        }
        await _kontrol(txn, baglam);
      }),
    );
  }
}
