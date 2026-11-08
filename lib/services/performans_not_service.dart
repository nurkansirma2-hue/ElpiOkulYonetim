part of 'bireysel_odev_kontrol_service.dart';

/// Dönem sonu değerlendirmesi; görev tanımına P1/P2 alanı yazmaz.
class PerformansNotService {
  static Future<List<String>> yillar(
    BireyselListeOturumu o,
  ) => BireyselOdevKontrolService._islem('Yıllar okunamadı.', o, (db) async {
    final rows = await db.rawQuery(
      'SELECT EgitimOgretimYili FROM OdevTanim WHERE OgretmenProfilId=? UNION SELECT EgitimOgretimYili FROM PerformansTanim WHERE OgretmenProfilId=?',
      [o.ogretmenId, o.ogretmenId],
    );
    return {
      o.yil,
      ...rows.map((r) => r['EgitimOgretimYili'] as String),
    }.toList()..sort((a, b) => b.compareTo(a));
  });
  static Future<List<Map<String, Object?>>> gecmisDersler(
    BireyselListeOturumu o,
    String yil,
  ) => BireyselOdevKontrolService._islem(
    'Geçmiş dersler okunamadı.',
    o,
    (db) => db.rawQuery(
      'SELECT DISTINCT x.SinifSubeId,s.SinifKodu,x.DersId,d.DersAdi FROM (SELECT SinifSubeId,DersId FROM OdevTanim WHERE OgretmenProfilId=? AND EgitimOgretimYili=? UNION SELECT SinifSubeId,DersId FROM PerformansTanim WHERE OgretmenProfilId=? AND EgitimOgretimYili=?) x JOIN SinifSube s ON s.SinifSubeId=x.SinifSubeId JOIN Ders d ON d.DersId=x.DersId ORDER BY s.SinifKodu,d.DersAdi',
      [o.ogretmenId, yil, o.ogretmenId, yil],
    ),
  );

  static Future<Map<String, Object?>> _tanim(
    DatabaseExecutor db,
    BireyselListeOturumu o,
    int sinif,
    int ders,
    int donem,
    int grup, {
    String? yil,
  }) async {
    yil ??= o.yil;
    if (![1, 2].contains(donem) || ![1, 2].contains(grup)) {
      throw ArgumentError('Dönem ve performans grubu 1 veya 2 olmalıdır.');
    }
    if (yil == o.yil && !o.siniflar.any((s) => s.sinifSubeId == sinif)) {
      throw StateError('Sınıf ders kapsamınızda değil.');
    }
    final rows = await db.query(
      'PerformansTanim',
      where:
          'OgretmenProfilId=? AND EgitimOgretimYili=? AND SinifSubeId=? AND DersId=? AND Donem=? AND Grup=?',
      whereArgs: [o.ogretmenId, yil, sinif, ders, donem, grup],
    );
    if (rows.isNotEmpty) return rows.single;
    if (yil == o.yil) {
      await BireyselOdevKontrolService._dersKontrol(db, o, sinif, ders);
    } else if ((await db.query(
      'OdevTanim',
      columns: ['OdevId'],
      where:
          'OgretmenProfilId=? AND EgitimOgretimYili=? AND SinifSubeId=? AND DersId=?',
      whereArgs: [o.ogretmenId, yil, sinif, ders],
    )).isEmpty) {
      throw StateError('Bu yılda size ait ders/sınıf kaydı yok.');
    }

    return {
      'Id': 0,
      'OgretmenProfilId': o.ogretmenId,
      'EgitimOgretimYili': yil,
      'SinifSubeId': sinif,
      'DersId': ders,
      'Donem': donem,
      'Grup': grup,
      'Surum': 0,
      'Kriterler': jsonEncode(
        performansKriterSablonlari[grup]!.map((k) => k.json).toList(),
      ),
      'OdevAgirligi': null,
    };
  }

  static Future<PerformansVerisi> oku(
    BireyselListeOturumu o,
    int sinif,
    int ders,
    int donem,
    int grup, {
    String? yil,
  }) => BireyselOdevKontrolService._islem(
    'Performans notları okunamadı.',
    o,
    (db) => _oku(db, o, sinif, ders, donem, grup, yil: yil),
  );

