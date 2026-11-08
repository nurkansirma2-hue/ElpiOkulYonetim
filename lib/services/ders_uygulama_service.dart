part of 'bireysel_odev_kontrol_service.dart';

/// Aynı mod/öğretmen/yıl ve transaction kurallarıyla ortak uygulama işlemleri.
extension DersUygulamaIslemleri on BireyselOdevKontrolService {
  static Future<OdevTanim> _gorev(
    DatabaseExecutor db,
    BireyselListeOturumu o,
    int id, {
    bool yazma = false,
  }) async {
    final g = await BireyselOdevKontrolService._gorev(db, o, id, yazma: yazma);
    if (!g.dersUygulamalari) {
      throw StateError('Bu görev Ders Uygulamaları türünde değil.');
    }
    for (final table in ['OdevUygulama', 'OdevUygulamaSonuc']) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((c) => c['name'] == 'Adet')) {
        await db.execute(
          "ALTER TABLE $table ADD COLUMN Adet INTEGER ${table == 'OdevUygulama' ? 'NOT NULL DEFAULT 1' : ''} CHECK(Adet > 0)",
        );
      }
      if (table == 'OdevUygulamaSonuc' &&
          !columns.any((c) => c['name'] == 'Yapilan')) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN Yapilan INTEGER CHECK(Yapilan >= 0 AND Yapilan <= Adet)',
        );
      }
    }
    return g;
  }

  static String _ad(String ad) {
    final s = ad.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty || s.length > 150) {
      throw ArgumentError('Uygulama adı 1–150 karakter olmalıdır.');
    }
    return s;
  }

  static String _anahtar(String ad) =>
      _ad(ad).replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  static Future<int> uygulamaKaydet(
    BireyselListeOturumu o,
    int odevId,
    String ad, {
    int? uygulamaId,
  }) => BireyselOdevKontrolService._islem('Uygulama kaydedilemedi.', o, (
    db,
  ) async {
    await _gorev(db, o, odevId, yazma: true);
    final adMetni = _ad(ad), anahtar = _anahtar(ad);
    final tekrar = await db.query(
      'OdevUygulama',
      where: 'OdevId=? AND AdAnahtari=?',
      whereArgs: [odevId, anahtar],
    );
    if (tekrar.any((r) => r['UygulamaId'] != uygulamaId)) {
      throw StateError('Bu uygulama zaten var; pasifse yeniden etkinleştirin.');
    }
    if (uygulamaId != null) {
      if (await db.update(
            'OdevUygulama',
            {'Ad': adMetni, 'AdAnahtari': anahtar},
            where: 'OdevId=? AND UygulamaId=?',
            whereArgs: [odevId, uygulamaId],
          ) !=
          1) {
        throw StateError('Uygulama bu ödeve ait değil.');
      }
      return uygulamaId;
    }
    final sira = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COALESCE(MAX(Sira),0)+1 FROM OdevUygulama WHERE OdevId=?',
        [odevId],
      ),
    )!;
    return db.insert('OdevUygulama', {
      'OdevId': odevId,
      'Ad': adMetni,
      'AdAnahtari': anahtar,
      'Sira': sira,
    });
  });

  static Future<void> adetKaydet(
    BireyselListeOturumu o,
    int odevId,
    int id,
    int adet,
  ) => BireyselOdevKontrolService._islem('Adet kaydedilemedi.', o, (db) async {
    await _gorev(db, o, odevId, yazma: true);
    if (adet < 1 || adet > 10000) {
      throw ArgumentError('Adet 1–10000 arasında olmalıdır.');
    }
    if (await db.update(
          'OdevUygulama',
          {'Adet': adet},
          where: 'OdevId=? AND UygulamaId=? AND Aktif=1',
          whereArgs: [odevId, id],
        ) !=
        1) {
      throw StateError('Aktif uygulama bulunamadı.');
    }
  });

  /// Geçmiş sonuçlar silinmez. UI, pasifleştirme öncesinde kullanıcıyı bilgilendirir.
  static Future<void> uygulamaAktifligi(
    BireyselListeOturumu o,
    int odevId,
    int uygulamaId,
    bool aktif,
  ) => BireyselOdevKontrolService._islem(
    'Uygulama durumu değiştirilemedi.',
    o,
    (db) async {
      await _gorev(db, o, odevId, yazma: true);
      if (await db.update(
            'OdevUygulama',
            {'Aktif': aktif ? 1 : 0},
            where: 'OdevId=? AND UygulamaId=?',
            whereArgs: [odevId, uygulamaId],
          ) !=
          1) {
        throw StateError('Uygulama bulunamadı.');
      }
    },
  );

  static Future<List<DersUygulamasi>> uygulamalar(
    BireyselListeOturumu o,
    int odevId,
  ) => BireyselOdevKontrolService._islem('Uygulamalar okunamadı.', o, (
    db,
  ) async {
    await _gorev(db, o, odevId);
    return (await db.query(
      'OdevUygulama',
      where: 'OdevId=?',
      whereArgs: [odevId],
      orderBy: 'Sira',
    )).map(DersUygulamasi.fromMap).toList();
  });

  static Future<void> sonuclariKaydet(
    BireyselListeOturumu o,
    int kontrolId,
    List<UygulamaSonucGirdisi> girdiler,
  ) {
    final kayitlar = List<UygulamaSonucGirdisi>.of(girdiler);
    return BireyselOdevKontrolService._islem(
      'Uygulama sonuçları kaydedilemedi.',
      o,
      (db) async {
        final k = await BireyselOdevKontrolService._kontrol(
          db,
          o,
          kontrolId,
          yazma: true,
        );
        await _gorev(db, o, k.odevId, yazma: true);
        final tekil = <String>{};
        for (final s in kayitlar) {
          if (!tekil.add('${s.ogrenciId}/${s.uygulamaId}')) {
            throw ArgumentError('Aynı öğrenci ve uygulama tekrarlanamaz.');
          }
          final u = await db.query(
            'OdevUygulama',
            where: 'UygulamaId=? AND OdevId=? AND Aktif=1',
            whereArgs: [s.uygulamaId, k.odevId],
          );
          final katilim = await db.query(
            'OdevOgrenci',
            where: 'OdevId=? AND OgrenciId=? AND Aktif=1',
            whereArgs: [k.odevId, s.ogrenciId],
          );
          final kontrolKatilimi = await db.query(
            'OdevKontrolSonuc',
            where: 'OdevKontrolId=? AND OgrenciId=?',
            whereArgs: [kontrolId, s.ogrenciId],
          );
          if (u.isEmpty || katilim.isEmpty || kontrolKatilimi.isEmpty) {
            throw StateError(
              'Uygulama veya öğrenci bu aktif kontrole ait değil.',
            );
          }
          final n = s.notDegeri ?? OdevKontrolSonuc.hizliNot(s.durum);
          if (s.durum == OdevKontrolDurumu.manuel &&
                  (n == null || n < 0 || n > 10) ||
              s.durum.bekliyor && n != null ||
              n != null && (n < 0 || n > 10)) {
            throw ArgumentError('Geçersiz uygulama puanı.');
          }
          // Eski Gelmedi/Mazeretli durumları null puanla aynen korunur.
          if (n != null &&
              s.durum != OdevKontrolDurumu.manuel &&
              n != OdevKontrolSonuc.hizliNot(s.durum)) {
            throw ArgumentError('Puan ve durum çelişiyor.');
          }
          if ((s.yapilan == null) != (s.adet == null) ||
              s.adet != null &&
                  (s.adet! < 1 || s.yapilan! < 0 || s.yapilan! > s.adet!)) {
            throw ArgumentError(
              'Yapılan sayısı 0 ile adet arasında olmalıdır.',
            );
          }
          final veri = <String, Object?>{
            'Yapilan': s.yapilan,
            'Adet': s.adet,
            'OdevId': k.odevId,
            'UygulamaId': s.uygulamaId,
            'OdevKontrolId': kontrolId,
            'OgrenciId': s.ogrenciId,
            'Durum': s.durum.kayitDegeri,
            'NotDegeri': n,
            'Aciklama': BireyselOdevKontrolService._metin(s.aciklama),
            'GuncellemeTarihi': DateTime.now().toIso8601String(),
          };
          final adet = await db.update(
            'OdevUygulamaSonuc',
            veri,
            where: 'OdevKontrolId=? AND OgrenciId=? AND UygulamaId=?',
            whereArgs: [kontrolId, s.ogrenciId, s.uygulamaId],
          );
          if (adet == 0) await db.insert('OdevUygulamaSonuc', veri);
        }
      },
    );
  }

  static Future<List<UygulamaSonucu>> gecmis(
    BireyselListeOturumu o,
    int odevId, {
    int? ogrenciId,
    int? kontrolId,
    bool guncel = false,
  }) => BireyselOdevKontrolService._islem('Uygulama geçmişi okunamadı.', o, (
    db,
  ) async {
    await _gorev(db, o, odevId);
    OdevKontrol? sinir;
    if (kontrolId != null) {
      sinir = await BireyselOdevKontrolService._kontrol(db, o, kontrolId);
      if (sinir.odevId != odevId) {
        throw StateError('Kontrol bu ödeve ait değil.');
      }
    }
    final rows = await db.rawQuery(
      '''SELECT s.*,k.KontrolTarihi,k.SiraNo FROM OdevUygulamaSonuc s
        JOIN OdevKontrol k ON k.OdevKontrolId=s.OdevKontrolId AND k.OdevId=s.OdevId
        WHERE s.OdevId=? ${ogrenciId == null ? '' : 'AND s.OgrenciId=?'}
        ${guncel ? 'AND k.Aktif=1' : ''}
        ORDER BY k.KontrolTarihi,k.SiraNo,k.OdevKontrolId''',
      [odevId, if (ogrenciId != null) ogrenciId],
    );
    final son = <String, UygulamaSonucu>{}, tum = <UygulamaSonucu>[];
    for (final r in rows) {
      if (sinir != null) {
        final fark = (r['KontrolTarihi'] as String).compareTo(
          odevTarihYaz(sinir.kontrolTarihi),
        );
        if (fark > 0 || fark == 0 && (r['SiraNo'] as int) > sinir.siraNo) {
          continue;
        }
      }
      final s = UygulamaSonucu.fromMap(r);
      tum.add(s);
      son['${s.ogrenciId}/${s.uygulamaId}'] = s;
    }
    return guncel ? son.values.toList() : tum;
  });
}
