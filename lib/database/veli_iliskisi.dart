import 'package:sqflite/sqflite.dart';
import '../models/mesajlasma.dart';

/// Anne/baba iletişimi kendi alanından okunur. Eski veli alanları yalnız
/// diğer kişiler ve kayıpsız eski veri uyumluluğu için korunur.
class VeliIliskisi {
  static const turler = {'Anne': 'Anne', 'Baba': 'Baba', 'Diger': 'Diğer veli'};
  static String _metin(Map o, String key) => (o[key] ?? '').toString().trim();
  static String tur(Map o) =>
      o['VeliTuru'] as String? ??
      (_metin(o, 'VeliAdi').isNotEmpty || _metin(o, 'VeliTelefonu').isNotEmpty
          ? 'Diger'
          : 'Anne');
  static String eskiTur(Map o) {
    final ad = _metin(o, 'VeliAdi'), tel = _metin(o, 'VeliTelefonu');
    if (ad.isEmpty && tel.isEmpty) return 'Anne';
    for (final parent in ['Anne', 'Baba']) {
      final parentAd = _metin(o, '${parent}Adi');
      final parentTel = mesajTelefonNormalize(_metin(o, '${parent}Telefon'));
      if (parentTel != null &&
          parentTel == mesajTelefonNormalize(tel) &&
          (ad.isEmpty ||
              ad == parentAd ||
              ad == (parent == 'Anne' ? 'Annesi' : 'Babası'))) {
        return parent;
      }
    }
    return 'Diger';
  }

  static Map<String, Object?> gorunum(Map<String, Object?> o) {
    final t = tur(o);
    return {
      ...o,
      'VeliTuru': t,
      'DigerVeliAdi': o['VeliAdi'],
      'DigerVeliTelefonu': o['VeliTelefonu'],
      'VeliAdi': t == 'Diger'
          ? o['VeliAdi']
          : (_metin(o, '${t}Adi').isEmpty
                ? (t == 'Anne' ? 'Annesi' : 'Babası')
                : o['${t}Adi']),
      'VeliTelefonu': t == 'Diger' ? o['VeliTelefonu'] : o['${t}Telefon'],
    };
  }

  static String turSql(String o) =>
      "COALESCE($o.VeliTuru, CASE WHEN "
      "TRIM(COALESCE($o.VeliAdi,''))<>'' OR TRIM(COALESCE($o.VeliTelefonu,''))<>'' "
      "THEN 'Diger' ELSE 'Anne' END)";
  static String adSql(String o) =>
      "CASE ${turSql(o)} WHEN 'Anne' THEN COALESCE(NULLIF(TRIM($o.AnneAdi),''),'Annesi') "
      "WHEN 'Baba' THEN COALESCE(NULLIF(TRIM($o.BabaAdi),''),'Babası') ELSE $o.VeliAdi END";
  static String telefonSql(String o) =>
      "CASE ${turSql(o)} WHEN 'Anne' THEN $o.AnneTelefon "
      "WHEN 'Baba' THEN $o.BabaTelefon ELSE $o.VeliTelefonu END";
  static Future<void> hazirla(DatabaseExecutor db) async {
    // Yerel v22/v23'te bu alan zaten vardır; GitHub v22'de bulunmaz.
    if ((await db.rawQuery(
      'PRAGMA table_info(Ogrenci)',
    )).any((c) => c['name'] == 'VeliTuru')) {
      return;
    }
    await db.execute(
      "ALTER TABLE Ogrenci ADD COLUMN VeliTuru TEXT CHECK(VeliTuru IN ('Anne','Baba','Diger'))",
    );
    for (final o in await db.query('Ogrenci')) {
      await db.update(
        'Ogrenci',
        {'VeliTuru': eskiTur(o)},
        where: 'OgrenciId=?',
        whereArgs: [o['OgrenciId']],
      );
    }
  }

  /// Yetki ve kapsam denetimi çağıran servisin transaction'ında yapılır.
  static Future<void> kaydet(
    DatabaseExecutor db,
    int id,
    String t, {
    String? ad,
    String? telefon,
    Map<String, Object?>? onceki,
  }) async {
    if (!turler.containsKey(t) ||
        (ad?.trim().length ?? 0) > 200 ||
        (telefon?.trim().length ?? 0) > 50 ||
        (telefon != null &&
            telefon.trim().isNotEmpty &&
            mesajTelefonNormalize(telefon) == null)) {
      throw const FormatException(
        'Veli ilişkisini ve telefonunu kontrol edin.',
      );
    }
    if (onceki != null) {
      final rows = await db.query(
        'Ogrenci',
        where: 'OgrenciId=?',
        whereArgs: [id],
      );
      if (rows.length != 1) throw StateError('Öğrenci kaydı bulunamadı.');
      final mevcut = gorunum(rows.single);
      final alanlar = [
        'VeliTuru',
        if (t == 'Diger') ...[
          'DigerVeliAdi',
          'DigerVeliTelefonu',
        ] else ...[
          '${t}Adi',
          '${t}Telefon',
        ],
      ];
      if (alanlar.any((key) => _metin(mevcut, key) != _metin(onceki, key))) {
        throw StateError(
          'Veli bilgileri değişti. Ekranı yeniden açıp kontrol edin.',
        );
      }
    }
    await db.update(
      'Ogrenci',
      {
        'VeliTuru': t,
        if (t == 'Diger') 'VeliAdi': ad?.trim() ?? '',
        if (t == 'Diger') 'VeliTelefonu': telefon?.trim() ?? '',
        if (t != 'Diger' && ad != null) '${t}Adi': ad.trim(),
        if (t != 'Diger' && telefon != null) '${t}Telefon': telefon.trim(),
        'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'OgrenciId=?',
      whereArgs: [id],
    );
  }
}