  static Future<PerformansVerisi> _oku(
    DatabaseExecutor db,
    BireyselListeOturumu o,
    int sinif,
    int ders,
    int donem,
    int grup, {
    String? yil,
  }) async {
    yil ??= o.yil;
    final t = await _tanim(db, o, sinif, ders, donem, grup, yil: yil);
    final kriterler = (jsonDecode(t['Kriterler'] as String) as List)
        .map((r) => PerformansKriteri.oku(r as Map))
        .toList();
    if (kriterler.fold<int>(0, (a, k) => a + k.azami) != 100) {
      throw StateError('Kriter şablonu toplamı 100 olmalıdır.');
    }
    final gorevler = (await db.query(
      'OdevTanim',
      where:
          'OgretmenProfilId=? AND EgitimOgretimYili=? AND SinifSubeId=? AND DersId=? AND (Donem=? OR Donem IS NULL)',
      whereArgs: [o.ogretmenId, yil, sinif, ders, donem],
      orderBy: 'BaslangicTarihi,OdevId',
    )).map(OdevTanim.fromMap).toList();
    final secilen = (await db.query(
      'PerformansOdev',
      where: 'PerformansId=?',
      whereArgs: [t['Id']],
      orderBy: 'OdevId',
    )).map((r) => r['OdevId'] as int).toSet();
    if (!gorevler.map((g) => g.odevId).toSet().containsAll(secilen)) {
      throw StateError(
        'Seçili ödevin ders/sınıf/dönemi değişmiş; ödev seçimini yenileyin.',
      );
    }
    final kayitlar = await db.query(
      'PerformansSonuc',
      where: 'PerformansId=?',
      whereArgs: [t['Id']],
    );
    final ogrenciler = await db.rawQuery(
      '''SELECT DISTINCT x.OgrenciId,x.OkulNo,x.Ad,x.Soyad
      FROM Ogrenci x WHERE x.OgrenciId IN (
        SELECT OgrenciId FROM OgrenciSinifKayit WHERE SinifSubeId=? AND EgitimOgretimYili=? ${yil == o.yil ? 'AND Aktif=1' : ''}
        UNION SELECT OgrenciId FROM PerformansSonuc WHERE PerformansId=?
        UNION SELECT k.OgrenciId FROM OdevOgrenci k JOIN PerformansOdev p ON p.OdevId=k.OdevId WHERE p.PerformansId=?)
      ORDER BY CAST(x.OkulNo AS INTEGER),x.OkulNo,x.Ad,x.Soyad''',
      [sinif, yil, t['Id'], t['Id']],
    );
    final sonucRows = await db.rawQuery(
      '''SELECT s.* FROM OdevKontrolSonuc s
      JOIN OdevKontrol k ON k.OdevKontrolId=s.OdevKontrolId
      JOIN PerformansOdev p ON p.OdevId=s.OdevId
      WHERE p.PerformansId=? AND k.Aktif=1 ORDER BY s.OgrenciId,s.OdevId,s.OdevKontrolId''',
      [t['Id']],
    );
    final katilimlar = (await db.rawQuery(
      'SELECT k.OdevId,k.OgrenciId FROM OdevOgrenci k JOIN PerformansOdev p ON p.OdevId=k.OdevId WHERE p.PerformansId=?',
      [t['Id']],
    )).map((r) => '${r['OdevId']}/${r['OgrenciId']}').toSet();
    final ogrenciSonuclari = <PerformansOgrenciSonucu>[];
    for (final ogrenci in ogrenciler) {
      final id = ogrenci['OgrenciId'];
      final saved = kayitlar.where((r) => r['OgrenciId'] == id).firstOrNull;
      final rows = sonucRows.where((r) => r['OgrenciId'] == id).toList();
      final puan = OdevPuanOzeti.hesapla([
        for (final gid in secilen.where((g) => katilimlar.contains('$g/$id')))
          rows.where((r) => r['OdevId'] == gid).map(OdevKontrolSonuc.fromMap),
      ]);
      final kp = saved == null
          ? <String, int?>{}
          : Map<String, int?>.from(
              jsonDecode(saved['KriterPuanlari'] as String) as Map,
            );
      final kpTam = kriterler.every((k) => kp[k.id] != null);
      final kriterPuani = kpTam
          ? kriterler.fold<int>(0, (a, k) => a + kp[k.id]!)
          : null;
      final agirlik = t['OdevAgirligi'] as int?;
      int? oneri;
      if (agirlik != null &&
          (agirlik == 0 || (puan.puan != null && puan.bos == 0)) &&
          (agirlik == 100 || kriterPuani != null)) {
        oneri =
            ((puan.puan ?? 0) * agirlik / 100 +
                    (kriterPuani ?? 0) * (100 - agirlik) / 100)
                .round();
      }
      final imza = jsonEncode([
        t['Surum'],
        t['Kriterler'],
        t['OdevAgirligi'],
        secilen.toList(),
        rows
            .map((r) => [r['OdevKontrolSonucId'], r['Durum'], r['NotDegeri']])
            .toList(),
        [for (final k in kriterler) kp[k.id]],
      ]);
      ogrenciSonuclari.add(
        PerformansOgrenciSonucu(
          ogrenci: ogrenci,
          odev: puan,
          kriterPuanlari: kp,
          kriterPuani: kriterPuani,
          oneri: oneri,
          nihai: saved?['NihaiPuan'] as int?,
          imza: imza,
          guncel: saved?['KaynakImza'] == imza,
        ),
      );
    }
    return PerformansVerisi(t, kriterler, gorevler, secilen, ogrenciSonuclari);
  }

