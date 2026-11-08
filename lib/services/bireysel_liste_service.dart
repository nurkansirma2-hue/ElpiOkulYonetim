import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/rapor_sablonu.dart';
import '../models/sinif.dart';
import 'bireysel_import_service.dart';
import 'bireysel_okul_bilgi_service.dart';
import 'calisma_modu_service.dart';
import '../database/veli_iliskisi.dart';
import '../models/mesajlasma.dart';

class BireyselListeOturumu {
  BireyselListeOturumu(this.ogretmenId, this.yil, this.ogretmen, this.okul, this.siniflar,
      {this.ekSiniflariDahilEt = false, this.mudur = '',
      this.sinifDersleri = const {}, this.okulId});
  final int ogretmenId;
  final String yil, ogretmen, okul;
  final List<Sinif> siniflar;
  final bool ekSiniflariDahilEt;
  final String mudur;
  final String? okulId;
  final Map<int, List<String>> sinifDersleri;
}

class BireyselListeService {
  static String _okulAdiNormalizeEt(String okul) =>
      okul.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static Future<void> _modKontrol() async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError('Bu işlem yalnız bireysel öğretmen modunda kullanılabilir.');
    }
  }
  static Future<Map<String, Object?>> _profil(DatabaseExecutor db) async {
    final rows = await db.query('OgretmenProfil', where: 'Aktif = 1', orderBy: 'OgretmenProfilId DESC', limit: 1);
    if (rows.isEmpty) throw StateError('Önce öğretmen kurulumunu tamamlayın.');
    return rows.single;
  }
  static Future<void> _oturumKontrol(DatabaseExecutor db, BireyselListeOturumu oturum) async {
    final p = await _profil(db);
    if (p['OgretmenProfilId'] != oturum.ogretmenId || p['EgitimOgretimYili'] != oturum.yil) {
      throw StateError('Öğretmen veya eğitim yılı değişti. Öğrencilerim ekranını yeniden açın.');
    }
  }
  static Future<BireyselListeOturumu> hazirla({bool ekSiniflariDahilEt = false}) async {
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    final p = await _profil(db);
    final id = p['OgretmenProfilId'] as int, yil = p['EgitimOgretimYili'].toString();
    final ekSiniflar = ekSiniflariDahilEt
        ? await BireyselImportService.ogrenciEkSinifIdleriniGetir(db, id, yil)
        : const <int>{};
    final ekSinifKosulu = ekSiniflar.isEmpty ? ''
        : ' OR s.SinifSubeId IN (${List.filled(ekSiniflar.length, '?').join(',')})';
    final rows = await db.rawQuery('''SELECT DISTINCT s.SinifSubeId, s.SinifKodu, s.Alan
      FROM SinifSube s
      WHERE s.Aktif = 1 AND s.EgitimOgretimYili = ?
        AND (EXISTS (SELECT 1 FROM GecerliDersProgrami dp WHERE dp.SinifSubeId = s.SinifSubeId
          AND dp.Aktif = 1 AND dp.EgitimOgretimYili = ? AND dp.OgretmenProfilId = ?)$ekSinifKosulu)
      ORDER BY s.SinifSeviyesi, s.SinifKodu''', [yil, yil, id, ...ekSiniflar]);
    final dersler = await db.rawQuery('''
      SELECT DISTINCT s.SinifSubeId, TRIM(d.DersAdi) AS DersAdi
      FROM GecerliDersProgrami dp
      INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
      INNER JOIN Ders d ON d.DersId = dp.DersId
      WHERE dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ?
        AND s.EgitimOgretimYili = ? AND dp.Aktif = 1
        AND s.Aktif = 1 AND d.Aktif = 1 AND LENGTH(TRIM(d.DersAdi)) > 0
      ORDER BY s.SinifSubeId, DersAdi
    ''', [id, yil, yil]);
    final sinifDersleri = <int, List<String>>{};
    for (final ders in dersler) {
      sinifDersleri.putIfAbsent(ders['SinifSubeId'] as int, () => [])
          .add(ders['DersAdi'] as String);
    }
    final okul = (p['OkulAdi'] ?? '').toString();
    final mudurBilgisi = await BireyselOkulBilgiService.raporMuduruGetir(db, id, okul);
    return BireyselListeOturumu(id, yil, (p['AdSoyad'] ?? '').toString(), okul,
      rows.map((r) => Sinif(sinifSubeId: r['SinifSubeId'] as int, sinif: r['SinifKodu'].toString(), alan: r['Alan'] as String?)).toList(),
      ekSiniflariDahilEt: ekSiniflariDahilEt, mudur: mudurBilgisi.mudur,
      okulId: mudurBilgisi.okulId,
      sinifDersleri: Map.unmodifiable({
        for (final entry in sinifDersleri.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }));
  }
  /// Öğrenciyi yalnız öğretmenin erişebildiği sınıfa ekler; kimlik kaydını çoğaltmaz.
  static Future<void> ogrenciEkle(BireyselListeOturumu oturum, {
    required int sinifId, required String okulNo,
    required String ad, required String soyad,
    String? cinsiyet,
  }) async {
    final no = okulNo.trim(), isim = ad.trim(), soyisim = soyad.trim();
    if (no.isEmpty || isim.isEmpty || soyisim.isEmpty ||
        no.length > 30 || isim.length > 100 || soyisim.length > 100) {
      throw const FormatException('Okul numarası, ad ve soyadı kontrol edin.');
    }
    final cinsiyetDegeri = cinsiyet?.trim() ?? '';
    if (cinsiyetDegeri.isNotEmpty && !const {'Kız', 'Erkek', 'Belirtilmedi'}.contains(cinsiyetDegeri)) {
      throw const FormatException('Cinsiyet seçimi geçersiz.');
    }
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    await db.transaction((tx) async {
      await _oturumKontrol(tx, oturum);
      if (!oturum.siniflar.any((e) => e.sinifSubeId == sinifId)) {
        throw StateError('Sınıf öğretmenin mevcut kapsamı dışında.');
      }
      final mevcut = await tx.query('Ogrenci', where: 'OkulNo=?', whereArgs: [no]);
      final simdi = DateTime.now().toUtc().toIso8601String();
      int ogrenciId;
      if (mevcut.isNotEmpty) {
        final o = mevcut.single;
        if ((o['Ad'] as String).trim().toLowerCase() != isim.toLowerCase() ||
            (o['Soyad'] as String).trim().toLowerCase() != soyisim.toLowerCase()) {
          throw StateError('Okul numarası başka bir öğrenciye ait. Kayıt birleştirilmedi.');
        }
        ogrenciId = o['OgrenciId'] as int;
        if (cinsiyetDegeri.isNotEmpty && cinsiyetDegeri != 'Belirtilmedi') {
          await tx.update('Ogrenci', {'Cinsiyet': cinsiyetDegeri, 'GuncellemeTarihi': simdi},
            where: 'OgrenciId=?', whereArgs: [ogrenciId]);
        }
        if (o['Aktif'] != 1) {
          await tx.update('Ogrenci', {'Aktif': 1, 'GuncellemeTarihi': simdi},
            where: 'OgrenciId=?', whereArgs: [ogrenciId]);
        }
      } else {
        ogrenciId = await tx.insert('Ogrenci', {
          'OkulNo': no, 'Ad': isim, 'Soyad': soyisim,
          'Cinsiyet': cinsiyetDegeri == 'Belirtilmedi' || cinsiyetDegeri.isEmpty ? null : cinsiyetDegeri,
          'Aktif': 1, 'OlusturmaTarihi': simdi,
        });
      }
      final kayitlar = await tx.query('OgrenciSinifKayit',
        where: 'OgrenciId=? AND EgitimOgretimYili=?',
        whereArgs: [ogrenciId, oturum.yil]);
      if (kayitlar.any((k) => k['SinifSubeId'] != sinifId && k['Aktif'] == 1)) {
        throw StateError('Öğrenci bu eğitim yılında başka aktif sınıfta. Önce mevcut kaydını kontrol edin.');
      }
      final eslesen = kayitlar.where((k) => k['SinifSubeId'] == sinifId).toList();
      if (eslesen.isEmpty) {
        await tx.insert('OgrenciSinifKayit', {
          'OgrenciId': ogrenciId, 'SinifSubeId': sinifId,
          'EgitimOgretimYili': oturum.yil,
          'Aktif': 1, 'OlusturmaTarihi': simdi,
        });
      } else if (eslesen.single['Aktif'] != 1) {
        await tx.update('OgrenciSinifKayit',
          {'Aktif': 1, 'GuncellemeTarihi': simdi},
          where: 'OgrenciSinifKayitId=?',
          whereArgs: [eslesen.single['OgrenciSinifKayitId']]);
      } else {
        throw StateError('Öğrenci seçilen sınıfta zaten kayıtlı.');
      }
      await _oturumKontrol(tx, oturum);
    });
  }

  /// Kimlik ve ilişkili belgeler korunur; yalnız belirtilen sınıf bağı kapatılır.
  static Future<void> siniftanCikar(BireyselListeOturumu oturum, {
    required int ogrenciId, required int sinifId,
  }) async {
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    await db.transaction((tx) async {
      await _oturumKontrol(tx, oturum);
      if (!oturum.siniflar.any((s) => s.sinifSubeId == sinifId)) {
        throw StateError('Sınıf erişim kapsamı dışında.');
      }
      final kapsamdakiler = await _ogrenciler(tx, oturum, sinifId);
      if (!kapsamdakiler.any((o) => o['OgrenciId'] == ogrenciId)) {
        throw StateError('Öğrenci artık bu sınıfın aktif listesinde değil.');
      }
      final sayi = await tx.update('OgrenciSinifKayit',
        {'Aktif': 0, 'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String()},
        where: 'OgrenciId=? AND SinifSubeId=? AND EgitimOgretimYili=? AND Aktif=1',
        whereArgs: [ogrenciId, sinifId, oturum.yil]);
      if (sayi != 1) throw StateError('Sınıf kaydı güncellenemedi.');
      await _oturumKontrol(tx, oturum);
    });
  }

  static Future<List<Map<String, Object?>>> ogrenciler(BireyselListeOturumu oturum, int? sinifId) async {
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    return db.transaction((txn) async {
      await _oturumKontrol(txn, oturum);
      return _ogrenciler(txn, oturum, sinifId);
    });
  }
  static Future<List<Map<String, Object?>>> _ogrenciler(
      DatabaseExecutor txn, BireyselListeOturumu oturum, int? sinifId) async {
      final ekSiniflar = oturum.ekSiniflariDahilEt
          ? await BireyselImportService.ogrenciEkSinifIdleriniGetir(txn, oturum.ogretmenId, oturum.yil)
          : const <int>{};
      final ekSinifKosulu = ekSiniflar.isEmpty ? ''
          : ' OR s.SinifSubeId IN (${List.filled(ekSiniflar.length, '?').join(',')})';
      return txn.rawQuery('''SELECT o.OgrenciId, o.OkulNo, o.Ad, o.Soyad, o.Cinsiyet,
        s.Alan, s.SinifKodu, f.FotoVerisi, f.DosyaYolu
        FROM Ogrenci o INNER JOIN OgrenciSinifKayit k ON k.OgrenciId = o.OgrenciId
        INNER JOIN SinifSube s ON s.SinifSubeId = k.SinifSubeId
        LEFT JOIN OgrenciFotograf f ON f.OgrenciId = o.OgrenciId AND f.Aktif = 1
        WHERE o.Aktif = 1 AND k.Aktif = 1 AND s.Aktif = 1
          AND (? IS NULL OR s.SinifSubeId = ?)
          AND k.EgitimOgretimYili = ? AND s.EgitimOgretimYili = ?
          AND (EXISTS (SELECT 1 FROM GecerliDersProgrami dp WHERE dp.SinifSubeId = s.SinifSubeId
            AND dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ? AND dp.Aktif = 1)$ekSinifKosulu)
        ORDER BY s.SinifSeviyesi, s.SinifKodu, CAST(o.OkulNo AS INTEGER), o.OkulNo, o.Ad, o.Soyad''',
        [sinifId, sinifId, oturum.yil, oturum.yil, oturum.ogretmenId, oturum.yil, ...ekSiniflar]);
  }
  static Future<Map<String, Object?>> ogrenciBilgileri(
      BireyselListeOturumu oturum, int ogrenciId) async {
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    return db.transaction((tx) async {
      await _oturumKontrol(tx, oturum);
      final kapsam = (await _ogrenciler(tx, oturum, null))
          .where((o) => o['OgrenciId'] == ogrenciId).toList();
      if (kapsam.isEmpty) throw StateError('Öğrenci mevcut sınıf kapsamınızda değil.');
      final ogrenci = (await tx.query('Ogrenci', where: 'OgrenciId=?',
          whereArgs: [ogrenciId])).single;
      final okul = await tx.query('OkulProfil', where: 'Id=1 AND AktifMi=1');
      if (okul.length != 1 || okul.single['OkulAdi'] != oturum.okul ||
          okul.single['EgitimYili'] != oturum.yil ||
          (oturum.okulId != null && okul.single['OkulId'] != oturum.okulId)) {
        throw StateError('Okul veya eğitim yılı değişti. Öğrencilerim ekranını yeniden açın.');
      }
      final ekler = await tx.rawQuery('''
        SELECT e.SoruId,e.Deger,s.Baslik,f.Baslik AS FormBaslik,y.OnayTarihi
        FROM OgrenciEkBilgiDeger e
        JOIN BilgiToplamaSoru s ON s.Id=e.SoruId AND s.FormId=e.FormId
        JOIN BilgiToplamaForm f ON f.Id=e.FormId
        JOIN BilgiToplamaYanit y ON y.Id=e.YanitId AND y.OgrenciId=e.OgrenciId
        WHERE e.OgrenciId=? AND f.OgretmenProfilId=? AND f.EgitimOgretimYili=?
          AND f.OkulId=? AND y.Durum='Onaylandi' AND y.OnaylayanProfilId=?
        ORDER BY y.OnayTarihi DESC,y.Id DESC
      ''', [ogrenciId, oturum.ogretmenId, oturum.yil,
        okul.single['OkulId'], oturum.ogretmenId]);
      final son = <Object?, Map<String, Object?>>{};
      for (final e in ekler) { son.putIfAbsent(e['SoruId'], () => e); }
      await _modKontrol();
      return {...VeliIliskisi.gorunum(ogrenci), 'SinifKodu': kapsam.first['SinifKodu'],
        'EkBilgiler': son.values.toList()};
    });
  }
  static Future<void> iletisimKaydet(BireyselListeOturumu oturum, int id,
      String kisi, Map<String, String> degerler,
      {required Map<String, Object?> onceki}) async {
    const alanlar = {
      'Ogrenci': ['Telefon'],
      'Anne': ['AnneAdi', 'AnneTelefon'],
      'Baba': ['BabaAdi', 'BabaTelefon'],
    };
    final izinli = alanlar[kisi];
    if (izinli == null || degerler.length != izinli.length ||
        !izinli.every(degerler.containsKey)) {
      throw const FormatException('İzin verilmeyen öğrenci bilgisi değişikliği.');
    }
    final temiz = degerler.map((k, v) => MapEntry(k, v.trim()));
    for (final e in temiz.entries) {
      final telefon = e.key.contains('Telefon');
      if (e.value.length > (telefon ? 50 : 200) ||
          (telefon && e.value.isNotEmpty && mesajTelefonNormalize(e.value) == null)) {
        throw const FormatException('Adı ve telefon numarasını kontrol edin.');
      }
    }
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    await db.transaction((tx) async {
      await _oturumKontrol(tx, oturum);
      final okul = await tx.query('OkulProfil', where: 'Id=1 AND AktifMi=1');
      if (okul.length != 1 || okul.single['OkulAdi'] != oturum.okul ||
          okul.single['EgitimYili'] != oturum.yil ||
          (oturum.okulId != null && okul.single['OkulId'] != oturum.okulId) ||
          !(await _ogrenciler(tx, oturum, null)).any((o) => o['OgrenciId'] == id)) {
        throw StateError('Öğrenci güncel okul ve ders kapsamınızda değil.');
      }
      final mevcut = (await tx.query('Ogrenci', where: 'OgrenciId=?', whereArgs: [id])).single;
      if (izinli.any((key) => (mevcut[key] ?? '').toString().trim() !=
          (onceki[key] ?? '').toString().trim())) {
        throw StateError('Bilgiler değişti. Ekranı yeniden açıp kontrol edin.');
      }
      await tx.update('Ogrenci', {...temiz,
        'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String()},
        where: 'OgrenciId=?', whereArgs: [id]);
      await _modKontrol();
      await _oturumKontrol(tx, oturum);
    });
  }
  static Future<void> veliKaydet(BireyselListeOturumu oturum, int id,
      String tur, {String? ad, String? telefon, Map<String, Object?>? onceki}) async {
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    await db.transaction((tx) async {
      await _oturumKontrol(tx, oturum);
      final okul = await tx.query('OkulProfil', where: 'Id=1 AND AktifMi=1');
      if (okul.length != 1 || okul.single['OkulAdi'] != oturum.okul ||
          okul.single['EgitimYili'] != oturum.yil ||
          (oturum.okulId != null && okul.single['OkulId'] != oturum.okulId) ||
          !(await _ogrenciler(tx, oturum, null)).any((o) => o['OgrenciId'] == id)) {
        throw StateError('Öğrenci güncel okul ve ders kapsamınızda değil.');
      }
      await VeliIliskisi.kaydet(tx, id, tur, ad: ad, telefon: telefon, onceki: onceki);
      await _modKontrol();
      await _oturumKontrol(tx, oturum);
    });
  }
  static Future<void> mudurKaydet(BireyselListeOturumu oturum, String mudur) async {
    await _modKontrol();
    final temizMudur = mudur.trim();
    if (temizMudur.length > 160) {
      throw const FormatException('Okul müdürü adı en fazla 160 karakter olmalı.');
    }
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      await _oturumKontrol(txn, oturum);
      final profil = await _profil(txn);
      if (_okulAdiNormalizeEt((profil['OkulAdi'] ?? '').toString()) !=
          _okulAdiNormalizeEt(oturum.okul)) {
        throw StateError('Okul değişti. Öğrencilerim ekranını yeniden açın.');
      }
      await BireyselOkulBilgiService.raporMuduruKaydet(txn,
        okulId: oturum.okulId, ogretmenId: oturum.ogretmenId,
        okulAdi: oturum.okul, mudur: temizMudur);
      await _modKontrol();
    });
  }
  static Future<List<RaporSablonu>> sablonlar(BireyselListeOturumu oturum) async {
    await _modKontrol();
    final db = await LocalDatabase.instance.database;
    await _oturumKontrol(db, oturum);
    final rows = await db.query('UygulamaAyarlari', where: 'Anahtar LIKE ?',
      whereArgs: ['liste_sablonu:${oturum.ogretmenId}:%'], orderBy: 'Anahtar');
    return rows.map((r) => RaporSablonu.fromJson(jsonDecode(r['Deger'] as String) as Map<String, dynamic>)).toList();
  }
  static Future<void> sablonKaydet(BireyselListeOturumu oturum, RaporSablonu sablon) async {
    await _modKontrol();
    sablon.dogrula();
    final snapshot = jsonEncode(sablon.toJson());
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      await _oturumKontrol(txn, oturum);
      await txn.insert('UygulamaAyarlari', {
        'Anahtar': 'liste_sablonu:${oturum.ogretmenId}:${Uri.encodeComponent(sablon.ad.trim().toLowerCase())}',
        'Deger': snapshot, 'GuncellemeTarihi': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