  static Future<int> _yazmaTanimi(
    DatabaseExecutor db,
    BireyselListeOturumu o,
    PerformansVerisi p,
  ) async {
    final t = p.tanim;
    if (t['EgitimOgretimYili'] != o.yil) {
      throw StateError('Geçmiş eğitim yılı salt okunurdur.');
    }
    final simdi = await _tanim(
      db,
      o,
      t['SinifSubeId'] as int,
      t['DersId'] as int,
      t['Donem'] as int,
      t['Grup'] as int,
    );
    if (simdi['Id'] != t['Id'] || simdi['Surum'] != t['Surum']) {
      throw StateError('Performans ayarları değişti. Ekranı yenileyin.');
    }
    await BireyselOdevKontrolService._dersKontrol(
      db,
      o,
      t['SinifSubeId'] as int,
      t['DersId'] as int,
    );
    if (t['Id'] != 0) return t['Id'] as int;
    return db.insert('PerformansTanim', {...t, 'Id': null});
  }

  static Future<void> odevleriSec(
    BireyselListeOturumu o,
    PerformansVerisi p,
    Set<int> ids,
  ) {
    final secilen = Set<int>.of(ids);
    return BireyselOdevKontrolService._islem(
      'Performans ödev seçimi kaydedilemedi.',
      o,
      (db) async {
        final id = await _yazmaTanimi(db, o, p);
        final t = p.tanim;
        final guncel = await _oku(
          db,
          o,
          t['SinifSubeId'] as int,
          t['DersId'] as int,
          t['Donem'] as int,
          t['Grup'] as int,
        );
        if (!guncel.odevler.map((g) => g.odevId).toSet().containsAll(secilen)) {
          throw StateError('Ödevler bu performans kapsamına ait değil.');
        }
        if (guncel.odevler.any((g) => g.dersUygulamalari && secilen.contains(g.odevId))) {
          throw StateError('Ders Uygulamaları için P1/P2 bağlantısı henüz açık değil.');
        }
        await db.delete(
          'PerformansOdev',
          where: 'PerformansId=?',
          whereArgs: [id],
        );
        for (final gid in secilen) {
          await db.insert('PerformansOdev', {
            'PerformansId': id,
            'OdevId': gid,
          });
        }
        await db.update(
          'PerformansTanim',
          {'Surum': (p.tanim['Surum'] as int) + 1},
          where: 'Id=?',
          whereArgs: [id],
        );
      },
    );
  }

  static Future<void> agirlikKaydet(
    BireyselListeOturumu o,
    PerformansVerisi p,
    int? agirlik,
  ) => BireyselOdevKontrolService._islem('Ağırlık kaydedilemedi.', o, (
    db,
  ) async {
    if (agirlik != null && (agirlik < 0 || agirlik > 100)) {
      throw ArgumentError('Ağırlık 0–100 olmalıdır.');
    }
    final id = await _yazmaTanimi(db, o, p);
    await db.update(
      'PerformansTanim',
      {'OdevAgirligi': agirlik, 'Surum': (p.tanim['Surum'] as int) + 1},
      where: 'Id=?',
      whereArgs: [id],
    );
  });

  static Future<void> kriterKaydet(
    BireyselListeOturumu o,
    PerformansVerisi p,
    PerformansOgrenciSonucu ogrenci,
    Map<String, int?> puanlar,
  ) {
    final copy = Map<String, int?>.of(puanlar);
    return BireyselOdevKontrolService._islem(
      'Kriter puanları kaydedilemedi.',
      o,
      (db) async {
        final id = await _yazmaTanimi(db, o, p);
        final t = p.tanim;
        final simdi = await _oku(
          db,
          o,
          t['SinifSubeId'] as int,
          t['DersId'] as int,
          t['Donem'] as int,
          t['Grup'] as int,
        );
        final anlik = simdi.ogrenciler
            .where(
              (s) => s.ogrenci['OgrenciId'] == ogrenci.ogrenci['OgrenciId'],
            )
            .single;
        if (anlik.imza != ogrenci.imza) {
          throw StateError(
            'Öğrenci değerlendirmesi değişti. Ekranı yenileyin.',
          );
        }
        if (copy.keys.any((k) => !p.kriterler.any((c) => c.id == k)) ||
            p.kriterler.any(
              (k) =>
                  copy[k.id] != null &&
                  (copy[k.id]! < 0 || copy[k.id]! > k.azami),
            )) {
          throw ArgumentError('Kriter puanları azami değeri aşamaz.');
        }
        final mevcut = await db.query(
          'PerformansSonuc',
          where: 'PerformansId=? AND OgrenciId=?',
          whereArgs: [id, ogrenci.ogrenci['OgrenciId']],
        );
        final veri = {
          'KriterPuanlari': jsonEncode(copy),
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        };
        if (mevcut.isEmpty) {
          await db.insert('PerformansSonuc', {
            'PerformansId': id,
            'OgrenciId': ogrenci.ogrenci['OgrenciId'],
            ...veri,
          });
        } else {
          await db.update(
            'PerformansSonuc',
            veri,
            where: 'PerformansId=? AND OgrenciId=?',
            whereArgs: [id, ogrenci.ogrenci['OgrenciId']],
          );
        }
      },
    );
  }

  static Future<void> notlariKaydet(
    BireyselListeOturumu o,
    PerformansVerisi p,
    Map<int, int?> notlar,
  ) {
    final copy = Map<int, int?>.of(notlar);
    return BireyselOdevKontrolService._islem(
      'Performans notları kaydedilemedi.',
      o,
      (db) => _notlariYaz(db, o, p, copy),
    );
  }

  static Future<void> _notlariYaz(
    DatabaseExecutor db,
    BireyselListeOturumu o,
    PerformansVerisi p,
    Map<int, int?> copy,
  ) async {
    if (copy.values.any((n) => n != null && (n < 0 || n > 100))) {
      throw ArgumentError('Nihai not 0–100 olmalıdır.');
    }
    final id = await _yazmaTanimi(db, o, p);
    final t = p.tanim;
    final simdi = await _oku(
      db,
      o,
      t['SinifSubeId'] as int,
      t['DersId'] as int,
      t['Donem'] as int,
      t['Grup'] as int,
    );
    for (final e in copy.entries) {
      final onceki = p.ogrenciler
          .where((s) => s.ogrenci['OgrenciId'] == e.key)
          .single;
      final s = simdi.ogrenciler
          .where((s) => s.ogrenci['OgrenciId'] == e.key)
          .single;
      if (s.imza != onceki.imza) {
        throw StateError('Puanlar değişti. Yeniden hesaplayıp kaydedin.');
      }
      final row = {
        'PerformansId': id,
        'OgrenciId': e.key,
        'KriterPuanlari': jsonEncode(s.kriterPuanlari),
        'OdevPuani': s.odev.puan,
        'KriterPuani': s.kriterPuani,
        'OneriPuani': s.oneri,
        'NihaiPuan': e.value,
        'KaynakImza': s.imza,
        'GuncellemeTarihi': DateTime.now().toIso8601String(),
      };
      final eski = await db.query(
        'PerformansSonuc',
        where: 'PerformansId=? AND OgrenciId=?',
        whereArgs: [id, e.key],
      );
      if (eski.isEmpty) {
        await db.insert('PerformansSonuc', row);
      } else {
        await db.update(
          'PerformansSonuc',
          row,
          where: 'PerformansId=? AND OgrenciId=?',
          whereArgs: [id, e.key],
        );
      }
    }
  }

  static Future<void> topluNotKaydet(
    BireyselListeOturumu o,
    List<({PerformansVerisi veri, Map<int, int?> notlar})> giris,
  ) {
    final copy = [
      for (final g in giris)
        (veri: g.veri, notlar: Map<int, int?>.of(g.notlar)),
    ];
    return BireyselOdevKontrolService._islem(
      'Performans notları kaydedilemedi. İşlem geri alındı.',
      o,
      (db) async {
        for (final g in copy) {
          await _notlariYaz(db, o, g.veri, g.notlar);
        }
      },
    );
  }

  static Future<String?> excelAktar(
    BireyselListeOturumu o,
    int sinif,
    int ders,
    int donem, {
    String? yil,
  }) async {
    final p1 = await oku(o, sinif, ders, donem, 1, yil: yil),
        p2 = await oku(o, sinif, ders, donem, 2, yil: yil);
    final excel = BireyselOdevKontrolService._excelOlustur('Performans');
    final sheet = excel['Performans'];
    sheet.appendRow([
      'Öğretmen',
      o.ogretmen,
      'Yıl',
      yil ?? o.yil,
      'Dönem',
      donem,
    ]);
    sheet.appendRow(['Öğrenci', 'P1', 'P2', 'Durum']);
    final ids = {
      ...p1.ogrenciler.map((s) => s.ogrenci['OgrenciId']),
      ...p2.ogrenciler.map((s) => s.ogrenci['OgrenciId']),
    };
    for (final id in ids) {
      final a = p1.ogrenciler
          .where((s) => s.ogrenci['OgrenciId'] == id)
          .firstOrNull;
      final b = p2.ogrenciler
          .where((s) => s.ogrenci['OgrenciId'] == id)
          .firstOrNull;
      final ogr = a?.ogrenci ?? b!.ogrenci;
      sheet.appendRow([
        '${ogr['OkulNo']} • ${ogr['Ad']} ${ogr['Soyad']}',
        a?.nihai ?? '',
        b?.nihai ?? '',
        a?.guncel == true &&
                b?.guncel == true &&
                a?.nihai != null &&
                b?.nihai != null
            ? 'Tamam'
            : 'Eksik / yeniden kontrol edin',
      ]);
    }
    BireyselOdevKontrolService._excelBicimle(excel, sheet, 1, 4);
    return BireyselOdevKontrolService._excelKaydet(excel, 'Performans_Notlari');
  }
}

class OdevDosyaService {
  static Future<List<Map<String, Object?>>> liste(
    BireyselListeOturumu o,
    int id,
  ) => BireyselOdevKontrolService._islem('Ekler okunamadı.', o, (db) async {
    await BireyselOdevKontrolService._gorev(db, o, id);
    return db.query(
      'OdevEk',
      columns: ['Id', 'DosyaAdi', 'OdevKontrolSonucId'],
      where: 'OdevId=?',
      whereArgs: [id],
    );
  });
  static Future<Map<String, Object?>> oku(
    BireyselListeOturumu o,
    int id,
    int ekId,
  ) => BireyselOdevKontrolService._islem('Ek okunamadı.', o, (db) async {
    await BireyselOdevKontrolService._gorev(db, o, id);
    return (await db.query(
      'OdevEk',
      where: 'Id=? AND OdevId=?',
      whereArgs: [ekId, id],
    )).single;
  });
  static Future<void> ekle(
    BireyselListeOturumu o,
    int id,
    String ad,
    Uint8List bytes, {
    int? sonucId,
  }) {
    final veri = Uint8List.fromList(bytes);
    return BireyselOdevKontrolService._islem('Ek kaydedilemedi.', o, (
      db,
    ) async {
      await BireyselOdevKontrolService._gorev(db, o, id, yazma: true);
      if (veri.isEmpty ||
          veri.length > 10485760 ||
          ad.trim().isEmpty ||
          ad.trim() == '.' ||
          ad.trim() == '..' ||
          ad.length > 200 ||
          ad.contains('/') ||
          ad.contains('\\')) {
        throw ArgumentError(
          'Dosya adı geçersiz veya dosya 10 MB sınırını aşıyor.',
        );
      }
      if (sonucId != null &&
          (await db.query(
                'OdevKontrolSonuc',
                where: 'OdevId=? AND OdevKontrolSonucId=?',
                whereArgs: [id, sonucId],
              )).length !=
              1) {
        throw StateError('Öğrenci sonucu ödeve ait değil.');
      }
      await db.insert('OdevEk', {
        'OdevId': id,
        'OdevKontrolSonucId': sonucId,
        'DosyaAdi': ad,
        'Veri': veri,
      });
    });
  }

  static Future<void> sil(BireyselListeOturumu o, int id, int ekId) =>
      BireyselOdevKontrolService._islem('Ek silinemedi.', o, (db) async {
        await BireyselOdevKontrolService._gorev(db, o, id, yazma: true);
        await db.delete(
          'OdevEk',
          where: 'Id=? AND OdevId=?',
          whereArgs: [ekId, id],
        );
      });
}
